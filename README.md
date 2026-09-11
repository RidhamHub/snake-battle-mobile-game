# Snake Battle

Arena snake combat for Android and iOS, built with Flutter. You share a 30×30
wrap-around arena with up to seven rival snakes that actively hunt, forage and
try to cut you off. Eat, chain combos, grab power-ups, and make the rivals
crash into you.

## Playing

| Action | Control |
| --- | --- |
| Steer | Swipe anywhere — a floating D-pad appears under your thumb |
| Boost | Press and hold — drains the boost meter, then recharges |
| Pause | Top-right button, or send the app to the background |

**Rules**

- Pellets grow you. Golden pellets are worth 5× but expire in a few seconds.
- Eating again inside 2.6 s stacks a combo, up to **x8**.
- Rivals die when they hit your body. Head-on, the **longer snake wins**;
  equal lengths take each other out.
- Your own tail and the grey wall blocks are lethal.
- Arena edges are portals — slide off one side, reappear on the other.

**Power-ups**

| | Effect |
| --- | --- |
| 🔥 Frenzy | Double score for 9 s |
| 🛡 Shield | Absorbs one otherwise fatal hit |
| 🧲 Magnet | Drags nearby pellets toward you for 9 s |
| 👻 Phase | Pass through snakes and walls for 6 s |
| ❄️ Freeze | Rivals stop moving for 5 s |

**Difficulty**

| | Rivals | Tick | AI skill | Wall blocks |
| --- | --- | --- | --- | --- |
| Rookie | 3 | 175 ms | 45 % | 0 |
| Veteran | 5 | 145 ms | 78 % | 6 |
| Legend | 7 | 118 ms | 95 % | 12 |

Coins come from pellets, kills, daily missions and optional rewarded ads, and
buy the 17 skins and 10 eye styles in the customisation screen.

## Project layout

```
lib/
  constants.dart            tuning: difficulty, power-ups, skins, colours
  game/
    models.dart             Point, Direction, Snake, Food, PowerPickup
    snake_game.dart         simulation + persisted profile (ChangeNotifier)
    ai_brain.dart           rival decision making (flood-fill safety search)
    effects.dart            particles, floating text, shockwaves, screen shake
    missions.dart           daily objectives and per-run stats
  services/
    audio_service.dart      pooled SFX + looping music
    haptics_service.dart    vibration, user-toggleable
    ad_service.dart         AdMob banner / interstitial / rewarded
  ui/
    home_screen.dart        profile, missions, difficulty, records
    game_screen.dart        fixed-timestep loop and input
    customization_page.dart skin / eye / colour shop
    painters/               arena, snakes, eyes, previews
    widgets/                HUD, game-over sheet, shared panels
```

### How the loop works

`GameScreen` runs a `Ticker` and accumulates real time. The simulation only
ever advances in whole ticks of `tickIntervalMs`, so speed never depends on the
device's frame rate; the leftover fraction is handed to the painter as
`renderT` and used to interpolate each segment between its previous and current
cell. That is what makes the snakes glide instead of jump.

The rival AI rebuilds one shared occupancy grid per tick, then scores each
candidate direction on a capped flood fill (room to escape), distance to its
personality's target, and whether it would lose a head-on trade. `aiSkill`
decides how often it plays the best move rather than a random safe one.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

The game is playable without any of its optional services: ads, audio and
haptics all degrade to no-ops when the platform does not support them.

### Audio assets

Every sound in `assets/audio/` is synthesised — no third-party samples. The
generator is a standalone Python script; re-run it if you want to retune the
sounds or the music loop.

### Release build

Signing config lives in `android/key.properties` (not in version control) and
points at `android/app/upload-keystore.jks`. `android/app/google-services.json`
is also kept out of version control — download it from the Firebase console
before building.

```bash
flutter build appbundle --release
```

The bundle lands in `build/app/outputs/bundle/release/app-release.aab`.
Remember to bump `version:` in `pubspec.yaml` — Play rejects a build whose
version code it has already seen.
