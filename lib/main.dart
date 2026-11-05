import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'ble/gauge_ble.dart';
import 'screens/scan_screen.dart';

/// Hide the phone's navigation bar (and status bar). Swiping up from the
/// bottom edge shows them briefly; Android hides them again by itself.
void hideSystemBars() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  hideSystemBars();
  runApp(
    ChangeNotifierProvider(
      create: (_) => GaugeConnection(),
      child: const GaugeApp(),
    ),
  );
}

class GaugeApp extends StatefulWidget {
  const GaugeApp({super.key});

  @override
  State<GaugeApp> createState() => _GaugeAppState();
}

class _GaugeAppState extends State<GaugeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Android can bring the bars back after switching apps or using the
  // keyboard, so hide them again whenever the app comes back to the front.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) hideSystemBars();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gauge Setup',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const ScanScreen(),
    );
  }
}
