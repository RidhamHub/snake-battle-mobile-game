import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../services/audio_service.dart';

/// Titled card used for each block on the home and customisation screens.
class SectionPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  const SectionPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 12, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool large;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AudioService().playSfx(GameConstants.sfxClick);
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: large ? 14 : 10),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.30)),
            boxShadow: filled
                ? [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 14)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: large ? 20 : 15, color: filled ? Colors.black : color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.black : color,
                  fontWeight: FontWeight.w900,
                  fontSize: large ? 13 : 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SmallToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const SmallToggle({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.05)
              : GameConstants.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.08)
                : GameConstants.danger.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white38 : GameConstants.danger,
        ),
      ),
    );
  }
}

class CoinBadge extends StatelessWidget {
  final int coins;
  final VoidCallback? onTap;

  const CoinBadge({super.key, required this.coins, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: GameConstants.gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GameConstants.gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on_rounded, color: GameConstants.gold, size: 16),
            const SizedBox(width: 6),
            Text(
              '$coins',
              style: const TextStyle(
                color: GameConstants.gold,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.add_circle_rounded,
                  color: GameConstants.gold.withValues(alpha: 0.7), size: 13),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rules and power-up reference, shown from the home screen.
void showHowToPlay(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF0D1424),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'HOW TO PLAY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: const [
                        _HelpRow(Icons.swipe_rounded, 'Steer',
                            'Swipe anywhere. A D-pad appears under your thumb.'),
                        _HelpRow(Icons.bolt_rounded, 'Boost',
                            'Hold to sprint. It drains the boost bar, so save it.'),
                        _HelpRow(Icons.restaurant_rounded, 'Eat',
                            'Pellets grow you. Gold ones are worth 5x but expire.'),
                        _HelpRow(Icons.local_fire_department_rounded, 'Combo',
                            'Eat again quickly to stack up to a x8 multiplier.'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: const [
                        _HelpRow(Icons.whatshot_rounded, 'Fight',
                            'Rivals die on your body. Head-on, the longer snake wins.'),
                        _HelpRow(Icons.dangerous_rounded, 'Avoid',
                            'Your own tail and the grey wall blocks are lethal.'),
                        _HelpRow(Icons.swap_horiz_rounded, 'Wrap',
                            'Edges are portals — slide off one side, appear on the other.'),
                        _HelpRow(Icons.emoji_events_rounded, 'Missions',
                            'Daily objectives pay coins for skins and eyes.'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'POWER-UPS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in PowerType.values) _PowerChip(type: type),
                ],
              ),
              const SizedBox(height: 18),
              ActionButton(
                label: 'GOT IT',
                icon: Icons.check_rounded,
                color: GameConstants.accentAlt,
                filled: true,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HelpRow(this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white70, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                Text(body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      height: 1.35,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerChip extends StatelessWidget {
  final PowerType type;
  const _PowerChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final cfg = PowerConfig.of(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cfg.icon, size: 14, color: cfg.color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(cfg.name,
                  style: TextStyle(
                      color: cfg.color, fontSize: 9.5, fontWeight: FontWeight.w900)),
              Text(cfg.blurb,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 8.5,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
