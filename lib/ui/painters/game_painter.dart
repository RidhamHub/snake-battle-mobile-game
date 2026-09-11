import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../constants.dart';

import '../../game/snake_game.dart';
import 'eye_painter.dart';

/// Paints the arena floor: checkerboard, grid lines and vignette.
///
/// None of this changes during a match, so it lives in its own
/// [RepaintBoundary] with `shouldRepaint => false` and is rasterised once
/// instead of redrawing ~900 cells every frame.
class ArenaBackgroundPainter extends CustomPainter {
  const ArenaBackgroundPainter();

  static final Paint _darkCell = Paint()..color = const Color(0xFF0A0E1A);
  static final Paint _lightCell = Paint()..color = const Color(0xFF0E1526);
  static final Paint _gridLine = Paint()
    ..color = const Color(0x0DFFFFFF)
    ..strokeWidth = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / GameConstants.gridSize;

    for (var row = 0; row < GameConstants.gridSize; row++) {
      for (var col = 0; col < GameConstants.gridSize; col++) {
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell, cell),
          (row + col) % 2 == 0 ? _darkCell : _lightCell,
        );
      }
    }

    for (var i = 0; i <= GameConstants.gridSize; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), _gridLine);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), _gridLine);
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.42)],
          stops: const [0.6, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant ArenaBackgroundPainter oldDelegate) => false;
}

/// Paints everything that moves: obstacles, food, power-ups, snakes and the
/// whole effects layer.
class GamePainter extends CustomPainter {
  final SnakeGame game;

  /// 0..1 progress between the previous and current simulation tick.
  final double renderT;

  /// Free-running seconds, used for idle pulses that should not stutter when
  /// the simulation is paused.
  final double clock;

  GamePainter({
    required this.game,
    required this.renderT,
    required this.clock,
  });

  static final Paint _fill = Paint()..style = PaintingStyle.fill;

  /// Cached laid-out paragraphs for floating text and power-up glyphs.
  ///
  /// Score callouts produce an unbounded set of distinct strings over a long
  /// session, so the cache is capped and cleared wholesale once it grows past
  /// the limit rather than being allowed to leak.
  static final Map<String, ui.Paragraph> _textCache = {};
  static const int _textCacheLimit = 160;

