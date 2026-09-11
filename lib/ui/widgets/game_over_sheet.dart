import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../game/missions.dart';
import '../../game/snake_game.dart';
import '../../services/ad_service.dart';
import '../../services/audio_service.dart';
import 'ad_banner.dart';

/// End-of-run summary: what you scored, how you died, what it earned you, and
/// any daily missions the run just completed.
class GameOverSheet extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onExit;
  final VoidCallback onRevive;

  const GameOverSheet({
    super.key,
    required this.onRetry,
    required this.onExit,
    required this.onRevive,
  });

  @override
  Widget build(BuildContext context) {
    final game = context.watch<SnakeGame>();
    final ads = context.watch<AdService>();

    final isRecord = game.score >= game.currentDifficultyHighScore && game.score > 0;
    final claimable = game.claimableMissions;
    // Only offer revive where a rewarded ad can actually be served. On hosts
    // without ads at all there is nothing to wait for, so the row is dropped
    // rather than left sitting there permanently disabled.
    final reviveOffered = ads.isAvailable && !game.hasUsedRevive;
    final canRevive = reviveOffered && ads.hasRewarded;

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.88),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1424),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: (isRecord ? GameConstants.gold : GameConstants.danger)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(game, isRecord),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _breakdown(game)),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 5,
                            child: _actions(context, canRevive, reviveOffered),
                          ),
                        ],
                      ),
                      if (claimable.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _missions(context, game, claimable),
                      ],
                      const SizedBox(height: 12),
                      const AdBannerWidget(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(SnakeGame game, bool isRecord) {
    return Column(
      children: [
        Text(
          isRecord ? '🏆 NEW RECORD' : '☠️ MISSION FAILED',
          style: TextStyle(
            color: isRecord ? GameConstants.gold : GameConstants.danger,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
        if (game.lastDeathCause != null) ...[
          const SizedBox(height: 4),
          Text(
            game.lastDeathCause!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _breakdown(SnakeGame game) {
    final run = game.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text('SCORE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 9,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.bold,
                  )),
              Text(
                '${game.score}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              Text(
                'BEST ${game.currentDifficultyHighScore}  ·  ${game.difficultyEnum.label}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.28),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _tile(Icons.restaurant_rounded, '${run.foodEaten}', 'FOOD', const Color(0xFFFFB733))),
            const SizedBox(width: 6),
            Expanded(child: _tile(Icons.bolt_rounded, 'x${run.bestCombo}', 'COMBO', GameConstants.accentAlt)),
            const SizedBox(width: 6),
            Expanded(child: _tile(Icons.whatshot_rounded, '${run.kills}', 'KILLS', GameConstants.danger)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _tile(Icons.timer_outlined, '${run.survivedSeconds.round()}s', 'TIME', Colors.white70)),
            const SizedBox(width: 6),
            Expanded(child: _tile(Icons.straighten_rounded, '${run.maxLength}', 'LENGTH', const Color(0xFF9C88FF))),
            const SizedBox(width: 6),
            Expanded(child: _tile(Icons.monetization_on_rounded, '+${run.coins}', 'COINS', GameConstants.gold)),
          ],
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
          ),
          Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.28),
                fontSize: 7.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              )),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, bool canRevive, bool reviveOffered) {
    return Column(
      children: [
        _button(
          icon: Icons.refresh_rounded,
          label: 'PLAY AGAIN',
          color: GameConstants.accent,
          filled: true,
          onTap: onRetry,
        ),
        const SizedBox(height: 8),
        if (canRevive) ...[
          _button(
            icon: Icons.favorite_rounded,
            label: 'REVIVE (AD)',
            color: GameConstants.gold,
            onTap: onRevive,
          ),
          const SizedBox(height: 8),
        ] else if (reviveOffered) ...[
          _button(
            icon: Icons.hourglass_empty_rounded,
            label: 'REVIVE LOADING',
            color: Colors.white24,
            onTap: () {},
          ),
          const SizedBox(height: 8),
        ],
        _button(
          icon: Icons.home_rounded,
          label: 'HOME',
          color: Colors.white54,
          onTap: onExit,
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AudioService().playSfx(GameConstants.sfxClick);
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: filled ? Colors.black : color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.black : color,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missions(BuildContext context, SnakeGame game, List<Mission> claimable) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameConstants.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GameConstants.gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 15, color: GameConstants.gold),
              const SizedBox(width: 8),
              Text(
                'MISSION COMPLETE',
                style: TextStyle(
                  color: GameConstants.gold.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in claimable)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.title,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ClaimButton(mission: m, game: game),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  final Mission mission;
  final SnakeGame game;

  const _ClaimButton({required this.mission, required this.game});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (game.claimMission(mission)) {
            AudioService().playSfx(GameConstants.sfxGolden);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: GameConstants.gold,
                  duration: const Duration(seconds: 2),
                  content: Text(
                    '+${mission.reward} coins claimed',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: GameConstants.gold,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '+${mission.reward}',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
