import 'package:latlong2/latlong.dart';

enum RoutePreference { fastest, cheapest, fewestTransfers }

class RouteOption {
  final String title;
  final String summary;
  final String modeLabel;
  final int etaMinutes;
  final int fare;
  final int transfers;
  final RoutePreference preference;

  const RouteOption({
    required this.title,
    required this.summary,
    required this.modeLabel,
    required this.etaMinutes,
    required this.fare,
    required this.transfers,
    required this.preference,
  });
}

class RoutePlannerService {
  const RoutePlannerService._();

  static List<RouteOption> generateRouteOptions({
    required LatLng destination,
    required LatLng? userLocation,
    RoutePreference preference = RoutePreference.fastest,
  }) {
    final origin = userLocation ?? const LatLng(14.5943, 120.9721);
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      origin,
      destination,
    );

    final options = <RouteOption>[
      RouteOption(
        title: 'Fastest route',
        summary: 'Direct jeepney ride with a brief walk',
        modeLabel: 'Jeep + walk',
        etaMinutes: (distanceKm * 7.2).round() + 12,
        fare: 30,
        transfers: 1,
        preference: preference,
      ),
      RouteOption(
        title: 'Cheapest route',
        summary: 'Budget-friendly with one transfer',
        modeLabel: 'Jeep + train',
        etaMinutes: (distanceKm * 9.5).round() + 18,
        fare: 18,
        transfers: 2,
        preference: preference,
      ),
      RouteOption(
        title: 'Fewest transfers',
        summary: 'Comfortable route with the least switching',
        modeLabel: 'UV express',
        etaMinutes: (distanceKm * 8.4).round() + 16,
        fare: 40,
        transfers: 0,
        preference: preference,
      ),
    ];

    switch (preference) {
      case RoutePreference.fastest:
        options.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
        break;
      case RoutePreference.cheapest:
        options.sort((a, b) => a.fare.compareTo(b.fare));
        break;
      case RoutePreference.fewestTransfers:
        options.sort((a, b) => a.transfers.compareTo(b.transfers));
        break;
    }

    return options
        .map(
          (option) => RouteOption(
            title: option.title,
            summary: option.summary,
            modeLabel: option.modeLabel,
            etaMinutes: option.etaMinutes,
            fare: option.fare,
            transfers: option.transfers,
            preference: preference,
          ),
        )
        .toList();
  }
}
