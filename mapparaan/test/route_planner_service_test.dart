import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/route_planner_service.dart';

void main() {
  test('fastest route preference ranks the shortest ETA first', () {
  final route = RoutePlannerService.generateRouteOptions(
    destination: const LatLng(14.5995, 120.9842),
    userLocation: const LatLng(14.5943, 120.9721),
    preference: RoutePreference.fastest,
  );

  expect(route.first.etaMinutes, lessThanOrEqualTo(route[1].etaMinutes));
  expect(route.first.preference, RoutePreference.fastest);
});

test('cheapest route preference ranks the lowest fare first', () {
  final route = RoutePlannerService.generateRouteOptions(
    destination: const LatLng(14.5995, 120.9842),
    userLocation: const LatLng(14.5943, 120.9721),
    preference: RoutePreference.cheapest,
  );

  expect(route.first.fare, lessThanOrEqualTo(route[1].fare));
  expect(route.first.preference, RoutePreference.cheapest);
});

test('fewest transfers preference ranks the lowest transfer count first', () {
  final route = RoutePlannerService.generateRouteOptions(
    destination: const LatLng(14.5995, 120.9842),
    userLocation: const LatLng(14.5943, 120.9721),
    preference: RoutePreference.fewestTransfers,
  );

  expect(route.first.transfers, lessThanOrEqualTo(route[1].transfers));
  expect(route.first.preference, RoutePreference.fewestTransfers);
});
}
