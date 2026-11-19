// App colours: a classic-instrument look.
//   Needle: signal red.   Titles / buttons / sliders: amber dash-light.
//   Dark mode: near-black charcoal with white markings.
//
// Colours are set explicitly rather than generated from one seed colour,
// because Material 3's automatic dark palette washes them out to pastels.

import 'package:flutter/material.dart';

class GaugeColors {
  // Needle
  static const needleDark = Color(0xFFFF3B30);
  static const needleLight = Color(0xFFD32F2F);

  // Amber accent
  static const amberDark = Color(0xFFFFB300); // on charcoal
  static const amberLight = Color(0xFFB25E00); // readable on white

  // Dark-mode surfaces
  static const charcoal = Color(0xFF121417);
  static const charcoalRaised = Color(0xFF1B1E22);
  static const dialFaceDark = Color(0xFF23272C);

  static Color needle(Brightness b) => b == Brightness.dark ? needleDark : needleLight;
}

ThemeData buildGaugeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final amber = dark ? GaugeColors.amberDark : GaugeColors.amberLight;

  var scheme = ColorScheme.fromSeed(
    seedColor: GaugeColors.amberDark,
    brightness: brightness,
    // Keep the seed's real saturation instead of softening it.
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  ).copyWith(
    primary: amber,
    onPrimary: dark ? Colors.black : Colors.white,
    error: dark ? const Color(0xFFFF6B60) : const Color(0xFFC62828),
  );

  if (dark) {
    scheme = scheme.copyWith(
      surface: GaugeColors.charcoal,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFB4B9C0),
      surfaceContainerLow: GaugeColors.charcoalRaised,
      surfaceContainer: GaugeColors.charcoalRaised,
      surfaceContainerHigh: const Color(0xFF202429),
      surfaceContainerHighest: GaugeColors.dialFaceDark,
      outlineVariant: const Color(0xFF3A3F45),
    );
  } else {
    scheme = scheme.copyWith(
      surfaceContainerHighest: const Color(0xFFECEEF1), // dial face
    );
  }

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: amber,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: amber,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: amber,
      thumbColor: amber,
      inactiveTrackColor: scheme.outlineVariant,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      labelStyle: TextStyle(color: scheme.onSurface),
      side: BorderSide(color: scheme.outlineVariant),
    ),
  );
}
