import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../constants.dart';

/// Mapparaan's basemap: CARTO Voyager tiles with a warm, slightly sepia tint
/// (the same look as the AnoTara web app's `.leaflet-tile-pane` filter:
/// sepia 0.35, brightness 0.95).
///
/// Use it as a child of `FlutterMap` instead of a plain `TileLayer`.
class MapparaanTileLayer extends StatelessWidget {
  const MapparaanTileLayer({super.key});

  // sepia(0.35) blended into the identity matrix, then scaled by 0.95.
  static const List<double> _warmTint = [
    0.748, 0.256, 0.063, 0, 0, //
    0.116, 0.846, 0.056, 0, 0, //
    0.090, 0.178, 0.661, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_warmTint),
      child: TileLayer(
        urlTemplate: AppConstants.mapTileUrl,
        subdomains: AppConstants.mapTileSubdomains,
        userAgentPackageName: AppConstants.appPackageName,
        retinaMode: RetinaMode.isHighDensity(context),
        maxZoom: AppConstants.maxZoom,
        // Cancels tile requests that are no longer needed (faster on web).
        tileProvider: CancellableNetworkTileProvider(),
      ),
    );
  }
}