import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/gauge_ble.dart';
import 'gauge_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    try {
      await GaugeScanner.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    }
  }

  Future<void> _connect(FoundGauge g) async {
    await GaugeScanner.stop();
    if (!mounted) return;
    setState(() => _connectingId = g.id);
    final conn = context.read<GaugeConnection>();
    final ok = await conn.connect(g);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (ok) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const GaugeScreen()));
      await conn.disconnect();
      _scan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(conn.error ?? 'Could not connect')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gauges nearby')),
      body: StreamBuilder<bool>(
        stream: GaugeScanner.adapterReady,
        initialData: true,
        builder: (context, snap) {
          if (snap.data == false) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_disabled, size: 48),
                  const SizedBox(height: 12),
                  const Text('Bluetooth is off or not allowed'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: GaugeScanner.turnOn,
                      child: const Text('Turn on Bluetooth')),
                ],
              ),
            );
          }
          return StreamBuilder<List<FoundGauge>>(
            stream: GaugeScanner.results,
            initialData: const [],
            builder: (context, snap) {
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Looking for gauges…\nMake sure the gauge is powered.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView(
                children: [
                  for (final g in list)
                    ListTile(
                      leading: const Icon(Icons.speed),
                      title: Text(g.name),
                      subtitle: Text('Signal ${g.rssi} dBm'),
                      trailing: _connectingId == g.id
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: _connectingId == null ? () => _connect(g) : null,
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: GaugeScanner.isScanning,
        initialData: false,
        builder: (context, snap) => snap.data == true
            ? FloatingActionButton.extended(
                onPressed: GaugeScanner.stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'))
            : FloatingActionButton.extended(
                onPressed: _scan,
                icon: const Icon(Icons.search),
                label: const Text('Scan')),
      ),
    );
  }
}
