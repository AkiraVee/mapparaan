import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../constants.dart';

/// Color treatments for the basemap. Change [MapparaanTileLayer.tint]
/// (or its default below) to switch the map's color.
///
/// These are drawn as a cheap translucent overlay on top of the tiles. (An
/// earlier version used a per-pixel ColorFilter, which re-processed the whole
/// map every frame and made panning/zooming slow.)
enum MapTint {
  /// The tiles exactly as the provider serves them.
  none(null),

  /// Warm sepia wash.
  warm(Color(0x26C8A064)),

  /// Soft teal wash matching Mapparaan's brand green (0xFF00695C).
  teal(Color(0x2E00897B)),

  /// White wash that fades the map so pins and routes stand out.
  faded(Color(0x40FFFFFF));

  final Color? overlay;
  const MapTint(this.overlay);
}

/// Mapparaan's basemap. Uses CARTO Voyager tiles when a CARTO API key is set,
/// otherwise OpenStreetMap standard tiles (see `AppConstants.mapTileUrl`),
/// with an optional color tint on top.
///
/// Use it as a child of `FlutterMap` instead of a plain `TileLayer`.
class MapparaanTileLayer extends StatelessWidget {
  final MapTint tint;

  const MapparaanTileLayer({super.key, this.tint = MapTint.teal});

  @override
  Widget build(BuildContext context) {
    final layer = TileLayer(
      urlTemplate: AppConstants.mapTileUrl,
      userAgentPackageName: AppConstants.appPackageName,
      maxZoom: AppConstants.maxZoom,
      // Cancels tile requests that are no longer needed (faster on web).
      tileProvider: CancellableNetworkTileProvider(),
      // Show tiles immediately instead of fading them in.
      tileDisplay: const TileDisplay.instantaneous(),
      // Load extra tiles around the screen and keep them longer, so panning
      // shows fewer blank patches.
      panBuffer: 2,
      keepBuffer: 4,
    );

    final overlay = tint.overlay;
    if (overlay == null) return layer;

    return Stack(
      fit: StackFit.expand,
      children: [
        layer,
        IgnorePointer(child: ColoredBox(color: overlay)),
      ],
    );
  }
}