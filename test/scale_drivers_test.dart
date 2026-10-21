import 'dart:typed_data';

import 'package:beand/scale/acaia_driver.dart';
import 'package:beand/scale/bookoo_driver.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/decent_driver.dart';
import 'package:beand/scale/scale_driver.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

List<int> withXor(List<int> bytes) => [...bytes, xorOf(bytes)];

void main() {
  group('Decent', () {
    final d = DecentDriver();

    test('commands are byte for byte those of Decent\'s documentation', () {
      expect(hex(DecentDriver.tareCommand), '030F000000010D');
      expect(hex(DecentDriver.ledOnGrams), '030A0101000108');
      expect(hex(DecentDriver.heartbeatCommand), '030A03FFFF000A');
      expect(hex(DecentDriver.timerStart), '030B030000000B');
      expect(hex(DecentDriver.timerStop), '030B0000000008');
      expect(hex(DecentDriver.timerReset), '030B020000000A');
      // Firmware 1.0 may drop a command: each goes twice.
      expect(d.tare, hasLength(2));
    });

    test('weight: tenths of a gram, signed, 7- and 10-byte packets', () {
      // 0x0794 = 1940 → 194.0 g (the example from the documentation).
      expect(d.parse(withXor([0x03, 0xCE, 0x07, 0x94, 0x00, 0x00])).weights, [
        194.0,
      ]);
      // Changing (CA) counts too; 0xFF9C = −100 → −10.0 g.
      expect(d.parse(withXor([0x03, 0xCA, 0xFF, 0x9C, 0x00, 0x00])).weights, [
        -10.0,
      ]);
      // Firmware 1.2+: minutes, seconds, deciseconds, two reserved, XOR.
      expect(
        d
            .parse(
              withXor([0x03, 0xCE, 0x00, 0xB9, 0x00, 0x1E, 0x05, 0x00, 0x00]),
            )
            .weights,
        [18.5],
      );
    });

    test('a bad checksum or another packet type is no weight', () {
      expect(
        d.parse([0x03, 0xCE, 0x07, 0x94, 0x00, 0x00, 0x00]).weights,
        isEmpty,
      );
      expect(
        d.parse(withXor([0x03, 0xAA, 0x01, 0x01, 0x00, 0x00])).weights,
        isEmpty,
      );
    });
  });

  group('Bookoo', () {
    final b = BookooDriver();

    // 20 bytes as in Bookoo's protocols.md.
    List<int> packet({
      required int sign,
      required int centigrams,
      int battery = 87,
    }) => withXor([
      0x03, 0x0B, // product, type
      0x00, 0x75, 0x30, // timer 30000 ms
      0x01, // unit: grams
      sign,
      (centigrams >> 16) & 0xff, (centigrams >> 8) & 0xff, centigrams & 0xff,
      0x2B, 0x00, 0x96, // flow + 1.50
      battery,
      0x00, 0x32, // standby
      0x01, 0x00, 0x00, // buzzer, smoothing, reserved
    ]);

    test('commands are byte for byte those of Bookoo\'s documentation', () {
      expect(hex(BookooDriver.tareCommand), '030A01000008');
      expect(hex(BookooDriver.timerStart), '030A0400000D');
      expect(hex(BookooDriver.timerStop), '030A0500000C');
      expect(hex(BookooDriver.timerReset), '030A0600000F');
    });

    test('weight in hundredths of a gram, sign, battery', () {
      final p = b.parse(packet(sign: 0x2B, centigrams: 1853));
      expect(p.weights, [18.53]);
      expect(p.battery, 87);
      expect(b.parse(packet(sign: 0x2D, centigrams: 120)).weights, [-1.2]);
    });

    test('a bad checksum is dropped', () {
      final bad = packet(sign: 0x2B, centigrams: 1853)..[19] ^= 0xFF;
      expect(b.parse(bad).weights, isEmpty);
    });
  });

  test('the advertised name picks the driver', () {
    final drivers = [AcaiaDriver(), DecentDriver(), BookooDriver()];
    String? brand(String name) =>
        drivers.where((d) => d.matches(name)).map((d) => d.brand).singleOrNull;
    expect(brand('Decent Scale'), 'Decent');
    expect(brand('BOOKOO_SC'), 'Bookoo');
    expect(brand('ACAIAL13006'), 'Acaia');
    expect(brand('PROCHBT001'), 'Acaia');
    expect(brand('Some speaker'), isNull);
    expect(scaleShortName('Decent Scale'), 'Decent');
    expect(scaleShortName('BOOKOO_SC'), 'Bookoo');
  });
}
