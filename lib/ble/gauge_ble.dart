// All Bluetooth code lives in this file, so the BLE package can be swapped
// later without touching the screens.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/gauge_models.dart';

/// Must match the UUIDs in the firmware.
class GaugeUuids {
  static final service = Guid('6a1f0001-3c2d-4b8e-9f10-7e5a2c9d4b01');
  static final config = Guid('6a1f0002-3c2d-4b8e-9f10-7e5a2c9d4b01');
  static final command = Guid('6a1f0003-3c2d-4b8e-9f10-7e5a2c9d4b01');
  static final status = Guid('6a1f0004-3c2d-4b8e-9f10-7e5a2c9d4b01');
  static final otaCtl = Guid('6a1f0005-3c2d-4b8e-9f10-7e5a2c9d4b01');
  static final otaData = Guid('6a1f0006-3c2d-4b8e-9f10-7e5a2c9d4b01');
}

/// flutter_blue_plus 2.x asks you to declare your license.
/// Personal / hobby use is `nonprofit`. Selling the app or kit as a
/// business needs their paid `commercial` license.
const fbpLicense = License.nonprofit;

/// A gauge seen while scanning.
class FoundGauge {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  FoundGauge(this.device, this.name, this.rssi);
  String get id => device.remoteId.str;
}

class GaugeScanner {
  static Stream<List<FoundGauge>> get results =>
      FlutterBluePlus.scanResults.map((list) => list
          .map((r) => FoundGauge(
                r.device,
                r.advertisementData.advName.isNotEmpty
                    ? r.advertisementData.advName
                    : (r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : r.device.remoteId.str),
                r.rssi,
              ))
          .toList());

  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// true = Bluetooth on and permitted.
  static Stream<bool> get adapterReady =>
      FlutterBluePlus.adapterState.map((s) => s == BluetoothAdapterState.on);

  static Future<void> start() => FlutterBluePlus.startScan(
        withServices: [GaugeUuids.service],
        timeout: const Duration(seconds: 8),
      );

  static Future<void> stop() => FlutterBluePlus.stopScan();

  static Future<void> turnOn() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}
  }
}

