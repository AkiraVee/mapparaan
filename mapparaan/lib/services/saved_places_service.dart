import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPlace {
  final String id;
  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;

  const SavedPlace({
    this.id = '',
    required this.name,
    required this.subtitle,
    this.latitude = 0,
    this.longitude = 0,
  });

  LatLng get coordinates => LatLng(latitude, longitude);

  static String _escapeField(String value) => value.replaceAll('::', '\u0000');

  static String _unescapeField(String value) => value.replaceAll('\u0000', '::');

  factory SavedPlace.fromLegacyString(String raw) {
    final parts = raw.split('::');
    if (parts.length >= 5) {
      final id = parts.first;
      final lastLatitude = parts[parts.length - 2];
      final lastLongitude = parts.last;
      final latitude = double.tryParse(lastLatitude) ?? 0;
      final longitude = double.tryParse(lastLongitude) ?? 0;

      if (parts.length == 5) {
        return SavedPlace(
          id: id,
          name: _unescapeField(parts[1]),
          subtitle: _unescapeField(parts[2]),
          latitude: latitude,
          longitude: longitude,
        );
      }

      final name = _unescapeField(parts.sublist(1, parts.length - 3).join('::'));
      final subtitle = _unescapeField(parts[parts.length - 3]);
      return SavedPlace(
        id: id,
        name: name,
        subtitle: subtitle,
        latitude: latitude,
        longitude: longitude,
      );
    }
    throw FormatException('Invalid saved place value: $raw');
  }

  String serialize() =>
      '$id::${_escapeField(name)}::${_escapeField(subtitle)}::$latitude::$longitude';
}

class SavedPlacesService {
  static const String _key = 'saved_places';
  static final List<SavedPlace> _places = <SavedPlace>[];

  static List<SavedPlace> get places => List.unmodifiable(_places);

  static Future<List<SavedPlace>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final loaded = raw.map(SavedPlace.fromLegacyString).toList();
    _places
      ..clear()
      ..addAll(loaded);
    return List.unmodifiable(loaded);
  }

  static bool contains(String name) =>
      _places.any((place) => place.name.toLowerCase() == name.toLowerCase());

  static Future<bool> save(SavedPlace place) async {
    final all = await load();
    final index = all.indexWhere(
      (current) => current.id == place.id ||
          current.name.toLowerCase() == place.name.toLowerCase(),
    );
    final updated = [...all];
    if (index >= 0) {
      updated[index] = place;
    } else {
      updated.add(place);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      updated.map((item) => item.serialize()).toList(),
    );
    _places
      ..clear()
      ..addAll(updated);
    return true;
  }

  static Future<bool> toggle(SavedPlace place) async {
    final all = await load();
    final index = all.indexWhere(
      (current) => current.id == place.id ||
          current.name.toLowerCase() == place.name.toLowerCase(),
    );
    final updated = [...all];
    if (index >= 0) {
      updated.removeAt(index);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        updated.map((item) => item.serialize()).toList(),
      );
      _places
        ..clear()
        ..addAll(updated);
      return false;
    }
    updated.add(place);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      updated.map((item) => item.serialize()).toList(),
    );
    _places
      ..clear()
      ..addAll(updated);
    return true;
  }

  static Future<void> removeByName(String name) async {
    final all = await load();
    final filtered = all
        .where((place) => place.name.toLowerCase() != name.toLowerCase())
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      filtered.map((item) => item.serialize()).toList(),
    );
    _places
      ..clear()
      ..addAll(filtered);
  }
}
