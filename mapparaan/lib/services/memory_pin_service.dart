import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class MemoryPin {
  final String id;
  final String placeName;
  final String address;
  final LatLng coordinates;
  final String imagePath; // Temporarily holds a mock string, later a real file path

  MemoryPin({
    required this.id,
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.imagePath,
  });
}

class MemoryPinService {
  // Temporary in-memory storage. 
  // ValueNotifier allows the HomeScreen map to instantly update when a pin is added.
  static final ValueNotifier<List<MemoryPin>> pins = ValueNotifier([]);

  static void addPin(MemoryPin pin) {
    final current = List<MemoryPin>.from(pins.value);
    current.add(pin);
    pins.value = current;
  }
}