import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/gauge_ble.dart';
import '../models/gauge_models.dart';
import '../ota/firmware_release.dart';
import '../widgets/dial.dart';
import '../widgets/settings.dart';
import 'ota_screen.dart';

class GaugeScreen extends StatefulWidget {
  const GaugeScreen({super.key});

  @override
  State<GaugeScreen> createState() => _GaugeScreenState();
}

class _GaugeScreenState extends State<GaugeScreen> {
  bool _leaving = false;
  FirmwareRelease? _latest;
  bool _offered = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  // Like STOMP: quietly check for newer firmware each time a gauge connects.
  Future<void> _checkForUpdate() async {
    final rel = await FirmwareRelease.fetchLatest();
    if (!mounted || rel == null) return;
    setState(() => _latest = rel);
  }

  void _openOta() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => OtaScreen(latest: _latest)));
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<GaugeConnection>();

    // Gauge dropped off: go back to the scan list (unless we're already leaving).
    if (!conn.connected && !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(conn.error ?? 'Disconnected')));
        Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }

    final fw = conn.config?.fw;
    final updateAvailable =
        conn.otaSupported && _latest != null && fw != null && _latest!.isNewerThan(fw);

    // Offer the update once per connection.
    if (updateAvailable && !_offered) {
      _offered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Firmware ${_latest!.version} is available'),
          action: SnackBarAction(label: 'View', onPressed: _openOta),
          duration: const Duration(seconds: 8),
        ));
      });
    }

    final cfg = conn.config;
    final st = conn.status;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(conn.name),
          actions: [
            IconButton(
              tooltip: 'Firmware update',
              onPressed: _openOta,
              icon: Badge(
                isLabelVisible: updateAvailable,
                child: const Icon(Icons.system_update),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Live'),
            Tab(text: 'Setup'),
            Tab(text: 'Needle'),
            Tab(text: 'Calibrate'),
          ]),
        ),
        body: cfg == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _LiveTab(cfg: cfg, st: st),
                _SetupTab(cfg: cfg, st: st),
                _NeedleTab(cfg: cfg),
                _CalTab(cfg: cfg),
              ]),
        bottomNavigationBar: _SaveBar(unsaved: st?.unsaved ?? false),
      ),
    );
  }
}

// ---------------------------------------------------------------- Save bar

class _SaveBar extends StatelessWidget {
  final bool unsaved;
  const _SaveBar({required this.unsaved});

