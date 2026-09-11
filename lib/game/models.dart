import '../constants.dart';

enum Direction { up, down, left, right }

extension DirectionX on Direction {
  Direction get opposite => switch (this) {
        Direction.up => Direction.down,
        Direction.down => Direction.up,
        Direction.left => Direction.right,
        Direction.right => Direction.left,
      };

  int get dx => switch (this) {
        Direction.left => -1,
        Direction.right => 1,
        _ => 0,
      };

  int get dy => switch (this) {
        Direction.up => -1,
        Direction.down => 1,
        _ => 0,
      };
}

/// An integer grid coordinate. Immutable and cheap to hash so it can be used
/// as a map/set key in the collision and pathfinding passes.
class Point {
  final int x;
  final int y;

  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Point && other.x == x && other.y == y);

  @override
  int get hashCode => x * 31 + y;

  /// Index into a flattened `gridSize * gridSize` array.
  int get index => y * GameConstants.gridSize + x;

  Point move(Direction d) => Point(x + d.dx, y + d.dy);

  /// Moves one step and wraps around the arena edges (portal walls).
  Point moveWrapped(Direction d) {
    const n = GameConstants.gridSize;
    return Point((x + d.dx + n) % n, (y + d.dy + n) % n);
  }

  /// Manhattan distance that accounts for the arena wrapping around.
  int wrappedDistanceTo(Point other) {
    const n = GameConstants.gridSize;
    final dx = (x - other.x).abs();
    final dy = (y - other.y).abs();
    return (dx < n - dx ? dx : n - dx) + (dy < n - dy ? dy : n - dy);
  }

  @override
  String toString() => '($x, $y)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Food
// ─────────────────────────────────────────────────────────────────────────────

enum FoodKind {
  /// Standard pellet.
  normal,

  /// Rare, short-lived, worth a multiple of a normal pellet.
  golden,

  /// Dropped by a destroyed snake. Plentiful but worth less.
  corpse,
}

class Food {
  Point pos;
  final FoodKind kind;

  /// Seconds left before it vanishes. `null` means it never expires.
  double? ttl;

  /// Free-running phase so pellets do not all pulse in lockstep.
  final double phase;

  Food(this.pos, this.kind, {this.ttl, this.phase = 0});

  bool get isGolden => kind == FoodKind.golden;

  /// Score multiplier applied on top of the difficulty's base food points.
  double get valueMultiplier => switch (kind) {
        FoodKind.normal => 1.0,
        FoodKind.golden => GameConstants.goldenFoodMultiplier.toDouble(),
        FoodKind.corpse => 0.5,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Power-ups
// ─────────────────────────────────────────────────────────────────────────────

class PowerPickup {
  Point pos;
  final PowerType type;
  double ttl;
  final double phase;

  PowerPickup(this.pos, this.type, this.ttl, {this.phase = 0});
}

/// An effect currently running on the player.
class ActiveEffect {
  final PowerType type;
  double remaining;

  ActiveEffect(this.type, this.remaining);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Snakes
// ─────────────────────────────────────────────────────────────────────────────

/// Drives how a rival picks its target. Personalities make a lobby of rivals
/// feel like distinct opponents rather than one algorithm cloned N times.
enum AiPersonality {
  /// Beelines for the nearest pellet and mostly ignores everyone else.
  forager,

  /// Tries to cut the player off by aiming ahead of the player's head.
  hunter,

  /// Keeps its distance from bigger snakes and grabs safe food.
  coward,

  /// Targets whichever snake is shortest, including the player.
  bully,
}

class Snake {
  List<Point> body;
  Direction direction;
  bool isAlive;
  final bool isPlayer;
  final int id;

  /// Segments still owed from food already eaten.
  int pendingGrowth;

  /// Where the tail was before the current step, used to interpolate rendering.
  Point? prevTail;

  // ── AI-only state ────────────────────────────────────────────────────
  final AiPersonality personality;

  /// Colour slot in [GameConstants.rivalColors].
  final int colorSlot;

  /// Ticks this rival stays frozen (player used FREEZE).
  int frozenTicks;

  Snake({
    required this.body,
    required this.direction,
    required this.id,
    this.isAlive = true,
    this.isPlayer = false,
    this.pendingGrowth = 0,
    this.personality = AiPersonality.forager,
    this.colorSlot = 0,
    this.frozenTicks = 0,
  });

  Point get head => body.first;
  int get length => body.length;

  /// Pushes a new head in the movement direction. The tail is trimmed
  /// separately by [settle] so that food can be resolved in between.
  void advance() {
    prevTail = body.last;
    body.insert(0, head.moveWrapped(direction));
  }

  /// Drops the tail unless the snake still owes growth from a pellet.
  void settle() {
    if (pendingGrowth > 0) {
      pendingGrowth--;
    } else if (body.length > 1) {
      body.removeLast();
    }
  }

  bool occupies(Point p) => body.contains(p);

  /// True when the head has run into this snake's own body.
  bool get hitsSelf {
    final h = head;
    for (var i = 1; i < body.length; i++) {
      if (body[i] == h) return true;
    }
    return false;
  }
}
