#!/usr/bin/env python3
"""Raw WebSocket capture of a GaggiMate (simulator or real machine).

No dependencies on purpose: GaggiMate speaks a plain WebSocket (no
Socket.IO); the handshake and frame format fit into the standard library,
so the script runs on a fresh machine without pip.

    python3 tool/gaggimate_ws_capture.py --host localhost:8080 --seconds 30 \
        --out capture.jsonl --send req:profiles:list

Each output line is a JSON object:
    {"t": <seconds since start>, "dir": "in"|"out", "msg": {...}}
"""

import argparse
import base64
import json
import os
import socket
import struct
import sys
import time


def handshake(sock, host, path):
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(request.encode())
    # Antwortkopf bis zur Leerzeile lesen, den Rest als ersten Puffer behalten.
    buffer = b""
    while b"\r\n\r\n" not in buffer:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Verbindung waehrend des Handshakes beendet")
        buffer += chunk
    head, _, rest = buffer.partition(b"\r\n\r\n")
    status = head.split(b"\r\n", 1)[0].decode(errors="replace")
    if "101" not in status:
        raise ConnectionError(f"Kein Upgrade: {status}")
    return rest


def mask(payload):
    key = os.urandom(4)
    return key + bytes(b ^ key[i % 4] for i, b in enumerate(payload))


def send_text(sock, text):
    payload = text.encode()
    header = bytes([0x81])
    length = len(payload)
    if length < 126:
        header += bytes([0x80 | length])
    elif length < (1 << 16):
        header += bytes([0x80 | 126]) + struct.pack(">H", length)
    else:
        header += bytes([0x80 | 127]) + struct.pack(">Q", length)
    sock.sendall(header + mask(payload))


def send_close(sock):
    """Close politely: a masked close frame (opcode 0x8, empty payload)
    before sock.close(). Without it the simulator keeps writing into the
    dropped connection and dies of SIGPIPE (EXIT=141), so it would need a
    restart after every capture."""
    try:
        sock.sendall(bytes([0x88, 0x80]) + mask(b""))
    except OSError:
        pass  # The other side is already gone; nothing left to say.


class FrameReader:
    """Splits the byte stream into frames. The GaggiMate firmware does not
    fragment, but fragments are reassembled here anyway."""

    def __init__(self, sock, initial=b""):
        self.sock = sock
        self.buffer = bytearray(initial)
        self.pending = bytearray()

    def _need(self, count):
        while len(self.buffer) < count:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("Verbindung beendet")
            self.buffer += chunk

    def _take(self, count):
        self._need(count)
        data = bytes(self.buffer[:count])
        del self.buffer[:count]
        return data

    def next_message(self):
        while True:
            first, second = self._take(2)
            fin = first & 0x80
            opcode = first & 0x0F
            masked = second & 0x80
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._take(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._take(8))[0]
            key = self._take(4) if masked else None
            payload = self._take(length) if length else b""
            if key:
                payload = bytes(b ^ key[i % 4] for i, b in enumerate(payload))

            if opcode == 0x8:  # close
                raise ConnectionError("Gegenseite hat geschlossen")
            if opcode == 0x9:  # ping -> pong
                self.sock.sendall(bytes([0x8A, 0x80]) + mask(payload)[:4] if not payload
                                  else bytes([0x8A, 0x80 | len(payload)]) + mask(payload))
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode in (0x1, 0x0):
                self.pending += payload
                if fin:
                    message = self.pending.decode(errors="replace")
                    self.pending = bytearray()
                    return message
                continue
            # Binary frames are not of interest here.
            if fin:
                self.pending = bytearray()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="localhost:8080",
                        help="host[:port] of the machine, default localhost:8080 (simulator)")
    parser.add_argument("--path", default="/ws")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--out", default="-", help="output file or - for stdout")
    parser.add_argument("--send", action="append", default=[],
                        help="message type to send after connecting "
                             "(e.g. req:profiles:list); can be repeated")
    parser.add_argument("--quiet", action="store_true",
                        help="do not echo evt:status to stderr")
    args = parser.parse_args()

    host, _, port = args.host.partition(":")
    port = int(port or 80)

    sock = socket.create_connection((host, port), timeout=10)
    rest = handshake(sock, args.host, args.path)
    reader = FrameReader(sock, rest)
    started = time.time()

    out = sys.stdout if args.out == "-" else open(args.out, "w")
    counts = {}

    def record(direction, message):
        try:
            parsed = json.loads(message)
        except ValueError:
            parsed = {"_raw": message}
        kind = parsed.get("tp", "?")
        counts[kind] = counts.get(kind, 0) + 1
        out.write(json.dumps({"t": round(time.time() - started, 3),
                              "dir": direction, "msg": parsed}) + "\n")
        out.flush()
        if not args.quiet or kind != "evt:status":
            print(f"{direction} {kind}", file=sys.stderr)

    for i, tp in enumerate(args.send):
        payload = json.dumps({"tp": tp, "rid": f"capture-{i}"})
        send_text(sock, payload)
        record("out", payload)

    try:
        while time.time() - started < args.seconds:
            sock.settimeout(max(0.1, args.seconds - (time.time() - started)))
            record("in", reader.next_message())
    except (ConnectionError, socket.timeout, TimeoutError) as error:
        print(f"Ende: {error}", file=sys.stderr)
    finally:
        if out is not sys.stdout:
            out.close()
        send_close(sock)
        sock.close()

    print("\nNachrichten nach Typ:", file=sys.stderr)
    for kind, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:5d}  {kind}", file=sys.stderr)


if __name__ == "__main__":
    main()
