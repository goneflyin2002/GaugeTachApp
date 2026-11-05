// Firmware releases are published in the GaugeTachFirmware GitHub repo:
//   version.json            -> {"version", "url", "size", "notes"}
//   releases/GaugeTach_vX.Y.Z.bin
// The repo must be public so the app can download without logging in.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const releaseIndexUrl =
    'https://raw.githubusercontent.com/goneflyin2002/GaugeTachFirmware/main/version.json';

class FirmwareRelease {
  final String version;
  final String url;
  final int size; // 0 = unknown
  final String notes;

  FirmwareRelease({
    required this.version,
    required this.url,
    required this.size,
    required this.notes,
  });

  /// Latest published release, or null if it can't be reached.
  static Future<FirmwareRelease?> fetchLatest() async {
    try {
      // The query string dodges GitHub's 5-minute cache of raw files.
      final uri = Uri.parse('$releaseIndexUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      return FirmwareRelease(
        version: (m['version'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        size: (m['size'] as num?)?.toInt() ?? 0,
        notes: (m['notes'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> download() async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('Download failed (HTTP ${r.statusCode})');
    }
    final bytes = r.bodyBytes;
    if (size > 0 && bytes.length != size) {
      throw Exception('Download size ${bytes.length} does not match version.json ($size)');
    }
    // Every ESP32 app image starts with the magic byte 0xE9.
    if (bytes.isEmpty || bytes[0] != 0xE9) {
      throw Exception('That file is not an ESP32 firmware image');
    }
    return bytes;
  }

  /// Is this release newer than [current] (e.g. "0.5.0")?
  bool isNewerThan(String current) => compareVersions(version, current) > 0;
}

/// Compares "1.2.10" style versions. Returns >0 if a is newer.
int compareVersions(String a, String b) {
  List<int> parts(String s) => s
      .replaceAll(RegExp(r'[^0-9.]'), '')
      .split('.')
      .where((p) => p.isNotEmpty)
      .map(int.parse)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
