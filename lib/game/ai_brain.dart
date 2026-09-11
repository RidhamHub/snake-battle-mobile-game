import 'dart:math';
import 'dart:typed_data';

import '../constants.dart';
import 'models.dart';

/// Cell classification used by the AI when it looks one step ahead.
class _Cell {
  static const int free = 0;
  static const int blocked = 1;

  /// A tail segment that will move out of the way this tick — safe to enter.
  static const int vacating = 2;
}

/// Decides where each rival snake steers.
///
/// The brain works on a flattened occupancy grid rebuilt once per tick and
/// shared by every rival, so the per-snake cost is only the candidate scoring.
/// Each candidate direction is scored on three things:
///
///  1. **Survival** — is the next cell walkable at all?
///  2. **Space** — a capped flood fill from the next cell, which is what stops
///     a snake from coiling itself into a pocket it cannot escape.
///  3. **Intent** — how much closer the move gets it to its personality target.
///
/// `skill` blends the best move against a random safe one, which is what makes
/// ROOKIE rivals beatable and LEGEND rivals genuinely dangerous.
class AiBrain {
  static const int _n = GameConstants.gridSize;
  static const int _cells = _n * _n;

  /// How far the flood fill will look before deciding a pocket is "roomy".
  static const int _floodCap = 110;

  final Random _random;

  /// Occupancy for the current tick. Rebuilt in [beginTick].
  final Uint8List _grid = Uint8List(_cells);

  /// Scratch buffers for the flood fill, reused to avoid per-call allocation.
  final Uint8List _visited = Uint8List(_cells);
  final Int32List _queue = Int32List(_cells);
  int _visitStamp = 0;

  /// Cells a rival head could reach next tick, keyed by the length of the
  /// snake that could move there. Used to avoid losing head-on trades.
  final Int32List _headThreat = Int32List(_cells);

  AiBrain(this._random);

  /// Rebuilds the shared world view. Call once per tick before [chooseDirection].
  void beginTick({
    required Snake player,
    required List<Snake> rivals,
    required Set<Point> obstacles,
  }) {
    _grid.fillRange(0, _cells, _Cell.free);
    _headThreat.fillRange(0, _cells, 0);

    for (final o in obstacles) {
      _grid[o.index] = _Cell.blocked;
    }

    void mark(Snake s) {
      if (!s.isAlive) return;
      for (var i = 0; i < s.body.length; i++) {
        // The final segment steps away this tick unless the snake is growing,
        // so treat it as passable rather than as a wall.
        final isVacatingTail = i == s.body.length - 1 && s.pendingGrowth == 0 && s.body.length > 1;
        final idx = s.body[i].index;
        if (isVacatingTail) {
          if (_grid[idx] == _Cell.free) _grid[idx] = _Cell.vacating;
        } else {
          _grid[idx] = _Cell.blocked;
        }
      }
    }

    mark(player);
    for (final r in rivals) {
      mark(r);
    }

    // Record where every other head could be next tick, tagged with its length,
    // so a rival can avoid trading heads with something bigger than itself.
    void threat(Snake s) {
      if (!s.isAlive) return;
      for (final d in Direction.values) {
        if (d == s.direction.opposite) continue;
        final p = s.head.moveWrapped(d);
        if (_headThreat[p.index] < s.length) _headThreat[p.index] = s.length;
      }
    }

    threat(player);
    for (final r in rivals) {
      threat(r);
    }
  }

  /// Picks the direction [ai] should travel this tick.
  Direction chooseDirection({
    required Snake ai,
    required Snake player,
    required List<Snake> rivals,
    required List<Food> food,
    required List<PowerPickup> powerUps,
    required double skill,
  }) {
    final target = _targetFor(ai, player, rivals, food, powerUps);

    final candidates = <Direction>[];
    for (final d in Direction.values) {
      if (d != ai.direction.opposite) candidates.add(d);
    }

    Direction? best;
    double bestScore = double.negativeInfinity;
    final safe = <Direction>[];

    for (final d in candidates) {
      final next = ai.head.moveWrapped(d);
      final cell = _grid[next.index];

      // A snake may step onto the square its own tail is leaving, but stepping
      // onto someone else's vacating tail is a coin flip we simply avoid.
      final isOwnTail = ai.body.isNotEmpty && next == ai.body.last;
      if (cell == _Cell.blocked) continue;
      if (cell == _Cell.vacating && !isOwnTail) continue;

      // Losing a head-on trade is fatal, so heavily discount those cells.
      final threatLen = _headThreat[next.index];
      final headOnPenalty = threatLen >= ai.length ? 900.0 : 0.0;

      final space = _reachableSpace(next, ai);
      if (space <= 2) continue; // dead end — never worth it

      safe.add(d);

      double score = 0;

      // Room to breathe dominates: a move into a pocket is almost always a loss.
      score += (space / _floodCap).clamp(0.0, 1.0) * 1000;

      // Then pull toward the personality's target.
      if (target != null) {
        final dist = next.wrappedDistanceTo(target);
        score += (1.0 - dist / _n) * 320;
      }

      // Gentle preference for holding a line; constant weaving looks twitchy.
      if (d == ai.direction) score += 25;

      score -= headOnPenalty;

      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }

    if (safe.isEmpty) {
      // Boxed in. Keep going and let the collision pass resolve it.
      return ai.direction;
    }

    // Skill decides how often the rival actually plays its best option.
    if (_random.nextDouble() > skill) {
      return safe[_random.nextInt(safe.length)];
    }
    return best ?? safe.first;
  }

