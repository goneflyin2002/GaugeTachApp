import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ask for a number. Returns null if cancelled or invalid.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  required double initial,
  String unit = '',
  double? min,
  double? max,
  int decimals = 0,
}) async {
  final ctl = TextEditingController(text: initial.toStringAsFixed(decimals));
  String? err;
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final v = double.tryParse(ctl.text.trim());
          if (v == null) {
            setState(() => err = 'Enter a number');
          } else if ((min != null && v < min) || (max != null && v > max)) {
            setState(() => err = 'Range ${min ?? ''} – ${max ?? ''}');
          } else {
            Navigator.pop(ctx, v);
          }
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(suffixText: unit, errorText: err),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    ),
  );
  // The keyboard can bring the phone's nav bar back; hide it again.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  return result;
}

/// A tappable row showing a numeric setting.
class NumberSetting extends StatelessWidget {
  final String label;
  final String? help;
  final double value;
  final String unit;
  final int decimals;
  final double? min, max;
  final ValueChanged<double> onChanged;

  const NumberSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.help,
    this.unit = '',
    this.decimals = 0,
    this.min,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: help == null ? null : Text(help!),
      trailing: Text(
        '${value.toStringAsFixed(decimals)} $unit'.trim(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () async {
        final v = await askNumber(context,
            title: label, initial: value, unit: unit, min: min, max: max, decimals: decimals);
        if (v != null) onChanged(v);
      },
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
