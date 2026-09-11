import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Sound effects and music.
///
/// SFX go through a small round-robin pool because a single [AudioPlayer]
/// cancels whatever it was playing when a new sound starts — with one player
/// a fast combo would swallow all but the last blip.
class AudioService extends ChangeNotifier {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  static const int _poolSize = 5;

  // Players are created inside [init], never at field-initialiser time: the
  // AudioPlayer constructor talks to a platform channel, which throws on any
  // host without the plugin (tests, desktop) before the app can guard it.
  final List<AudioPlayer> _pool = [];
  AudioPlayer? _music;
  int _next = 0;

  bool _sfxEnabled = true;
  bool _musicEnabled = true;
  bool _musicPlaying = false;
  bool _ready = false;

  /// Guards against the same sound firing many times in one frame.
  final Map<String, int> _lastPlayedMs = {};
  static const int _minGapMs = 45;

  bool get isEnabled => _sfxEnabled;
  bool get isMusicEnabled => _musicEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sfxEnabled = prefs.getBool(GameConstants.audioEnabledKey) ?? true;
    _musicEnabled = prefs.getBool(GameConstants.musicEnabledKey) ?? true;

    try {
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer();
        // Low latency mode keeps short blips snappy.
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }

      final music = AudioPlayer();
      await music.setReleaseMode(ReleaseMode.loop);
      await music.setVolume(0.35);
      _music = music;

      _ready = true;
    } catch (e) {
      // No audio backend here (tests, unsupported desktop). The game stays
      // fully playable, just silent.
      _ready = false;
      debugPrint('AudioService: audio unavailable ($e)');
    }
  }

  Future<void> toggleSfx() async {
    _sfxEnabled = !_sfxEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GameConstants.audioEnabledKey, _sfxEnabled);
    notifyListeners();
  }

  Future<void> toggleMusic() async {
    _musicEnabled = !_musicEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GameConstants.musicEnabledKey, _musicEnabled);
    if (_musicEnabled) {
      await startMusic();
    } else {
      await stopMusic();
    }
    notifyListeners();
  }

  void playSfx(String assetPath) {
    if (!_sfxEnabled || !_ready) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPlayedMs[assetPath] ?? 0;
    if (now - last < _minGapMs) return;
    _lastPlayedMs[assetPath] = now;

    if (_pool.isEmpty) return;
    final player = _pool[_next];
    _next = (_next + 1) % _pool.length;

    // Fire and forget: a failed sound must never interrupt the game loop.
    player.play(AssetSource(assetPath), volume: 0.85).catchError((Object e) {
      debugPrint('AudioService: failed to play $assetPath ($e)');
    });
  }

  Future<void> startMusic() async {
    final music = _music;
    if (!_musicEnabled || !_ready || _musicPlaying || music == null) return;
    _musicPlaying = true;
    try {
      await music.play(AssetSource(GameConstants.bgmLoop), volume: 0.3);
    } catch (e) {
      _musicPlaying = false;
      debugPrint('AudioService: music failed ($e)');
    }
  }

  Future<void> stopMusic() async {
    if (!_musicPlaying) return;
    _musicPlaying = false;
    try {
      await _music?.stop();
    } catch (_) {
      // Nothing meaningful to do if stopping fails.
    }
  }

  /// Ducks the music while the app is backgrounded or an ad is on screen.
  Future<void> pauseMusic() async {
    if (!_musicPlaying) return;
    try {
      await _music?.pause();
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> resumeMusic() async {
    if (!_musicEnabled || !_musicPlaying) return;
    try {
      await _music?.resume();
    } catch (_) {
      // Ignore.
    }
  }

  @override
  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
    _music?.dispose();
    super.dispose();
  }
}
