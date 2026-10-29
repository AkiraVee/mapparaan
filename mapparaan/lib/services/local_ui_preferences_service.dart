import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ColorVisionFilter {
  none('Off', 'No screen color adjustment', <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  redGreen(
    'Red-green contrast',
    'Adds a blue cue to help distinguish red and green',
    <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0.2, -0.2, 1, 0, 0, 0, 0, 0, 1, 0],
  ),
  blueYellow(
    'Blue-yellow contrast',
    'Adds a red-green cue to help distinguish blue and yellow',
    <double>[
      1.15,
      0,
      -0.15,
      0,
      0,
      0,
      1.15,
      -0.15,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
  ),
  protanopia(
    'Protanopia',
    'Stronger red-weakness adjustment; adds a blue cue to red',
    <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0.45, 0, 1, 0, 0, 0, 0, 0, 1, 0],
  ),
  deuteranopia(
    'Deuteranopia',
    'Stronger green-weakness adjustment; adds a blue cue to green',
    <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0.45, 1, 0, 0, 0, 0, 0, 1, 0],
  ),
  tritanopia(
    'Tritanopia',
    'Stronger blue-weakness adjustment; adds a red cue to blue',
    <double>[1, 0, 0.45, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
  ),
  achromatopsia(
    'Achromatopsia / Monochromacy',
    'Grayscale view; color distinctions are not restored',
    <double>[
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
  );

  const ColorVisionFilter(this.label, this.description, this.matrix);

  final String label;
  final String description;
  final List<double> matrix;
}

class LocalUiPreferences {
  final bool seniorMode;
  final bool simpleWords;
  final bool dataSaver;
  final bool accessibleOnly;
  final bool avoidStairs;
  final bool avoidFloods;
  final double? walkingLimitKm;
  final String language;
  final ColorVisionFilter colorVisionFilter;

  const LocalUiPreferences({
    this.seniorMode = false,
    this.simpleWords = false,
    this.dataSaver = false,
    this.accessibleOnly = false,
    this.avoidStairs = false,
    this.avoidFloods = false,
    this.walkingLimitKm,
    this.language = 'English',
    this.colorVisionFilter = ColorVisionFilter.none,
  });

  LocalUiPreferences copyWith({
    bool? seniorMode,
    bool? simpleWords,
    bool? dataSaver,
    bool? accessibleOnly,
    bool? avoidStairs,
    bool? avoidFloods,
    Object? walkingLimitKm = _unchanged,
    String? language,
    ColorVisionFilter? colorVisionFilter,
  }) {
    return LocalUiPreferences(
      seniorMode: seniorMode ?? this.seniorMode,
      simpleWords: simpleWords ?? this.simpleWords,
      dataSaver: dataSaver ?? this.dataSaver,
      accessibleOnly: accessibleOnly ?? this.accessibleOnly,
      avoidStairs: avoidStairs ?? this.avoidStairs,
      avoidFloods: avoidFloods ?? this.avoidFloods,
      walkingLimitKm: identical(walkingLimitKm, _unchanged)
          ? this.walkingLimitKm
          : walkingLimitKm as double?,
      language: language ?? this.language,
      colorVisionFilter: colorVisionFilter ?? this.colorVisionFilter,
    );
  }

  Map<String, dynamic> toJson() => {
    'senior_mode': seniorMode,
    'simple_words': simpleWords,
    'data_saver': dataSaver,
    'accessible_only': accessibleOnly,
    'avoid_stairs': avoidStairs,
    'avoid_floods': avoidFloods,
    'walking_limit_km': walkingLimitKm,
    'language': language,
    'color_vision_filter': colorVisionFilter.name,
  };

  static const _unchanged = Object();
}

class LocalUiPreferencesService {
  LocalUiPreferencesService._();

  static const _prefix = 'mapparaan.local_ui.';
  static final ValueNotifier<LocalUiPreferences> current = ValueNotifier(
    const LocalUiPreferences(),
  );

  static Future<LocalUiPreferences> load() async {
    final store = await SharedPreferences.getInstance();
    final value = LocalUiPreferences(
      seniorMode: store.getBool('${_prefix}senior_mode') ?? false,
      simpleWords: store.getBool('${_prefix}simple_words') ?? false,
      dataSaver: store.getBool('${_prefix}data_saver') ?? false,
      accessibleOnly: store.getBool('${_prefix}accessible_only') ?? false,
      avoidStairs: store.getBool('${_prefix}avoid_stairs') ?? false,
      avoidFloods: store.getBool('${_prefix}avoid_floods') ?? false,
      walkingLimitKm: store.getDouble('${_prefix}walking_limit_km'),
      language: store.getString('${_prefix}language') ?? 'English',
      colorVisionFilter: ColorVisionFilter.values.firstWhere(
        (filter) =>
            filter.name == store.getString('${_prefix}color_vision_filter'),
        orElse: () => ColorVisionFilter.none,
      ),
    );
    current.value = value;
    return value;
  }

  static Future<void> save(LocalUiPreferences value) async {
    current.value = value;
    final store = await SharedPreferences.getInstance();
    await store.setBool('${_prefix}senior_mode', value.seniorMode);
    await store.setBool('${_prefix}simple_words', value.simpleWords);
    await store.setBool('${_prefix}data_saver', value.dataSaver);
    await store.setBool('${_prefix}accessible_only', value.accessibleOnly);
    await store.setBool('${_prefix}avoid_stairs', value.avoidStairs);
    await store.setBool('${_prefix}avoid_floods', value.avoidFloods);
    if (value.walkingLimitKm == null) {
      await store.remove('${_prefix}walking_limit_km');
    } else {
      await store.setDouble(
        '${_prefix}walking_limit_km',
        value.walkingLimitKm!,
      );
    }
    await store.setString('${_prefix}language', value.language);
    await store.setString(
      '${_prefix}color_vision_filter',
      value.colorVisionFilter.name,
    );
  }
}
