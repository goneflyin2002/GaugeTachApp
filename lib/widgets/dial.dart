import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/gauge_models.dart';

/// A drawn copy of the gauge face, showing where the real needle is.
/// The gap in the sweep is centered at the bottom, like most tachs.
class GaugeDial extends StatelessWidget {
  final GaugeConfig config;
  final double needleDeg;
  final double readout;
  final String label;

  const GaugeDial({
    super.key,
    required this.config,
    required this.needleDeg,
    required this.readout,
    this.label = 'RPM',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DialPainter(
          config: config,
          needleDeg: needleDeg,
          face: scheme.surfaceContainerHighest,
          ink: scheme.onSurface,
          dim: scheme.onSurfaceVariant,
          needle: scheme.primary,
        ),
        child: Align(
          alignment: const Alignment(0, 0.45),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                readout.toStringAsFixed(0),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final GaugeConfig config;
  final double needleDeg;
  final Color face, ink, dim, needle;

  _DialPainter({
    required this.config,
    required this.needleDeg,
    required this.face,
    required this.ink,
    required this.dim,
    required this.needle,
  });

  // Canvas angles: 0 = 3 o'clock, clockwise positive. 90 = straight down.
  double get _startDeg => 90 + (360 - config.sweep) / 2;
  double _rad(double faceDeg) => (_startDeg + faceDeg) * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    canvas.drawCircle(c, r, Paint()..color = face);

    // Track
    final track = Paint()
      ..color = dim.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.02;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.86), _rad(0),
        config.sweep * math.pi / 180, false, track);

    // Ticks every 500, labels every 1000 (in thousands)
    final full = config.fullScale;
    final major = full > 20000 ? 5000.0 : 1000.0;
    final minor = major / 2;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (double v = 0; v <= full + 0.1; v += minor) {
      final isMajor = (v % major).abs() < 0.1;
      final a = _rad(config.valueToDeg(v));
      final dir = Offset(math.cos(a), math.sin(a));
      final outer = c + dir * r * 0.92;
      final inner = c + dir * r * (isMajor ? 0.78 : 0.84);
      canvas.drawLine(
          inner,
          outer,
          Paint()
            ..color = isMajor ? ink : dim
            ..strokeWidth = isMajor ? r * 0.025 : r * 0.012
            ..strokeCap = StrokeCap.round);
      if (isMajor) {
        tp.text = TextSpan(
          text: (v / 1000).toStringAsFixed(0),
          style: TextStyle(color: ink, fontSize: r * 0.11, fontWeight: FontWeight.w600),
        );
        tp.layout();
        final p = c + dir * r * 0.64;
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Needle
    final a = _rad(needleDeg.clamp(-20.0, config.sweep + 20.0).toDouble());
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
        c - dir * r * 0.12,
        c + dir * r * 0.82,
        Paint()
          ..color = needle
          ..strokeWidth = r * 0.03
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, r * 0.06, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.needleDeg != needleDeg ||
      old.config != config ||
      old.face != face ||
      old.needle != needle;
}
