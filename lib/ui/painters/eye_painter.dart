import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../game/models.dart';

/// Draws snake eyes in every style, in one place.
///
/// The arena, the home-screen preview and the customisation preview all used
/// to carry their own near-duplicate copy of this logic, which is how they
/// drifted out of sync. They now all call [draw].
class EyeRenderer {
  const EyeRenderer._();

  /// [cellSize] is the diameter the head occupies, so the eyes scale with the
  /// arena or with whatever preview size the caller is using.
  static void draw(
    Canvas canvas, {
    required Offset center,
    required double cellSize,
    required EyeStyle style,
    Direction direction = Direction.right,
    double opacity = 1.0,
  }) {
    final offset = cellSize * 0.24;
    final eyeR = cellSize * 0.15;

    late Offset left;
    late Offset right;
    switch (direction) {
      case Direction.up:
        left = center + Offset(-offset, -offset);
        right = center + Offset(offset, -offset);
      case Direction.down:
        left = center + Offset(-offset, offset);
        right = center + Offset(offset, offset);
      case Direction.left:
        left = center + Offset(-offset, -offset);
        right = center + Offset(-offset, offset);
      case Direction.right:
        left = center + Offset(offset, -offset);
        right = center + Offset(offset, offset);
    }

    final white = Paint()..color = Colors.white.withValues(alpha: opacity);
    final dark = Paint()..color = Colors.black87.withValues(alpha: opacity);

    void bothCircles(Offset a, Offset b, double r, Paint p) {
      canvas.drawCircle(a, r, p);
      canvas.drawCircle(b, r, p);
    }

    switch (style) {
      case EyeStyle.classic:
        bothCircles(left, right, eyeR, white);
        bothCircles(left, right, eyeR * 0.58, dark);
        bothCircles(
          left - Offset(eyeR * 0.25, eyeR * 0.25),
          right - Offset(eyeR * 0.25, eyeR * 0.25),
          eyeR * 0.24,
          white,
        );

      case EyeStyle.cute:
        bothCircles(left, right, eyeR * 1.32, white);
        bothCircles(left, right, eyeR * 0.76,
            Paint()..color = const Color(0xFF6C5CE7).withValues(alpha: opacity));
        bothCircles(
          left - Offset(eyeR * 0.32, eyeR * 0.32),
          right - Offset(eyeR * 0.32, eyeR * 0.32),
          eyeR * 0.3,
          white,
        );

      case EyeStyle.angry:
        bothCircles(left, right, eyeR,
            Paint()..color = const Color(0xFFFFCDD2).withValues(alpha: opacity));
        bothCircles(left, right, eyeR * 0.55, dark);
        final brow = Paint()
          ..color = Colors.black.withValues(alpha: opacity)
          ..strokeWidth = math.max(1.6, cellSize * 0.09)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(left + Offset(-eyeR, -eyeR * 1.1), left + Offset(eyeR, -eyeR * 0.25), brow);
        canvas.drawLine(right + Offset(-eyeR, -eyeR * 0.25), right + Offset(eyeR, -eyeR * 1.1), brow);

      case EyeStyle.sleepy:
        bothCircles(left, right, eyeR, white);
        bothCircles(left, right, eyeR * 0.45, dark);
        final lid = Paint()
          ..color = Colors.black.withValues(alpha: 0.75 * opacity)
          ..strokeWidth = math.max(2.0, cellSize * 0.12)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(left + Offset(-eyeR, -eyeR * 0.15), left + Offset(eyeR, -eyeR * 0.15), lid);
        canvas.drawLine(right + Offset(-eyeR, -eyeR * 0.15), right + Offset(eyeR, -eyeR * 0.15), lid);

      case EyeStyle.wink:
        canvas.drawCircle(left, eyeR, white);
        canvas.drawCircle(left, eyeR * 0.55, dark);
        final lash = Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..strokeWidth = math.max(1.8, cellSize * 0.1)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawArc(
          Rect.fromCenter(center: right, width: eyeR * 2.2, height: eyeR * 1.4),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          lash,
        );

      case EyeStyle.star:
        bothCircles(left, right, eyeR * 1.05, white);
        _star(canvas, left, eyeR * 0.72, GameConstants.gold, opacity);
        _star(canvas, right, eyeR * 0.72, GameConstants.gold, opacity);

      case EyeStyle.heart:
        bothCircles(left, right, eyeR * 1.05, white);
        _heart(canvas, left, eyeR * 0.62, const Color(0xFFFF4081), opacity);
        _heart(canvas, right, eyeR * 0.62, const Color(0xFFFF4081), opacity);

      case EyeStyle.neon:
        final glow = Paint()..color = const Color(0xFF18FFFF).withValues(alpha: 0.35 * opacity);
        bothCircles(left, right, eyeR * 1.8, glow);
        bothCircles(left, right, eyeR * 1.05,
            Paint()..color = const Color(0xFF18FFFF).withValues(alpha: opacity));
        bothCircles(left, right, eyeR * 0.5, white);

      case EyeStyle.dizzy:
        bothCircles(left, right, eyeR, white);
        final spiral = Paint()
          ..color = const Color(0xFFB388FF).withValues(alpha: opacity)
          ..strokeWidth = math.max(1.0, cellSize * 0.055)
          ..style = PaintingStyle.stroke;
        for (final e in [left, right]) {
          canvas.drawCircle(e, eyeR * 0.68, spiral);
          canvas.drawCircle(e, eyeR * 0.34, spiral);
        }

      case EyeStyle.cool:
        final glass = Paint()..color = Colors.black.withValues(alpha: 0.9 * opacity);
        final frame = Paint()
          ..color = const Color(0xFFB0BEC5).withValues(alpha: opacity)
          ..strokeWidth = math.max(1.0, cellSize * 0.05)
          ..style = PaintingStyle.stroke;
        final lRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: left, width: eyeR * 2.3, height: eyeR * 1.7),
          Radius.circular(eyeR * 0.4),
        );
        final rRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: right, width: eyeR * 2.3, height: eyeR * 1.7),
          Radius.circular(eyeR * 0.4),
        );
        canvas.drawRRect(lRect, glass);
        canvas.drawRRect(rRect, glass);
        canvas.drawRRect(lRect, frame);
        canvas.drawRRect(rRect, frame);
        // Bridge between the lenses.
        canvas.drawLine(
          Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2),
          Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2),
          frame,
        );
        // Glare streak.
        canvas.drawLine(
          left + Offset(-eyeR * 0.7, eyeR * 0.4),
          left + Offset(eyeR * 0.2, -eyeR * 0.4),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * opacity)
            ..strokeWidth = math.max(0.8, cellSize * 0.04),
        );
    }
  }

  static void _star(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      var angle = (math.pi * 2 * i / 5) - math.pi / 2;
      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      angle += math.pi / 5;
      path.lineTo(
        center.dx + radius * 0.42 * math.cos(angle),
        center.dy + radius * 0.42 * math.sin(angle),
      );
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  static void _heart(Canvas canvas, Offset center, double size, Color color, double opacity) {
    final x = center.dx;
    final y = center.dy - size * 0.35;
    final path = Path()
      ..moveTo(x, y + size * 0.35)
      ..cubicTo(x - size * 1.3, y - size * 0.9, x - size * 2.1, y + size * 0.5, x, y + size * 1.8)
      ..cubicTo(x + size * 2.1, y + size * 0.5, x + size * 1.3, y - size * 0.9, x, y + size * 0.35)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }
}

/// Renders a single head with the given eye style, for the shop grid.
///
/// This draws the real thing rather than showing an emoji stand-in, so the
/// tile always matches what you get in the arena and never depends on the
/// platform having an emoji font for that glyph.
class EyePreviewPainter extends CustomPainter {
  final EyeStyle style;
  final Color headColor;

  EyePreviewPainter({required this.style, required this.headColor});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.42;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, r, Paint()..color = headColor);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Face the viewer: eyes side by side rather than in profile.
    EyeRenderer.draw(
      canvas,
      center: center,
      cellSize: r * 2.1,
      style: style,
      direction: Direction.down,
    );
  }

  @override
  bool shouldRepaint(covariant EyePreviewPainter old) =>
      old.style != style || old.headColor != headColor;
}
