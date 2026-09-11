import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../services/ad_service.dart';

/// Renders the banner only once it has genuinely loaded.
///
/// When there is no ad — desktop, offline, no fill — this collapses to nothing
/// rather than leaving a "Loading Ad…" hole in the layout.
class AdBannerWidget extends StatelessWidget {
  const AdBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ads = context.watch<AdService>();
    final banner = ads.bannerAd;

    if (banner == null || !ads.isBannerLoaded) return const SizedBox.shrink();

    return SizedBox(
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