  /// Where this rival wants to go, based on its personality.
  Point? _targetFor(
    Snake ai,
    Snake player,
    List<Snake> rivals,
    List<Food> food,
    List<PowerPickup> powerUps,
  ) {
    switch (ai.personality) {
      case AiPersonality.hunter:
        // Aim a few cells ahead of the player so the rival cuts the corner
        // instead of endlessly chasing the tail it can never catch.
        if (player.isAlive) {
          if (ai.length > player.length || ai.head.wrappedDistanceTo(player.head) < 8) {
            var lead = player.head;
            for (var i = 0; i < 3; i++) {
              lead = lead.moveWrapped(player.direction);
            }
            return lead;
          }
        }
        return _nearestFood(ai, food, powerUps);

      case AiPersonality.bully:
        Snake? weakest;
        for (final s in [player, ...rivals]) {
          if (!s.isAlive || s.id == ai.id) continue;
          if (s.length >= ai.length) continue;
          if (weakest == null || s.length < weakest.length) weakest = s;
        }
        if (weakest != null && ai.head.wrappedDistanceTo(weakest.head) < 12) {
          return weakest.head.moveWrapped(weakest.direction);
        }
        return _nearestFood(ai, food, powerUps);

      case AiPersonality.coward:
        // Run from anything bigger that is uncomfortably close.
        for (final s in [player, ...rivals]) {
          if (!s.isAlive || s.id == ai.id) continue;
          if (s.length <= ai.length) continue;
          if (ai.head.wrappedDistanceTo(s.head) > 6) continue;
          // Head for the mirror-image cell, i.e. straight away from the threat.
          return Point(
            (s.head.x + _n ~/ 2) % _n,
            (s.head.y + _n ~/ 2) % _n,
          );
        }
        return _nearestFood(ai, food, powerUps);

      case AiPersonality.forager:
        return _nearestFood(ai, food, powerUps);
    }
  }

  Point? _nearestFood(Snake ai, List<Food> food, List<PowerPickup> powerUps) {
    Point? best;
    var bestScore = double.infinity;

    for (final f in food) {
      // Golden pellets are worth a detour.
      final weight = f.isGolden ? 0.55 : 1.0;
      final d = ai.head.wrappedDistanceTo(f.pos) * weight;
      if (d < bestScore) {
        bestScore = d;
        best = f.pos;
      }
    }
    for (final p in powerUps) {
      final d = ai.head.wrappedDistanceTo(p.pos) * 0.8;
      if (d < bestScore) {
        bestScore = d;
        best = p.pos;
      }
    }
    return best;
  }

  /// Capped flood fill from [start], counting cells the snake could still
  /// reach. This is the single most important signal — it is what keeps a
  /// rival from sealing itself inside its own coil.
  int _reachableSpace(Point start, Snake ai) {
    _visitStamp++;
    if (_visitStamp > 250) {
      _visited.fillRange(0, _cells, 0);
      _visitStamp = 1;
    }
    final stamp = _visitStamp;
    final tailIdx = ai.body.isNotEmpty ? ai.body.last.index : -1;

    var head = 0;
    var tail = 0;
    _queue[tail++] = start.index;
    _visited[start.index] = stamp;

    var count = 0;
    while (head < tail && count < _floodCap) {
      final idx = _queue[head++];
      count++;

      final x = idx % _n;
      final y = idx ~/ _n;

      for (final d in Direction.values) {
        final nx = (x + d.dx + _n) % _n;
        final ny = (y + d.dy + _n) % _n;
        final nIdx = ny * _n + nx;

        if (_visited[nIdx] == stamp) continue;

        final cell = _grid[nIdx];
        final passable = cell == _Cell.free || cell == _Cell.vacating || nIdx == tailIdx;
        if (!passable) continue;

        _visited[nIdx] = stamp;
        if (tail < _cells) _queue[tail++] = nIdx;
      }
    }
    return count;
  }
}
