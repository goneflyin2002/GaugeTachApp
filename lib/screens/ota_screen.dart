import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/gauge_ble.dart';
import '../ota/firmware_release.dart';

class OtaScreen extends StatefulWidget {
  final FirmwareRelease? latest; // already fetched by the gauge screen, if any
  const OtaScreen({super.key, this.latest});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

enum _Phase { checking, ready, downloading, sending, done, failed }

class _OtaScreenState extends State<OtaScreen> {
  FirmwareRelease? _latest;
  _Phase _phase = _Phase.checking;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latest = widget.latest;
    if (_latest != null) {
      _phase = _Phase.ready;
    } else {
      _check();
    }
  }

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    final r = await FirmwareRelease.fetchLatest();
    if (!mounted) return;
    setState(() {
      _latest = r;
      _phase = _Phase.ready;
      if (r == null) _error = 'Could not reach the update server. Check the phone\'s internet.';
    });
  }

  Future<void> _install() async {
    final rel = _latest;
    if (rel == null) return;
    final conn = context.read<GaugeConnection>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      setState(() {
        _phase = _Phase.downloading;
        _error = null;
        _progress = 0;
      });
      final bin = await rel.download();
      if (!mounted) return;
      setState(() => _phase = _Phase.sending);
      await conn.updateFirmware(bin, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      messenger.showSnackBar(SnackBar(
          content: Text('Firmware ${rel.version} installed. The gauge is restarting; '
              'reconnect in a few seconds.')));
      await Future.delayed(const Duration(milliseconds: 800));
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<GaugeConnection>();
    final current = conn.config?.fw ?? '?';
    final rel = _latest;
    final busy = _phase == _Phase.downloading || _phase == _Phase.sending;
    final newer = rel != null && rel.isNewerThan(current);
    final text = Theme.of(context).textTheme;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Firmware update')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('On the gauge'),
              trailing: Text(current, style: text.titleMedium),
            ),
            ListTile(
              title: const Text('Latest release'),
              trailing: _phase == _Phase.checking
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(rel?.version ?? '–', style: text.titleMedium),
            ),
            if (rel != null && rel.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(rel.notes),
              ),
            const SizedBox(height: 16),
            if (!conn.otaSupported)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('This gauge\'s firmware is too old for Bluetooth updates. '
                    'Flash version 0.5.0 or later over USB once; after that, updates '
                    'can be done from here.'),
              )
            else if (busy || _phase == _Phase.done) ...[
              LinearProgressIndicator(
                  value: _phase == _Phase.downloading ? null : _progress),
              const SizedBox(height: 12),
              Text(
                switch (_phase) {
                  _Phase.downloading => 'Downloading…',
                  _Phase.sending =>
                    'Sending to gauge… ${(_progress * 100).toStringAsFixed(0)}%\n'
                        'Keep the phone close and the app open.',
                  _ => 'Done. The gauge is restarting.',
                },
                textAlign: TextAlign.center,
              ),
            ] else ...[
              if (rel != null && !newer)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('The gauge is up to date.', textAlign: TextAlign.center),
                ),
              FilledButton.icon(
                onPressed: rel == null ? null : _install,
                icon: const Icon(Icons.system_update),
                label: Text('${newer ? 'Install' : 'Reinstall'} ${rel?.version ?? ''}'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _check, child: const Text('Check again')),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