  @override
  Widget build(BuildContext context) {
    if (!unsaved) return const SizedBox.shrink();
    final conn = context.read<GaugeConnection>();
    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            const Expanded(child: Text('Changes are active but not saved')),
            FilledButton.icon(
              onPressed: () => conn.send('save'),
              icon: const Icon(Icons.save),
              label: const Text('Save to gauge'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Live

class _LiveTab extends StatefulWidget {
  final GaugeConfig cfg;
  final GaugeStatus? st;
  const _LiveTab({required this.cfg, required this.st});

  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  double? _sim; // slider position while dragging

  // The connection only ever sends the newest value, so no throttling needed.
  void _sendSim(GaugeConnection conn, double v, {bool force = false}) =>
      conn.simulate(v.round());

  @override
  Widget build(BuildContext context) {
    final conn = context.read<GaugeConnection>();
    final cfg = widget.cfg;
    final st = widget.st;
    final full = cfg.fullScale;

    String state;
    if (st == null) {
      state = 'Waiting for gauge…';
    } else if (st.parked) {
      state = 'Ignition off – needle parked';
    } else if (st.busy) {
      state = st.homed ? 'Sweeping…' : 'Homing…';
    } else if (!st.homed) {
      state = 'Not homed';
    } else if (st.hold) {
      state = 'Needle held (manual)';
    } else if (st.simulating) {
      state = 'Simulating ${st.sim} rpm';
    } else {
      state = 'Live input';
    }

    final simValue = (_sim ?? (st?.simulating == true ? st!.sim.toDouble() : 0))
        .clamp(0, full)
        .toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GaugeDial(
              config: cfg,
              needleDeg: st?.needle ?? 0,
              readout: st?.rpm ?? 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Chip(label: Text(state))),
        const SectionHeader('Test the needle'),
        Row(children: [
          const SizedBox(width: 16),
          Text('Simulate', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(
            child: Slider(
              value: simValue,
              min: 0,
              max: full,
              divisions: (full / 50).round().clamp(1, 1000).toInt(),
              label: '${simValue.round()}',
              onChanged: (v) {
                setState(() => _sim = v);
                _sendSim(conn, v);
              },
              onChangeEnd: (v) {
                _sendSim(conn, v, force: true);
                setState(() => _sim = null);
              },
            ),
          ),
        ]),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
                onPressed: () => conn.send('live'),
                icon: const Icon(Icons.sensors),
                label: const Text('Real input')),
            OutlinedButton.icon(
                onPressed: () => conn.send('sweep'),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Sweep')),
            OutlinedButton.icon(
                onPressed: () => conn.send('home'),
                icon: const Icon(Icons.home),
                label: const Text('Home')),
          ],
        ),
        const SectionHeader('Set the zero mark'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Nudge the needle until it sits exactly on 0, then tap "Set zero here".'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final j in const [-1.0, -0.2, 0.2, 1.0])
              OutlinedButton(
                onPressed: () => conn.jog(j),
                child: Text('${j > 0 ? '+' : ''}${j.toStringAsFixed(1)}°'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.tonal(
            onPressed: () async {
              await conn.send('setzero');
              await conn.send('live');
            },
            child: const Text('Set zero here'),
          ),
        ),
        const SizedBox(height: 24),
        if (st != null)
          Text(
            'Needle ${st.needle.toStringAsFixed(1)}°   target ${st.target.toStringAsFixed(1)}°   '
            'input ${st.raw.toStringAsFixed(0)} rpm\n'
            'Firmware ${cfg.fw} · ${cfg.driver}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Setup

class _SetupTab extends StatelessWidget {
  final GaugeConfig cfg;
  final GaugeStatus? st;
  const _SetupTab({required this.cfg, required this.st});

  static const _cylinders = [1, 2, 3, 4, 5, 6, 8, 10, 12];

  @override
  Widget build(BuildContext context) {
    final conn = context.read<GaugeConnection>();
    final cyl = (cfg.ppr * 2).round();
    final isStd = _cylinders.contains(cyl) && (cfg.ppr * 2 - cyl).abs() < 0.01;

    return ListView(children: [
      const SectionHeader('Engine'),
      ListTile(
        title: const Text('Cylinders (4-stroke)'),
        subtitle: Text('${cfg.ppr.toStringAsFixed(2)} pulses per revolution'),
        trailing: DropdownButton<int>(
          value: isStd ? cyl : null,
          hint: const Text('Custom'),
          items: [
            for (final c in _cylinders) DropdownMenuItem(value: c, child: Text('$c')),
          ],
          onChanged: (c) {
            if (c != null) conn.set('ppr', c / 2);
          },
        ),
      ),
      NumberSetting(
        label: 'Pulses per revolution',
        help: 'For MSD / tach adapters or 2-strokes',
        value: cfg.ppr,
        decimals: 2,
        min: 0.25,
        max: 16,
        onChanged: (v) => conn.set('ppr', v),
      ),
      NumberSetting(
        label: 'Ignore pulses above',
        help: 'Rejects points bounce and coil ringing',
        value: cfg.maxInputRpm,
        unit: 'rpm',
        min: 1000,
        max: 20000,
        onChanged: (v) => conn.set('maxrpm', v),
      ),
      NumberSetting(
        label: 'Smoothing',
        help: 'Higher = steadier, slower needle',
        value: cfg.filterMs,
        unit: 'ms',
        min: 0,
        max: 2000,
        onChanged: (v) => conn.set('filter', v),
      ),
      const SectionHeader('Dial'),
      NumberSetting(
        label: 'Full scale',
        help: 'Resets calibration to a straight line',
        value: cfg.fullScale,
        unit: 'rpm',
        min: 100,
        max: 30000,
        onChanged: (v) => conn.set('max', v),
      ),
      NumberSetting(
        label: 'Needle sweep',
        value: cfg.sweep,
        unit: '°',
        decimals: 1,
        min: 10,
        max: 359,
        onChanged: (v) => conn.set('sweep', v),
      ),
      SwitchListTile(
        title: const Text('Sweep at power-up'),
        value: cfg.wakeSweep,
        onChanged: (v) => conn.set('wake', v ? 1 : 0),
      ),
      if (cfg.hasIgnSense) ...[
        const SectionHeader('Ignition'),
        SwitchListTile(
          title: const Text('Park needle when ignition turns off'),
          subtitle: Text(
            'Needs ignition sense wired to D9. '
            'Ignition now: ${st == null ? '–' : (st!.ignOn ? 'ON' : 'OFF')}'
            '${st?.parked == true ? ' (parked)' : ''}',
          ),
          value: cfg.ignSense,
          onChanged: (v) => conn.set('ign', v ? 1 : 0),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- Needle

class _NeedleTab extends StatelessWidget {
  final GaugeConfig cfg;
  const _NeedleTab({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final conn = context.read<GaugeConnection>();
    return ListView(children: [
      const SectionHeader('Motion'),
      NumberSetting(
        label: 'Top speed',
        value: cfg.speed,
        unit: '°/s',
        min: 10,
        max: 1000,
        onChanged: (v) => conn.set('speed', v),
      ),
      NumberSetting(
        label: 'Acceleration',
        value: cfg.accel,
        unit: '°/s²',
        min: 50,
        max: 20000,
        onChanged: (v) => conn.set('accel', v),
      ),
      NumberSetting(
        label: 'Deadband',
        help: 'Ignore changes smaller than this',
        value: cfg.deadband,
        unit: '°',
        decimals: 2,
        min: 0,
        max: 5,
        onChanged: (v) => conn.set('deadband', v),
      ),
      ListTile(
        title: const Text('Step-loss test'),
        subtitle: const Text('Sweeps 10 times. The needle should end exactly on 0.'),
        trailing: OutlinedButton(
            onPressed: () => conn.send('sweep 10'), child: const Text('Run')),
      ),
      const SectionHeader('Motor'),
      NumberSetting(
        label: 'Drive strength',
        value: cfg.drivePct.toDouble(),
        unit: '%',
        min: 10,
        max: 100,
        onChanged: (v) => conn.set('drive', v.round()),
      ),
      SwitchListTile(
        title: const Text('Reverse direction'),
        subtitle: const Text('Re-homes the needle'),
        value: cfg.invert,
        onChanged: (v) => conn.set('invert', v ? 1 : 0),
      ),
      const SectionHeader('Homing'),
      NumberSetting(
        label: 'Home speed',
        value: cfg.homeSpeed,
        unit: '°/s',
        min: 20,
        max: 600,
        onChanged: (v) => conn.set('homespeed', v),
      ),
      NumberSetting(
        label: 'Overtravel',
        help: 'Extra drive past full sweep to be sure it hits the stop',
        value: cfg.overtravel,
        unit: '°',
        min: 0,
        max: 60,
        onChanged: (v) => conn.set('overtravel', v),
      ),
      NumberSetting(
        label: 'Zero mark above stop',
        help: 'Easier to set with "Set zero here" on the Live tab',
        value: cfg.zeroOffset,
        unit: '°',
        decimals: 2,
        min: -30,
        max: 60,
        onChanged: (v) => conn.set('zerooffset', v),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Calibrate

class _CalTab extends StatelessWidget {
  final GaugeConfig cfg;
  const _CalTab({required this.cfg});

  /// Replace the whole table in one write.
  Future<void> _writeCal(GaugeConnection conn, List<CalPoint> pts) {
    final sorted = [...pts]..sort((a, b) => a.value.compareTo(b.value));
    final lines = [
      'cal clear',
      for (final p in sorted) 'cal add ${p.value.round()} ${p.deg.toStringAsFixed(2)}',
    ];
    return conn.send(lines.join('\n'));
  }

  Future<void> _addPoint(BuildContext context, GaugeConnection conn) async {
    final st = conn.status;
    final v = await askNumber(context,
        title: 'Reading (rpm)', initial: 0, unit: 'rpm', min: 0, max: 30000);
    if (v == null || !context.mounted) return;
    final d = await askNumber(context,
        title: 'Needle angle for ${v.round()} rpm',
        initial: st?.needle ?? cfg.valueToDeg(v),
        unit: '°',
        decimals: 1,
        min: 0,
        max: cfg.sweep);
    if (d == null) return;
    final pts = cfg.cal.where((p) => (p.value - v).abs() > 0.5).toList()..add(CalPoint(v, d));
    await _writeCal(conn, pts);
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.read<GaugeConnection>();
    final pts = cfg.cal;
    return Scaffold(
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'For dials that aren\'t evenly spaced. Each point says where the needle '
            'should be at a reading; the gauge draws straight lines between them. '
            'Tip: on the Live tab, simulate the reading, nudge the needle onto that '
            'mark with the jog buttons, then come back here and add the point. The '
            'angle is filled in from where the needle is now.',
          ),
        ),
        const SectionHeader('Points'),
        for (final p in pts)
          ListTile(
            title: Text('${p.value.round()} rpm'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${p.deg.toStringAsFixed(1)}°',
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: pts.length <= 2
                    ? null
                    : () => _writeCal(conn, pts.where((q) => q != p).toList()),
              ),
            ]),
          ),
        if (pts.length >= 8)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Maximum of 8 points.'),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => conn.set('max', cfg.fullScale),
            child: const Text('Reset to a straight line'),
          ),
        ),
        const SizedBox(height: 80),
      ]),
      floatingActionButton: pts.length >= 8
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addPoint(context, conn),
              icon: const Icon(Icons.add),
              label: const Text('Add point'),
            ),
    );
  }
}