/// The connected gauge: settings, live status, and commands.
class GaugeConnection extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cfgChar, _cmdChar, _statusChar, _otaCtl, _otaData;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _statusSub;

  String name = '';
  bool connected = false;
  String? error;
  GaugeConfig? config;
  GaugeStatus? status;

  int _lastRev = -1;
  bool _readingCfg = false;

  Future<bool> connect(FoundGauge g) async {
    await disconnect();
    _device = g.device;
    name = g.name;
    error = null;
    notifyListeners();

    final d = g.device;
    try {
      await d.connect(license: fbpLicense, timeout: const Duration(seconds: 15));

      // Ask Android for the fastest connection interval (~7.5-15 ms instead
      // of ~50 ms), so each command gets through quickly.
      try {
        await d.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high);
      } catch (_) {}

      final services = await d.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid == GaugeUuids.service,
        orElse: () => throw Exception('Gauge service not found'),
      );
      for (final c in svc.characteristics) {
        if (c.uuid == GaugeUuids.config) {
          _cfgChar = c;
        } else if (c.uuid == GaugeUuids.command) {
          _cmdChar = c;
        } else if (c.uuid == GaugeUuids.status) {
          _statusChar = c;
        } else if (c.uuid == GaugeUuids.otaCtl) {
          _otaCtl = c;
        } else if (c.uuid == GaugeUuids.otaData) {
          _otaData = c;
        }
      }
      if (_cfgChar == null || _cmdChar == null || _statusChar == null) {
        throw Exception('Gauge firmware is missing a characteristic (update the firmware)');
      }

      _statusSub = _statusChar!.onValueReceived.listen(_onStatus);
      await _statusChar!.setNotifyValue(true);
      await refreshConfig();

      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && connected) {
          _cleanup();
          error = 'Gauge disconnected';
          notifyListeners();
        }
      });

      connected = true;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      try {
        await d.disconnect();
      } catch (_) {}
      _cleanup();
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    final d = _device;
    _cleanup();
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
    notifyListeners();
  }

  void _cleanup() {
    _statusSub?.cancel();
    _connSub?.cancel();
    _statusSub = null;
    _connSub = null;
    _cfgChar = _cmdChar = _statusChar = _otaCtl = _otaData = null;
    _device = null;
    connected = false;
    config = null;
    status = null;
    _lastRev = -1;
    _readingCfg = false;
    _queue.clear();
    _pendingJog = 0;
    _pendingRpm = null;
    _sending = false;
  }

  void _onStatus(List<int> value) {
    try {
      final m = jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
      status = GaugeStatus.fromJson(m);
      if (status!.rev != _lastRev) refreshConfig();
      notifyListeners();
    } catch (_) {
      // partial / garbled packet: ignore, another comes in 100 ms
    }
  }

  Future<void> refreshConfig() async {
    final c = _cfgChar;
    if (c == null || _readingCfg) return;
    _readingCfg = true;
    try {
      final v = await c.read();
      final m = jsonDecode(utf8.decode(v)) as Map<String, dynamic>;
      config = GaugeConfig.fromJson(m);
      _lastRev = config!.rev;
      notifyListeners();
    } catch (e) {
      debugPrint('config read failed: $e');
    } finally {
      _readingCfg = false;
    }
  }

  // ------------------------------------------------------------ sending
  //
  // Only one write is ever in flight. While it's going, new commands wait
  // here and are merged:
  //   - nudges add up into a single "jog" (10 taps of +0.2 = "jog 2.00")
  //   - simulated RPM keeps only the latest value
  //   - everything else is kept in order
  // When the write finishes, everything waiting goes out together in one
  // multi-line write. So the gauge can never fall behind, however fast you tap.

  final List<String> _queue = [];
  double _pendingJog = 0;
  String? _pendingRpm;
  bool _sending = false;

  /// Send one or more console commands, e.g. "set speed 300" or
  /// "cal clear\ncal add 0 0\ncal add 7000 345".
  Future<void> send(String cmd) {
    _queue.addAll(cmd.split('\n').where((l) => l.trim().isNotEmpty));
    _pendingRpm = null; // a button press replaces any half-sent slider value
    return _pump();
  }

  /// Nudge the needle. Rapid taps are added together.
  void jog(double deg) {
    _pendingJog += deg;
    _pump();
  }

  /// Simulated RPM from the slider. Only the newest value is sent.
  void simulate(int rpm) {
    _pendingRpm = 'rpm $rpm';
    _pump();
  }

  Future<void> _pump() async {
    if (_sending) return;
    _sending = true;
    try {
      while (true) {
        final c = _cmdChar;
        final d = _device;
        if (c == null || d == null) break;

        final lines = <String>[];
        if (_pendingJog.abs() >= 0.005) {
          lines.add('jog ${_pendingJog.toStringAsFixed(2)}');
        }
        _pendingJog = 0;
        // The gauge's command queue holds 16 lines; stay under that.
        while (_queue.isNotEmpty && lines.length < 12) {
          lines.add(_queue.removeAt(0));
        }
        if (_pendingRpm != null && lines.length < 12) {
          lines.add(_pendingRpm!);
          _pendingRpm = null;
        }
        if (lines.isEmpty) break;

        final data = utf8.encode(lines.join('\n'));
        try {
          await c.write(data, allowLongWrite: data.length > d.mtuNow - 3);
        } catch (e) {
          error = 'Send failed: $e';
          notifyListeners();
          break;
        }
      }
    } finally {
      _sending = false;
    }
  }

  // ------------------------------------------------------------ OTA

  /// Firmware 0.5.0 and later can be updated over Bluetooth.
  bool get otaSupported => _otaCtl != null && _otaData != null;

  void _checkOtaError() {
    final s = status;
    if (s != null && s.ota == 3) {
      throw Exception('Gauge rejected the update: ${s.otaErr}');
    }
  }

  /// Send a firmware .bin to the gauge. Each chunk is acknowledged by the
  /// gauge after it's written to flash, so it can't be overrun. When the
  /// gauge confirms, it reboots into the new firmware (and disconnects).
  Future<void> updateFirmware(Uint8List bin, void Function(double) onProgress) async {
    final ctl = _otaCtl, dat = _otaData, d = _device;
    if (ctl == null || dat == null || d == null) {
      throw Exception('This gauge firmware has no Bluetooth update support. Flash it once over USB.');
    }
    try {
      await ctl.write(utf8.encode('begin ${bin.length}'));
      await Future.delayed(const Duration(milliseconds: 250)); // let a fresh status arrive
      _checkOtaError();

      final chunk = (d.mtuNow - 3).clamp(20, 509).toInt();
      var n = 0;
      for (var off = 0; off < bin.length; off += chunk) {
        if (!connected) throw Exception('Gauge disconnected');
        final end = math.min(off + chunk, bin.length);
        await dat.write(bin.sublist(off, end));
        if (++n % 16 == 0) {
          _checkOtaError();
          onProgress(end / bin.length);
        }
      }
      onProgress(1);

      await ctl.write(utf8.encode('end'), timeout: 30); // gauge verifies the image here
      final t0 = DateTime.now();
      while (DateTime.now().difference(t0).inSeconds < 15) {
        if (status?.ota == 2) return;
        _checkOtaError();
        await Future.delayed(const Duration(milliseconds: 100));
      }
      throw Exception('Gauge did not confirm the update');
    } catch (_) {
      try {
        await ctl.write(utf8.encode('abort'));
      } catch (_) {}
      rethrow;
    }
  }

  /// "set <key> <value>" with sensible number formatting.
  Future<void> set(String key, num value) {
    final s = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return send('set $key $s');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
