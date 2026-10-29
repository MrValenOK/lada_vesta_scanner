// lib/features/dashboard/widgets/oscilloscope.dart — двухлучевой мини-осциллограф
// (УДК/ДДК). Портировано из рабочего lada_vesta_scanner; цвета — только токены
// AppColors (хардкод hex запрещён, AGENTS V2.0).
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class Oscilloscope extends StatelessWidget {
  final Queue<double> trace1;
  final Queue<double>? trace2;
  final double minValue;
  final double maxValue;
  final Color color1;
  final Color? color2;

  const Oscilloscope({
    super.key,
    required this.trace1,
    this.trace2,
    required this.minValue,
    required this.maxValue,
    required this.color1,
    this.color2,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.scopeBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.lg),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ScopePainter(
              trace1: trace1.toList(),
              trace2: trace2?.toList(),
              minVal: minValue,
              maxVal: maxValue,
              color1: color1,
              color2: color2 ?? Colors.transparent,
              gridColor: c.scopeGrid,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  final List<double> trace1;
  final List<double>? trace2;
  final double minVal;
  final double maxVal;
  final Color color1;
  final Color color2;
  final Color gridColor;

  _ScopePainter({
    required this.trace1,
    this.trace2,
    required this.minVal,
    required this.maxVal,
    required this.color1,
    required this.color2,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Сетка: 3 горизонтальные, 5 вертикальных линий
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (int i = 1; i < 6; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    void drawTrace(List<double> trace, Color color) {
      if (trace.isEmpty) return;
      final range = maxVal - minVal;
      if (range == 0) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final stepX = size.width / 99; // буфер до 100 точек
      for (int i = 0; i < trace.length; i++) {
        final x = i * stepX;
        final normalizedY = ((trace[i] - minVal) / range).clamp(0.0, 1.0);
        final y = size.height - (normalizedY * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawTrace(trace1, color1);
    if (trace2 != null) drawTrace(trace2!, color2);
  }

  @override
  bool shouldRepaint(covariant _ScopePainter oldDelegate) => true;
}
