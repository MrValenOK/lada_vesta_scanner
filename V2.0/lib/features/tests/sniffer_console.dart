// lib/features/tests/sniffer_console.dart — консоль HEX-сниффера.
// Вынесена из tests_screen.dart (лимит 400 строк/файл). Цвета — токены AppColors.
import 'package:flutter/material.dart';

import '../../core/theme.dart';

class SnifferConsole extends StatelessWidget {
  const SnifferConsole({super.key, required this.lines, required this.scroll});

  final List<String> lines;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.scopeBg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      padding: const EdgeInsets.all(S.s3),
      child: ListView.builder(
        controller: scroll,
        itemCount: lines.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SelectableText(lines[i],
              style: AppTheme.mono(size: T.sm, color: c.text1)),
        ),
      ),
    );
  }
}
