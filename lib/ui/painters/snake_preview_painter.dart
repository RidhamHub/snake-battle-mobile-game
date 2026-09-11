import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants.dart';
import 'eye_painter.dart';

/// A single animated snake swimming through a box, used on the home screen and
/// in the customisation preview. Both screens used to carry their own copy;
/// sharing it means a skin looks identical everywhere.
class SnakePreviewPainter extends CustomPainter {
  final double t;
  final Color primaryColor;
  final Color secondaryColor;
  final SkinType skinType;
  final EyeStyle eyeStyle;

  /// Diameter of a body segment in logical pixels.
  final double segmentSize;
  final int segments;

  SnakePreviewPainter({
    required this.t,
    required this.primaryColor,
    required this.secondaryColor,
    required this.skinType,
    required this.eyeStyle,
    this.segmentSize = 26,
    this.segments = 9,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = segmentSize * 0.72;
    final totalWidth = (segments - 1) * spacing;
    final startX = (size.width - totalWidth) / 2 + totalWidth;
    final centerY = size.height / 2;
    final amplitude = math.min(size.height * 0.18, segmentSize * 0.55);

    // Index 0 is the head, at the right-hand end, travelling right.
    final centers = List<Offset>.generate(segments, (i) {
      final x = startX - i * spacing;
      final y = centerY + math.sin(t * math.pi * 2 - i * 0.62) * amplitude;
      return Offset(x, y);
    });

    final width = segmentSize;

    // Glow layer for neon skins.
    if (skinType == SkinType.neon) {
      final glowPath = Path()..moveTo(centers.last.dx, centers.last.dy);
      for (var i = centers.length - 2; i >= 0; i--) {
        glowPath.lineTo(centers[i].dx, centers[i].dy);
      }
      canvas.drawPath(
        glowPath,
        Paint()
          ..color = primaryColor.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 1.7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final path = Path()..moveTo(centers.last.dx, centers.last.dy);
    for (var i = centers.length - 2; i >= 0; i--) {
      path.lineTo(centers[i].dx, centers[i].dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = secondaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final fill = Paint()..style = PaintingStyle.fill;

    switch (skinType) {
      case SkinType.striped:
        fill.color = primaryColor;
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawCircle(centers[i], width * 0.46, fill);
        }
      case SkinType.spotted:
        fill.color = primaryColor;
        for (var i = 1; i < centers.length; i++) {
          canvas.drawCircle(centers[i], width * 0.18, fill);
        }
      case SkinType.patterned:
        fill.color = primaryColor.withValues(alpha: 0.72);
        for (var i = 2; i < centers.length; i += 3) {
          canvas.drawCircle(centers[i], width * 0.31, fill);
        }
      case SkinType.pixel:
        fill.color = secondaryColor;
        for (var i = 1; i < centers.length; i++) {
          canvas.drawRect(
            Rect.fromCenter(center: centers[i], width: width, height: width),
            fill,
          );
        }
        fill.color = primaryColor.withValues(alpha: 0.25);
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawRect(
            Rect.fromCenter(center: centers[i], width: width, height: width),
            fill,
          );
        }
      case SkinType.neon:
        fill.color = primaryColor.withValues(alpha: 0.35);
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawCircle(centers[i], width * 0.31, fill);
        }
      case SkinType.standard:
      case SkinType.rounded:
        break;
    }

    // Tapered tail.
    for (var i = centers.length - 1; i >= centers.length - 2 && i > 0; i--) {
      fill.color = secondaryColor;
      final shrink = i == centers.length - 1 ? 0.33 : 0.43;
      canvas.drawCircle(centers[i], width * shrink, fill);
    }

    // Head.
    fill.color = primaryColor;
    canvas.drawCircle(centers.first, width * 0.54, fill);
    canvas.drawCircle(
      centers.first,
      width * 0.54,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    EyeRenderer.draw(
      canvas,
      center: centers.first,
      cellSize: width * 1.08,
      style: eyeStyle,
    );
  }

  @override
  bool shouldRepaint(covariant SnakePreviewPainter old) =>
      old.t != t ||
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.skinType != skinType ||
      old.eyeStyle != eyeStyle;
}

/// Tiny three-segment swatch used in the skin grid.
class SkinSwatchPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final SkinType type;

  SkinSwatchPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.type,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.26;
    final cy = size.height / 2;
    final spacing = r * 1.75;
    final startX = size.width / 2 - spacing;

    final centers = [
      Offset(startX + spacing * 2, cy),
      Offset(startX + spacing, cy),
      Offset(startX, cy),
    ];

    final stroke = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(centers.last, centers.first, stroke);

    final fill = Paint();
    if (type == SkinType.striped) {
      fill.color = primaryColor;
      canvas.drawCircle(centers[1], r * 0.95, fill);
    } else if (type == SkinType.spotted) {
      fill.color = primaryColor;
      canvas.drawCircle(centers[1], r * 0.4, fill);
      canvas.drawCircle(centers[2], r * 0.4, fill);
    } else if (type == SkinType.pixel) {
      fill.color = secondaryColor;
      for (var i = 1; i < 3; i++) {
        canvas.drawRect(Rect.fromCenter(center: centers[i], width: r * 2, height: r * 2), fill);
      }
    } else if (type == SkinType.neon) {
      fill.color = primaryColor.withValues(alpha: 0.4);
      canvas.drawCircle(centers[1], r * 1.3, fill);
    } else if (type == SkinType.patterned) {
      fill.color = primaryColor.withValues(alpha: 0.7);
      canvas.drawCircle(centers[2], r * 0.7, fill);
    }

    fill.color = primaryColor;
    canvas.drawCircle(centers.first, r * 1.08, fill);
  }

  @override
  bool shouldRepaint(covariant SkinSwatchPainter old) =>
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.type != type;
}
