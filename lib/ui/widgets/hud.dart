import 'dart:math' as math;


import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../game/snake_game.dart';

/// Frosted pill used as the base for every HUD chip.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.09),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

class HudIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const HudIconButton({super.key, required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
        ),
        child: Icon(icon, color: color ?? Colors.white, size: 22),
      ),
    );
  }
}

/// Score + personal best for the active difficulty.
class ScorePanel extends StatelessWidget {
  final SnakeGame game;
  const ScorePanel({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final best = math.max(game.currentDifficultyHighScore, game.score);
    final isRecord = game.score > game.currentDifficultyHighScore && game.score > 0;

    return GlassPanel(
      borderColor: isRecord ? GameConstants.gold.withValues(alpha: 0.5) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('SCORE', '${game.score}', Colors.white),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          _stat('BEST', '$best', isRecord ? GameConstants.gold : Colors.white54),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.6,
            )),
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

/// Big combo readout with a draining ring. Only visible while a combo is live.
class ComboBanner extends StatelessWidget {
  final SnakeGame game;
  const ComboBanner({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    if (game.combo < 2 || game.comboTimer <= 0) return const SizedBox.shrink();

    final fraction = (game.comboTimer / GameConstants.comboWindow).clamp(0.0, 1.0);
    final hot = game.combo >= 5;
    final color = hot ? GameConstants.gold : GameConstants.accentAlt;

    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        borderColor: color.withValues(alpha: 0.55),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 2.4,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                  Icon(
                    hot ? Icons.local_fire_department_rounded : Icons.bolt_rounded,
                    size: 12,
                    color: color,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'x${game.combo}',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many rivals are still in the arena.
class RivalCounter extends StatelessWidget {
  final SnakeGame game;
  const RivalCounter({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.blur_circular_rounded, size: 15, color: GameConstants.danger),
          const SizedBox(width: 6),
          Text(
            '${game.aliveRivalCount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Boost meter. Turns amber when it is running low and red while locked out.
class BoostBar extends StatelessWidget {
  final SnakeGame game;
  const BoostBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final fraction = game.boostFraction;
    final boosting = game.isBoosting;
    final empty = fraction < GameConstants.boostMinToEngage;

    final Color color;
    if (empty) {
      color = GameConstants.danger;
    } else if (fraction < 0.4) {
      color = GameConstants.gold;
    } else {
      color = GameConstants.accentAlt;
    }

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderColor: boosting ? color.withValues(alpha: 0.6) : null,
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: 8, color: Colors.white.withValues(alpha: 0.08)),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 90),
                    widthFactor: fraction,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.65), color],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            empty ? 'RECHARGING' : (boosting ? 'BOOST' : 'HOLD TO BOOST'),
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icons for whatever power-ups are currently running, with countdown rings.
class ActiveEffectsStrip extends StatelessWidget {
  final SnakeGame game;
  const ActiveEffectsStrip({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (game.hasShield) {
      chips.add(_chip(PowerType.shield, null));
    }
    for (final e in game.activeEffects.values) {
      if (e.type == PowerType.shield) continue;
      chips.add(_chip(e.type, (e.remaining / PowerConfig.of(e.type).seconds).clamp(0.0, 1.0)));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in chips) ...[c, const SizedBox(width: 6)],
      ],
    );
  }

  Widget _chip(PowerType type, double? fraction) {
    final cfg = PowerConfig.of(type);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        border: Border.all(color: cfg.color.withValues(alpha: 0.7), width: 1.4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (fraction != null)
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 2.2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(cfg.color.withValues(alpha: 0.85)),
              ),
            ),
          Icon(cfg.icon, size: 17, color: cfg.color),
        ],
      ),
    );
  }
}
