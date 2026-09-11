import 'dart:math';
import 'dart:ui';

/// A single short-lived spark. Positions are in *grid* units so the painter can
/// scale them with the arena instead of caring about pixels.
class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final double size;
  final Color color;
  final bool glow;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.maxLife,
    required this.size,
    required this.color,
    this.glow = false,
  }) : life = maxLife;

  double get t => (life / maxLife).clamp(0.0, 1.0);
  bool get isDead => life <= 0;

  void update(double dt) {
    life -= dt;
    x += vx * dt;
    y += vy * dt;
    // Mild drag so bursts settle rather than flying off forever.
    vx *= 1 - 3.2 * dt;
    vy *= 1 - 3.2 * dt;
  }
}

/// A score / combo callout that drifts upward and fades.
class FloatingText {
  double x;
  double y;
  final String text;
  final Color color;
  final double fontSize;
  double life;
  final double maxLife;

  FloatingText({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.fontSize = 13,
    this.maxLife = 1.0,
  }) : life = maxLife;

  double get t => (life / maxLife).clamp(0.0, 1.0);
  bool get isDead => life <= 0;

  void update(double dt) {
    life -= dt;
    y -= dt * 2.2;
  }
}

/// Expanding ring drawn when something dramatic happens (a kill, a death).
class Shockwave {
  final double x;
  final double y;
  final Color color;
  final double maxRadius;
  double life;
  final double maxLife;

  Shockwave({
    required this.x,
    required this.y,
    required this.color,
    this.maxRadius = 6,
    this.maxLife = 0.5,
  }) : life = maxLife;

  double get progress => 1 - (life / maxLife).clamp(0.0, 1.0);
  bool get isDead => life <= 0;

  void update(double dt) => life -= dt;
}

/// Owns every transient visual. Kept deliberately separate from the game rules
/// so the simulation stays testable and the effects can run at display rate.
class EffectsSystem {
  final List<Particle> particles = [];
  final List<FloatingText> texts = [];
  final List<Shockwave> waves = [];

  final Random _random = Random();

  /// Current screen-shake offset in grid units, consumed by the painter.
  double shakeX = 0;
  double shakeY = 0;
  double _shakeAmount = 0;

  /// Full-screen colour flash, e.g. red on death or gold on a big combo.
  Color? flashColor;
  double _flashLife = 0;
  double _flashMax = 0.35;

  double get flashOpacity => _flashMax <= 0 ? 0 : (_flashLife / _flashMax).clamp(0.0, 1.0);

  bool get isEmpty =>
      particles.isEmpty && texts.isEmpty && waves.isEmpty && _shakeAmount <= 0 && _flashLife <= 0;

  void clear() {
    particles.clear();
    texts.clear();
    waves.clear();
    _shakeAmount = 0;
    shakeX = 0;
    shakeY = 0;
    _flashLife = 0;
    flashColor = null;
  }

  void update(double dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      particles[i].update(dt);
      if (particles[i].isDead) particles.removeAt(i);
    }
    for (var i = texts.length - 1; i >= 0; i--) {
      texts[i].update(dt);
      if (texts[i].isDead) texts.removeAt(i);
    }
    for (var i = waves.length - 1; i >= 0; i--) {
      waves[i].update(dt);
      if (waves[i].isDead) waves.removeAt(i);
    }

    if (_shakeAmount > 0) {
      _shakeAmount = max(0, _shakeAmount - dt * 4.5);
      shakeX = (_random.nextDouble() * 2 - 1) * _shakeAmount;
      shakeY = (_random.nextDouble() * 2 - 1) * _shakeAmount;
    } else {
      shakeX = 0;
      shakeY = 0;
    }

    if (_flashLife > 0) {
      _flashLife = max(0, _flashLife - dt);
      if (_flashLife == 0) flashColor = null;
    }
  }

  void shake(double amount) {
    _shakeAmount = max(_shakeAmount, amount);
  }

  void flash(Color color, {double duration = 0.35}) {
    flashColor = color;
    _flashMax = duration;
    _flashLife = duration;
  }

  // ── Emitters ─────────────────────────────────────────────────────────

  /// Radial spray, used when a pellet is eaten.
  void burst(
    double x,
    double y,
    Color color, {
    int count = 10,
    double speed = 4.5,
    double life = 0.45,
    double size = 0.18,
    bool glow = false,
  }) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * pi * 2;
      final v = speed * (0.45 + _random.nextDouble() * 0.75);
      particles.add(Particle(
        x: x,
        y: y,
        vx: cos(angle) * v,
        vy: sin(angle) * v,
        maxLife: life * (0.6 + _random.nextDouble() * 0.7),
        size: size * (0.6 + _random.nextDouble() * 0.8),
        color: color,
        glow: glow,
      ));
    }
  }

  /// Scatters debris along a destroyed snake's body.
  void explodeAlong(List<Offset> cells, Color color) {
    for (final c in cells) {
      burst(c.dx, c.dy, color, count: 3, speed: 3.0, life: 0.55, size: 0.16);
    }
  }

  /// Faint trail dropped behind the head while boosting.
  void boostTrail(double x, double y, Color color) {
    particles.add(Particle(
      x: x + (_random.nextDouble() - 0.5) * 0.3,
      y: y + (_random.nextDouble() - 0.5) * 0.3,
      vx: (_random.nextDouble() - 0.5) * 0.8,
      vy: (_random.nextDouble() - 0.5) * 0.8,
      maxLife: 0.32,
      size: 0.2,
      color: color,
      glow: true,
    ));
  }

  void popup(double x, double y, String text, Color color, {double fontSize = 13}) {
    texts.add(FloatingText(x: x, y: y, text: text, color: color, fontSize: fontSize));
  }

  void ring(double x, double y, Color color, {double radius = 6, double duration = 0.5}) {
    waves.add(Shockwave(x: x, y: y, color: color, maxRadius: radius, maxLife: duration));
  }
}