  static ui.Paragraph _cachedParagraph(String key, ui.Paragraph Function() build) {
    final hit = _textCache[key];
    if (hit != null) return hit;
    if (_textCache.length >= _textCacheLimit) _textCache.clear();
    final made = build();
    _textCache[key] = made;
    return made;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / GameConstants.gridSize;
    final effects = game.effects;

    canvas.save();
    // Screen shake is expressed in grid units so it scales with the arena.
    canvas.translate(effects.shakeX * cell, effects.shakeY * cell);

    _drawObstacles(canvas, cell);
    _drawFood(canvas, cell);
    _drawPowerUps(canvas, cell);
    _drawShockwaves(canvas, cell);

    // Rivals first so the player always reads on top of the pile.
    for (final rival in game.rivals) {
      if (!rival.isAlive) continue;
      final c = game.rivalColor(rival);
      _drawSnake(
        canvas,
        cell,
        rival,
        primary: c,
        secondary: Color.lerp(c, Colors.black, 0.42)!,
        type: SkinType.rounded,
        eyeStyle: EyeStyle.classic,
        isPlayer: false,
      );
    }

    if (game.hasPlayer && _playerVisible) {
      final skin = game.currentSkin;
      _drawSnake(
        canvas,
        cell,
        game.playerSnake,
        primary: skin.primaryColor,
        secondary: skin.secondaryColor,
        type: skin.type,
        eyeStyle: game.currentEye.style,
        isPlayer: true,
      );
    }

    _drawParticles(canvas, cell);
    _drawFloatingText(canvas, cell);

    canvas.restore();

    final flash = effects.flashColor;
    if (flash != null && effects.flashOpacity > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = flash.withValues(alpha: flash.a * effects.flashOpacity),
      );
    }
  }

  /// The player blinks out during the death animation.
  bool get _playerVisible {
    if (!game.isDying) {
      // Blink while the post-revive grace window is running.
      if (game.graceTimer > 0) return (clock * 9).floor() % 2 == 0;
      return true;
    }
    return (clock * 12).floor() % 2 == 0;
  }

  // ── Static hazards ───────────────────────────────────────────────────

  void _drawObstacles(Canvas canvas, double cell) {
    if (game.obstacles.isEmpty) return;
    final body = Paint()..color = GameConstants.obstacleColor;
    final edge = Paint()
      ..color = const Color(0xFF5C6E96).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final o in game.obstacles) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(o.x * cell + cell * 0.06, o.y * cell + cell * 0.06,
            cell * 0.88, cell * 0.88),
        Radius.circular(cell * 0.18),
      );
      canvas.drawRRect(rect, body);
      canvas.drawRRect(rect, edge);
    }
  }

  // ── Food ─────────────────────────────────────────────────────────────

  void _drawFood(Canvas canvas, double cell) {
    for (final f in game.food) {
      final cx = f.pos.x * cell + cell / 2;
      final cy = f.pos.y * cell + cell / 2;
      final pulse = 0.86 + 0.14 * math.sin((clock * 2.4 + f.phase * 6.28) * math.pi);

      switch (f.kind) {
        case FoodKind.golden:
          final r = cell * 0.42 * pulse;
          // Expiring pellets fade out so the timer is readable at a glance.
          final ttl = f.ttl ?? GameConstants.goldenLifetimeSeconds;
          final urgency = (ttl / GameConstants.goldenLifetimeSeconds).clamp(0.0, 1.0);
          final blink = ttl < 2.0 ? (0.45 + 0.55 * math.sin(clock * 22)) : 1.0;

          _fill.color = GameConstants.gold.withValues(alpha: 0.22 * blink);
          canvas.drawCircle(Offset(cx, cy), r * 1.9, _fill);
          _fill.color = GameConstants.gold.withValues(alpha: blink.clamp(0.0, 1.0));
          canvas.drawCircle(Offset(cx, cy), r, _fill);
          _fill.color = const Color(0xFFFFF3C4).withValues(alpha: blink.clamp(0.0, 1.0));
          canvas.drawCircle(Offset(cx, cy), r * 0.52, _fill);
          _drawSparkle(canvas, Offset(cx, cy), r * 1.5, blink);

          // Thin countdown arc around the pellet.
          canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.5),
            -math.pi / 2,
            math.pi * 2 * urgency,
            false,
            Paint()
              ..color = GameConstants.gold.withValues(alpha: 0.75)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round,
          );

        case FoodKind.corpse:
          final r = cell * 0.26 * pulse;
          _fill.color = const Color(0xFF8FA3C4).withValues(alpha: 0.30);
          canvas.drawCircle(Offset(cx, cy), r * 1.5, _fill);
          _fill.color = const Color(0xFFB9C7DE);
          canvas.drawCircle(Offset(cx, cy), r, _fill);

        case FoodKind.normal:
          final r = cell * 0.34 * pulse;
          _fill.color = const Color(0xFFFFA502).withValues(alpha: 0.20);
          canvas.drawCircle(Offset(cx, cy), r * 1.7, _fill);
          _fill.color = const Color(0xFFFFB733);
          canvas.drawCircle(Offset(cx, cy), r, _fill);
          _fill.color = const Color(0xFFFFDD57);
          canvas.drawCircle(Offset(cx, cy), r * 0.55, _fill);
          _fill.color = Colors.white.withValues(alpha: 0.65);
          canvas.drawCircle(Offset(cx - r * 0.3, cy - r * 0.3), r * 0.22, _fill);
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, double alpha) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.75 * alpha.clamp(0.0, 1.0))
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final spin = clock * 1.4;
    for (var i = 0; i < 4; i++) {
      final a = spin + i * math.pi / 2;
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r * 0.55, c.dy + math.sin(a) * r * 0.55),
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        p,
      );
    }
  }

  // ── Power-ups ────────────────────────────────────────────────────────

  void _drawPowerUps(Canvas canvas, double cell) {
    for (final p in game.powerUps) {
      final cfg = PowerConfig.of(p.type);
      final cx = p.pos.x * cell + cell / 2;
      final cy = p.pos.y * cell + cell / 2;

      final bob = math.sin((clock * 2.2 + p.phase * 6.28)) * cell * 0.08;
      final expiring = p.ttl < 2.5;
      final blink = expiring ? (0.4 + 0.6 * math.sin(clock * 20)).clamp(0.0, 1.0) : 1.0;
      final center = Offset(cx, cy + bob);
      final r = cell * 0.62;

      _fill.color = cfg.color.withValues(alpha: 0.20 * blink);
      canvas.drawCircle(center, r * 1.5, _fill);
      _fill.color = cfg.color.withValues(alpha: 0.32 * blink);
      canvas.drawCircle(center, r * 1.1, _fill);

      final tile = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: r * 1.5, height: r * 1.5),
        Radius.circular(cell * 0.22),
      );
      canvas.drawRRect(tile, Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.92 * blink));
      canvas.drawRRect(
        tile,
        Paint()
          ..color = cfg.color.withValues(alpha: blink)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      _drawIcon(canvas, cfg.icon, center, cell * 0.62, cfg.color.withValues(alpha: blink));
    }
  }

  void _drawIcon(Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final key = 'icon:${icon.codePoint}:${size.toStringAsFixed(1)}:${color.toARGB32()}';
    final para = _cachedParagraph(key, () {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontFamily: icon.fontFamily,
        fontSize: size,
        textAlign: TextAlign.center,
      ))
        ..pushStyle(ui.TextStyle(color: color, fontFamily: icon.fontFamily))
        ..addText(String.fromCharCode(icon.codePoint));
      return builder.build()..layout(ui.ParagraphConstraints(width: size * 2));
    });
    canvas.drawParagraph(para, Offset(center.dx - size, center.dy - para.height / 2));
  }

  // ── Snakes ───────────────────────────────────────────────────────────

  /// Interpolated pixel centre for segment [i] of [snake].
  Offset _segmentCenter(Snake snake, int i, double cell) {
    final target = snake.body[i];
    final source = i < snake.body.length - 1
        ? snake.body[i + 1]
        : (snake.prevTail ?? snake.body[i]);

    // A wrapped step jumps across the arena; snapping avoids a segment
    // streaking through the middle of the board.
    final dx = (target.x - source.x).abs();
    final dy = (target.y - source.y).abs();
    if (dx > 1 || dy > 1) {
      return Offset(target.x * cell + cell / 2, target.y * cell + cell / 2);
    }

    final x = source.x + (target.x - source.x) * renderT;
    final y = source.y + (target.y - source.y) * renderT;
    return Offset(x * cell + cell / 2, y * cell + cell / 2);
  }

  void _drawSnake(
    Canvas canvas,
    double cell,
    Snake snake, {
    required Color primary,
    required Color secondary,
    required SkinType type,
    required EyeStyle eyeStyle,
    required bool isPlayer,
  }) {
    if (snake.body.isEmpty) return;

    final n = snake.body.length;
    final centers = List<Offset>.generate(
      n,
      (i) => _segmentCenter(snake, i, cell),
      growable: false,
    );

    final phasing = isPlayer && game.activeEffects.containsKey(PowerType.phase);
    final opacity = phasing ? 0.55 : 1.0;

    // ── Aura for the player: power-ups and boost read as a halo ──
    if (isPlayer) _drawPlayerAura(canvas, centers.first, cell);

    // ── Continuous body ──
    // The path is split wherever two consecutive segments are not adjacent,
    // which happens exactly when the snake wraps around an edge.
    final bodyWidth = cell * 0.92;
    final strokes = <Path>[];
    Path current = Path()..moveTo(centers[0].dx, centers[0].dy);
    var started = true;

    for (var i = 1; i < n; i++) {
      final gap = (centers[i] - centers[i - 1]).distance;
      if (gap > cell * 1.6) {
        if (started) strokes.add(current);
        current = Path()..moveTo(centers[i].dx, centers[i].dy);
        started = true;
      } else {
        current.lineTo(centers[i].dx, centers[i].dy);
      }
    }
    if (started) strokes.add(current);

    final glow = type == SkinType.neon || phasing;
    if (glow) {
      final glowPaint = Paint()
        ..color = primary.withValues(alpha: 0.28 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth * 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final p in strokes) {
        canvas.drawPath(p, glowPaint);
      }
    }

    final bodyPaint = Paint()
      ..color = secondary.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in strokes) {
      canvas.drawPath(p, bodyPaint);
    }

    // ── Skin pattern overlay ──
    _drawPattern(canvas, centers, cell, type, primary, secondary, opacity);

    // ── Tapered tail: shrink the final segments so it reads as a tail ──
    if (n >= 3) {
      for (var i = n - 1; i >= n - 2; i--) {
        final shrink = i == n - 1 ? 0.34 : 0.44;
        _fill.color = secondary.withValues(alpha: opacity);
        canvas.drawCircle(centers[i], bodyWidth * shrink, _fill);
      }
    }

    // ── Head ──
    final head = centers[0];
    final headR = cell * 0.5;

    _fill.color = primary.withValues(alpha: opacity);
    canvas.drawCircle(head, headR, _fill);

    if (isPlayer) {
      canvas.drawCircle(
        head,
        headR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    } else {
      // Rivals get a length badge so the player can judge head-on trades.
      canvas.drawCircle(
        head,
        headR,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    EyeRenderer.draw(
      canvas,
      center: head,
      cellSize: cell,
      direction: snake.direction,
      style: eyeStyle,
      opacity: opacity,
    );

    // Tongue flick on the player, purely for character.
    if (isPlayer && (clock * 1.6).floor() % 3 == 0) {
      _drawTongue(canvas, head, snake.direction, cell, opacity);
    }
  }

  void _drawPlayerAura(Canvas canvas, Offset head, double cell) {
    final effectsUp = game.activeEffects.values.toList();
    var ringIndex = 0;

    if (game.hasShield) {
      final c = PowerConfig.of(PowerType.shield).color;
      final pulse = 0.8 + 0.2 * math.sin(clock * 5);
      canvas.drawCircle(
        head,
        cell * 1.05 * pulse,
        Paint()
          ..color = c.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(head, cell * 1.05 * pulse, Paint()..color = c.withValues(alpha: 0.10));
    }

    for (final e in effectsUp) {
      if (e.type == PowerType.shield) continue;
      final c = PowerConfig.of(e.type).color;
      final radius = cell * (0.78 + ringIndex * 0.22) * (0.9 + 0.1 * math.sin(clock * 6 + ringIndex));
      // Fade the ring out as the effect runs down.
      final fade = e.remaining < 1.5 ? (e.remaining / 1.5).clamp(0.0, 1.0) : 1.0;
      canvas.drawCircle(
        head,
        radius,
        Paint()
          ..color = c.withValues(alpha: 0.35 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      ringIndex++;
    }

    if (game.isBoosting) {
      canvas.drawCircle(head, cell * 0.9, Paint()..color = Colors.white.withValues(alpha: 0.12));
    }
  }

  void _drawPattern(
    Canvas canvas,
    List<Offset> centers,
    double cell,
    SkinType type,
    Color primary,
    Color secondary,
    double opacity,
  ) {
    switch (type) {
      case SkinType.striped:
        _fill.color = primary.withValues(alpha: opacity);
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawCircle(centers[i], cell * 0.44, _fill);
        }
      case SkinType.spotted:
        _fill.color = primary.withValues(alpha: opacity);
        for (var i = 1; i < centers.length; i++) {
          canvas.drawCircle(centers[i], cell * 0.17, _fill);
        }
      case SkinType.patterned:
        _fill.color = primary.withValues(alpha: 0.72 * opacity);
        for (var i = 2; i < centers.length; i += 3) {
          canvas.drawCircle(centers[i], cell * 0.3, _fill);
        }
      case SkinType.pixel:
        _fill.color = secondary.withValues(alpha: opacity);
        for (var i = 1; i < centers.length; i++) {
          canvas.drawRect(
            Rect.fromCenter(center: centers[i], width: cell * 0.9, height: cell * 0.9),
            _fill,
          );
        }
        _fill.color = primary.withValues(alpha: 0.25 * opacity);
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawRect(
            Rect.fromCenter(center: centers[i], width: cell * 0.9, height: cell * 0.9),
            _fill,
          );
        }
      case SkinType.neon:
        _fill.color = primary.withValues(alpha: 0.35 * opacity);
        for (var i = 1; i < centers.length; i += 2) {
          canvas.drawCircle(centers[i], cell * 0.3, _fill);
        }
      case SkinType.standard:
      case SkinType.rounded:
        break;
    }
  }

  void _drawTongue(Canvas canvas, Offset head, Direction dir, double cell, double opacity) {
    final len = cell * 0.55;
    final dx = dir.dx.toDouble();
    final dy = dir.dy.toDouble();
    final tip = Offset(head.dx + dx * len, head.dy + dy * len);
    final base = Offset(head.dx + dx * cell * 0.35, head.dy + dy * cell * 0.35);

    final p = Paint()
      ..color = const Color(0xFFFF5C7A).withValues(alpha: 0.9 * opacity)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(base, tip, p);
    // Forked tip, perpendicular to travel.
    final px = -dy, py = dx;
    canvas.drawLine(tip, Offset(tip.dx + px * cell * 0.14 + dx * cell * 0.12,
        tip.dy + py * cell * 0.14 + dy * cell * 0.12), p);
    canvas.drawLine(tip, Offset(tip.dx - px * cell * 0.14 + dx * cell * 0.12,
        tip.dy - py * cell * 0.14 + dy * cell * 0.12), p);
  }

  // ── Effects layer ────────────────────────────────────────────────────

  void _drawShockwaves(Canvas canvas, double cell) {
    for (final w in game.effects.waves) {
      final r = w.maxRadius * w.progress * cell;
      final alpha = (1 - w.progress).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(w.x * cell, w.y * cell),
        r,
        Paint()
          ..color = w.color.withValues(alpha: 0.55 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * alpha + 0.5,
      );
    }
  }

  void _drawParticles(Canvas canvas, double cell) {
    for (final p in game.effects.particles) {
      final a = p.t;
      final r = p.size * cell * (0.4 + a * 0.6);
      final center = Offset(p.x * cell, p.y * cell);
      if (p.glow) {
        _fill.color = p.color.withValues(alpha: 0.25 * a);
        canvas.drawCircle(center, r * 2.2, _fill);
      }
      _fill.color = p.color.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(center, r, _fill);
    }
  }

  void _drawFloatingText(Canvas canvas, double cell) {
    for (final t in game.effects.texts) {
      final alpha = t.t < 0.35 ? t.t / 0.35 : 1.0;
      final key = '${t.text}|${t.color.toARGB32()}|${t.fontSize}';
      final para = _cachedParagraph(key, () {
        final b = ui.ParagraphBuilder(ui.ParagraphStyle(
          fontSize: t.fontSize,
          fontWeight: FontWeight.w900,
          textAlign: TextAlign.center,
        ))
          ..pushStyle(ui.TextStyle(
            color: t.color,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ))
          ..addText(t.text);
        return b.build()..layout(const ui.ParagraphConstraints(width: 160));
      });

      canvas.save();
      canvas.translate(t.x * cell - 80, t.y * cell - para.height);
      // Fade by compositing the whole paragraph, cheaper than re-laying it out.
      if (alpha < 1) {
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, 160, para.height),
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
        canvas.drawParagraph(para, Offset.zero);
        canvas.restore();
      } else {
        canvas.drawParagraph(para, Offset.zero);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
