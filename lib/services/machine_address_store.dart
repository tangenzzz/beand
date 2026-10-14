import 'package:shared_preferences/shared_preferences.dart';

// Does the address look like an IP? Any port is stripped first
// ("192.168.1.10:8080" is an IP).
bool looksLikeIpAddress(String value) {
  final withoutPort = value.contains(']')
      // IPv6 in brackets: [::1]:8080
      ? value.substring(0, value.indexOf(']') + 1)
      : (value.split(':').length == 2 ? value.split(':').first : value);
  final bare = withoutPort.replaceAll(RegExp(r'^\[|\]$'), '');
  return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(bare) ||
      bare.contains(':');
}

// Where a machine's address lives — and, more importantly, what must NOT
// happen: an IP never replaces the configured name.
//
// Background: after installation the first connection did not get
// through, the silent re-discovery fell back to the IP — and saved it as
// the hostname. After that the settings field showed the IP instead of the
// name, and the name was gone. But a dropout must not change the setting:
// the name is what survives a new IP, the IP only what survives broken
// name resolution.
class MachineAddressStore {
  const MachineAddressStore({required this.hostKey, required this.ipKey});

  final String hostKey;
  final String ipKey;

  Future<void> remember({required String address, String? ip}) async {
    final prefs = await SharedPreferences.getInstance();
    if (looksLikeIpAddress(address)) {
      await prefs.setString(ipKey, address);
      return;
    }
    await prefs.setString(hostKey, address);
    if (ip != null) await prefs.setString(ipKey, ip);
  }

  Future<String?> configuredHost() async =>
      (await SharedPreferences.getInstance()).getString(hostKey);

  Future<String?> lastIp() async =>
      (await SharedPreferences.getInstance()).getString(ipKey);
}
