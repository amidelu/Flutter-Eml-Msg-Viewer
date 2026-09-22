import 'package:flutter/material.dart';

/// A single labeled header line, e.g. `From: Jane Doe <jane@example.com>`.
class HeaderRow extends StatelessWidget {
  const HeaderRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value, style: tt.bodySmall?.copyWith(color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
