import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Owns every AdMob surface.
///
/// Ads are strictly optional here: every entry point degrades to a no-op when
/// the SDK is unavailable (desktop, no network, unsupported platform), so the
/// game never blocks on an ad that will not arrive.
class AdService extends ChangeNotifier {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  bool _adsRemoved = false;
  bool _available = false;
  bool isBannerLoaded = false;
  bool isInitializing = false;
  String? lastErrorMessage;

  int _bannerRetries = 0;
  Timer? _bannerRetryTimer;

  int _rewardedAdsCount = 0;
  static const int maxRewardedAdsPerDay = 2;

  /// True once the SDK reported success. Ad widgets stay hidden until then.
  bool get isAvailable => _available && !_adsRemoved;

  bool get hasInterstitial => _interstitialAd != null;
  bool get hasRewarded => _rewardedAd != null && !isRewardedLimitReached;
  bool get isRewardedLimitReached => _rewardedAdsCount >= maxRewardedAdsPerDay;
  int get rewardedAdsCount => _rewardedAdsCount;
  BannerAd? get bannerAd => isAvailable ? _bannerAd : null;

  /// Ads are only supported on mobile; everywhere else this is inert.
  bool get _platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (isInitializing || !_platformSupported) return;
    isInitializing = true;

    try {
      await MobileAds.instance.initialize();
      _available = true;
      await _loadRewardedLimitData();
      _loadAllAds();
    } catch (e) {
      _available = false;
      lastErrorMessage = 'Ads unavailable';
      debugPrint('AdService: initialization failed ($e)');
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _loadRewardedLimitData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T').first;
      final savedDate = prefs.getString('rewarded_ad_date') ?? '';

      if (savedDate != today) {
        _rewardedAdsCount = 0;
        await prefs.setString('rewarded_ad_date', today);
        await prefs.setInt('rewarded_ad_count', 0);
      } else {
        _rewardedAdsCount = prefs.getInt('rewarded_ad_count') ?? 0;
      }
    } catch (e) {
      debugPrint('AdService: could not read rewarded limit ($e)');
    }
  }

  Future<void> _incrementRewardedCount() async {
    _rewardedAdsCount++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('rewarded_ad_count', _rewardedAdsCount);
    } catch (e) {
      debugPrint('AdService: could not persist rewarded count ($e)');
    }
  }

  void setAdsRemoved(bool removed) {
    _adsRemoved = removed;
    if (removed) {
      _bannerRetryTimer?.cancel();
      _bannerAd?.dispose();
      _bannerAd = null;
      isBannerLoaded = false;
    }
    notifyListeners();
  }

  void retryAds() {
    lastErrorMessage = null;
    _bannerRetries = 0;
    _loadAllAds();
    notifyListeners();
  }

  void _loadAllAds() {
    if (!isAvailable) return;
    loadBanner();
    loadInterstitial();
    loadRewarded();
  }

  // ── Banner ─────────────────────────────────────────────────────────

  void loadBanner() {
    if (!isAvailable) return;

    _bannerRetryTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    isBannerLoaded = false;

    final ad = BannerAd(
      adUnitId: GameConstants.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          isBannerLoaded = true;
          _bannerRetries = 0;
          lastErrorMessage = null;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          isBannerLoaded = false;
          lastErrorMessage = 'Ads unavailable';
          ad.dispose();
          _bannerAd = null;
          notifyListeners();
          debugPrint('AdService: banner failed (${error.code}) ${error.message}');

          // "No fill" (code 3) is not worth hammering; everything else gets a
          // few backed-off retries.
          if (error.code != 3 && _bannerRetries < 4) {
            _bannerRetries++;
            _bannerRetryTimer = Timer(
              Duration(seconds: 5 * _bannerRetries),
              loadBanner,
            );
          }
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  // ── Interstitial ───────────────────────────────────────────────────

  void loadInterstitial() {
    if (!isAvailable) return;
    InterstitialAd.load(
      adUnitId: GameConstants.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          debugPrint('AdService: interstitial failed (${error.code})');
        },
      ),
    );
  }

  void showInterstitial({VoidCallback? onDismissed}) {
    final ad = _interstitialAd;
    if (!isAvailable || ad == null) {
      onDismissed?.call();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadInterstitial();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        loadInterstitial();
        onDismissed?.call();
      },
    );

    _interstitialAd = null;
    ad.show();
    notifyListeners();
  }

  // ── Rewarded ───────────────────────────────────────────────────────

  void loadRewarded() {
    if (!isAvailable || isRewardedLimitReached) return;
    RewardedAd.load(
      adUnitId: GameConstants.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          debugPrint('AdService: rewarded failed (${error.code})');
        },
      ),
    );
  }

  /// [onReward] fires only if the user actually earned the reward.
  /// [onDismissed] always fires once the ad is gone, including failures, so
  /// callers can reliably resume music or unblock the UI.
  void showRewarded({required VoidCallback onReward, VoidCallback? onDismissed}) {
    final ad = _rewardedAd;
    if (!isAvailable || ad == null || isRewardedLimitReached) {
      onDismissed?.call();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewarded();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        loadRewarded();
        onDismissed?.call();
      },
    );

    _rewardedAd = null;
    notifyListeners();

    ad.show(onUserEarnedReward: (_, _) {
      unawaited(_incrementRewardedCount());
      onReward();
    });
  }

  @override
  void dispose() {
    _bannerRetryTimer?.cancel();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }
}
