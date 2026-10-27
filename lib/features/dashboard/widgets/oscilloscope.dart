import 'package:flutter/material.dart';
import 'dart:collection';

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
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF10151D), // darkScopeBg из нашей темы
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        // RepaintBoundary спасает батарею, изолируя перерисовку
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ScopePainter(
              trace1: trace1.toList(),
              trace2: trace2?.toList(),
              minVal: minValue,
              maxVal: maxValue,
              color1: color1,
              color2: color2 ?? Colors.transparent,
              gridColor: const Color(0xFF243040),
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
    // 1. Отрисовка фоновой сетки (Grid)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    
    // Горизонтальные линии
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Вертикальные линии
    for (int i = 1; i < 6; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // 2. Логика отрисовки самой кривой
    void drawTrace(List<double> trace, Color color) {
      if (trace.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      // Выделяем ширину шага, предполагая, что на экране хранится до 100 точек
      final stepX = size.width / 99; 
      final range = maxVal - minVal;
      if (range == 0) return;

      for (int i = 0; i < trace.length; i++) {
        final x = i * stepX;
        // Нормализация (от 0.0 до 1.0) и инверсия (ось Y во Flutter идет сверху вниз)
        double normalizedY = (trace[i] - minVal) / range;
        normalizedY = normalizedY.clamp(0.0, 1.0);
        final y = size.height - (normalizedY * size.height);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Рисуем графики
    drawTrace(trace1, color1);
    if (trace2 != null) {
      drawTrace(trace2!, color2);
    }
  }

  @override
  bool shouldRepaint(covariant _ScopePainter oldDelegate) => true; 
}