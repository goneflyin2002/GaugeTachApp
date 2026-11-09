// Data from the gauge firmware (GaugeTachX27.ino, BLE section).

double _d(Map<String, dynamic> m, String k, [double def = 0]) =>
    (m[k] as num?)?.toDouble() ?? def;
int _i(Map<String, dynamic> m, String k, [int def = 0]) =>
    (m[k] as num?)?.toInt() ?? def;
bool _b(Map<String, dynamic> m, String k) => _i(m, k) != 0;

class CalPoint {
  final double value; // input value (rpm)
  final double deg; // needle angle
  const CalPoint(this.value, this.deg);
}

/// Every setting, as read from the config characteristic.
class GaugeConfig {
  final String fw;
  final String type;
  final String driver;
  final int rev;
  final double sweep;
  final double ppr;
  final double maxInputRpm;
  final double filterMs;
  final double speed;
  final double accel;
  final double deadband;
  final int drivePct;
  final bool invert;
  final double zeroOffset;
  final double homeSpeed;
  final double overtravel;
  final bool wakeSweep;
  final bool ignSense; // park needle when ignition power drops (firmware 0.6.0+)
  final bool hasIgnSense; // firmware supports it
  final List<CalPoint> cal;

  GaugeConfig.fromJson(Map<String, dynamic> m)
      : fw = (m['fw'] ?? '?').toString(),
        type = (m['type'] ?? 'tach').toString(),
        driver = (m['driver'] ?? '?').toString(),
        rev = _i(m, 'rev'),
        sweep = _d(m, 'sweep', 345),
        ppr = _d(m, 'ppr', 4),
        maxInputRpm = _d(m, 'maxrpm', 9000),
        filterMs = _d(m, 'filter', 60),
        speed = _d(m, 'speed'),
        accel = _d(m, 'accel'),
        deadband = _d(m, 'deadband'),
        drivePct = _i(m, 'drive', 100),
        invert = _b(m, 'invert'),
        zeroOffset = _d(m, 'zerooffset'),
        homeSpeed = _d(m, 'homespeed'),
        overtravel = _d(m, 'overtravel'),
        wakeSweep = _b(m, 'wake'),
        ignSense = _b(m, 'ign'),
        hasIgnSense = m.containsKey('ign'),
        cal = ((m['cal'] as List?) ?? const [])
            .map((p) => CalPoint(
                  ((p as List)[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList();

  /// Full-scale reading (top calibration point).
  double get fullScale => cal.isEmpty ? 7000 : cal.last.value;

  /// Same mapping the firmware uses: straight lines between cal points.
  double valueToDeg(double v) {
    if (cal.length < 2) return 0;
    if (v <= cal.first.value) return cal.first.deg;
    for (var i = 1; i < cal.length; i++) {
      if (v <= cal[i].value) {
        final a = cal[i - 1], b = cal[i];
        final f = (v - a.value) / (b.value - a.value);
        return a.deg + f * (b.deg - a.deg);
      }
    }
    return cal.last.deg;
  }
}

/// Live values, notified 10 times a second.
class GaugeStatus {
  final double rpm;
  final double raw;
  final double needle;
  final double target;
  final bool homed;
  final bool busy;
  final bool hold;
  final int sim; // -1 = real input
  final bool unsaved;
  final int rev;
  final int ota; // 0 idle, 1 receiving, 2 done (rebooting), 3 failed
  final int otaPct;
  final String otaErr;
  final bool ignOn; // ignition sense reads "key on"
  final bool parked; // ignition off: needle parked at 0

  GaugeStatus.fromJson(Map<String, dynamic> m)
      : rpm = _d(m, 'rpm'),
        raw = _d(m, 'raw'),
        needle = _d(m, 'needle'),
        target = _d(m, 'target'),
        homed = _b(m, 'homed'),
        busy = _b(m, 'busy'),
        hold = _b(m, 'hold'),
        sim = _i(m, 'sim', -1),
        unsaved = _b(m, 'unsaved'),
        rev = _i(m, 'rev'),
        ota = _i(m, 'ota'),
        otaPct = _i(m, 'otapct'),
        otaErr = (m['otaerr'] ?? '').toString(),
        ignOn = _b(m, 'ignon'),
        parked = _b(m, 'parked');

  bool get simulating => sim >= 0;
}
