import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AppThemeMode { system, light, dark }

enum ColorPalette {
  pasigDusk(
    'Pasig Dusk',
    Color(0xFF00796B),
    Color(0xFFB2DFDB),
    Color(0xFF00201B),
  ),
  intramuros(
    'Intramuros',
    Color(0xFF8D4E00),
    Color(0xFFFFDDB8),
    Color(0xFF2D1600),
  ),
  manilaBay(
    'Manila Bay',
    Color(0xFF0061A4),
    Color(0xFFD1E4FF),
    Color(0xFF001D36),
  ),
  binondo('Binondo', Color(0xFFBA1A1A), Color(0xFFFFDAD6), Color(0xFF410002));

  const ColorPalette(
    this.label,
    this.primary,
    this.container,
    this.onContainer,
  );

  final String label;
  final Color primary;
  final Color container;
  final Color onContainer;

  Color get onPrimary =>
      primary.computeLuminance() > 0.179 ? Colors.black : Colors.white;
}

class CommuterPreferences {
  final AppThemeMode themeMode;
  final ColorPalette colorPalette;
  final bool highContrastMap;
  final bool compactUi;
  final bool useMetricUnits;

  const CommuterPreferences({
    this.themeMode = AppThemeMode.system,
    this.colorPalette = ColorPalette.pasigDusk,
    this.highContrastMap = false,
    this.compactUi = false,
    this.useMetricUnits = true,
  });

  CommuterPreferences copyWith({
    AppThemeMode? themeMode,
    ColorPalette? colorPalette,
    bool? highContrastMap,
    bool? compactUi,
    bool? useMetricUnits,
  }) {
    return CommuterPreferences(
      themeMode: themeMode ?? this.themeMode,
      colorPalette: colorPalette ?? this.colorPalette,
      highContrastMap: highContrastMap ?? this.highContrastMap,
      compactUi: compactUi ?? this.compactUi,
      useMetricUnits: useMetricUnits ?? this.useMetricUnits,
    );
  }
}

class CommuterPreferencesService {
  static final SupabaseClient _client = Supabase.instance.client;
  static final ValueNotifier<CommuterPreferences> current = ValueNotifier(
    const CommuterPreferences(),
  );

  static Future<CommuterPreferences> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      current.value = const CommuterPreferences();
      return current.value;
    }

    final response = await _client
        .from('user_preferences')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();
    final row = response ?? const <String, dynamic>{};
    final preferences = CommuterPreferences(
      themeMode: _enumFromName(
        AppThemeMode.values,
        row['theme_mode'],
        AppThemeMode.system,
      ),
      colorPalette: _enumFromName(
        ColorPalette.values,
        row['color_palette'],
        ColorPalette.pasigDusk,
      ),
      highContrastMap: row['high_contrast_map'] as bool? ?? false,
      compactUi: row['compact_ui'] as bool? ?? false,
      useMetricUnits: row['use_metric_units'] as bool? ?? true,
    );
    current.value = preferences;
    return preferences;
  }

  static Future<void> save(CommuterPreferences preferences) async {
    current.value = preferences;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('user_preferences').upsert({
      'user_id': userId,
      'theme_mode': preferences.themeMode.name,
      'color_palette': preferences.colorPalette.name,
      'high_contrast_map': preferences.highContrastMap,
      'compact_ui': preferences.compactUi,
      'use_metric_units': preferences.useMetricUnits,
    });
  }

  static T _enumFromName<T extends Enum>(
    List<T> values,
    Object? value,
    T fallback,
  ) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return fallback;
  }

  static Future<Map<String, dynamic>> loadPreferences() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};

    final response = await _client
        .from('user_preferences')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();

    return response ?? {};
  }

  static Future<void> updatePassengerType(String passengerType) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('user_preferences').upsert({
      'user_id': userId,
      'passenger_type': passengerType,
    });
  }

  static Future<void> updateColorPalette(String colorPalette) async {
    final palette = _enumFromName(
      ColorPalette.values,
      colorPalette,
      current.value.colorPalette,
    );
    await save(current.value.copyWith(colorPalette: palette));
  }

  static Future<void> updateThemeMode(String themeMode) async {
    final mode = _enumFromName(
      AppThemeMode.values,
      themeMode,
      current.value.themeMode,
    );
    await save(current.value.copyWith(themeMode: mode));
  }
}
