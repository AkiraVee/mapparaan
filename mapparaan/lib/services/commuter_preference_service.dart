import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ── 1. APP THEME MODES ──
/// Controls whether the app follows system default, dark mode, or light mode.
enum AppThemeMode { system, light, dark }

/// ── 2. MANILA LANDMARK COLOR PALETTES ──
/// Accent color schemes inspired by Manila's iconic landmarks.
enum ColorPalette {
  systemDefault('Intramuros Teal', Color(0xFF00695C), Color(0xFFE0F2F1)),
  fortSantiago('Fort Santiago Brick', Color(0xFFBF360C), Color(0xFFFBE9E7)),
  manilaBay('Baywalk Sunset', Color(0xFFE65100), Color(0xFFFFF3E0)),
  binondo('Binondo Lantern Gold', Color(0xFFF57F17), Color(0xFFFFF8E1)),
  pasigDusk('Pasig River Dusk', Color(0xFF6A1B9A), Color(0xFFF3E5F5)),
  escoltaSlate('Escolta Heritage Slate', Color(0xFF37474F), Color(0xFFECEFF1));

  final String label;
  final Color primary;
  final Color container;

  const ColorPalette(this.label, this.primary, this.container);

  Color get onPrimary =>
      primary.computeLuminance() > 0.179 ? Colors.black : Colors.white;

  Color get onContainer =>
      container.computeLuminance() > 0.179 ? Colors.black : Colors.white;
}

/// ── 3. PREFERENCES MODEL ──
class CommuterPreferences {
  final AppThemeMode themeMode;
  final ColorPalette colorPalette;
  final bool useMetricUnits;
  final bool highContrastMap;
  final bool compactUi;

  const CommuterPreferences({
    this.themeMode = AppThemeMode.system,
    this.colorPalette = ColorPalette.systemDefault,
    this.useMetricUnits = true,
    this.highContrastMap = false,
    this.compactUi = false,
  });

  CommuterPreferences copyWith({
    AppThemeMode? themeMode,
    ColorPalette? colorPalette,
    bool? useMetricUnits,
    bool? highContrastMap,
    bool? compactUi,
  }) {
    return CommuterPreferences(
      themeMode: themeMode ?? this.themeMode,
      colorPalette: colorPalette ?? this.colorPalette,
      useMetricUnits: useMetricUnits ?? this.useMetricUnits,
      highContrastMap: highContrastMap ?? this.highContrastMap,
      compactUi: compactUi ?? this.compactUi,
    );
  }
}

/// ── 4. STORAGE SERVICE ──
class CommuterPreferencesService {
  static final ValueNotifier<CommuterPreferences> current = ValueNotifier(
    const CommuterPreferences(),
  );

  static const String _keyThemeMode = 'pref_theme_mode';
  static const String _keyPalette = 'pref_color_palette';
  static const String _keyMetric = 'pref_use_metric';
  static const String _keyContrast = 'pref_high_contrast';
  static const String _keyCompactUi = 'pref_compact_ui';

  /// Reads stored preferences from disk; falls back safely to Intramuros Teal.
  static Future<CommuterPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeName =
        prefs.getString(_keyThemeMode) ?? AppThemeMode.system.name;
    final paletteName =
        prefs.getString(_keyPalette) ?? ColorPalette.systemDefault.name;

    final loaded = CommuterPreferences(
      themeMode: AppThemeMode.values.firstWhere(
        (e) => e.name == themeName,
        orElse: () => AppThemeMode.system,
      ),
      colorPalette: ColorPalette.values.firstWhere(
        (e) => e.name == paletteName,
        orElse: () => ColorPalette.systemDefault, // Safe fallback
      ),
      useMetricUnits: prefs.getBool(_keyMetric) ?? true,
      highContrastMap: prefs.getBool(_keyContrast) ?? false,
      compactUi: prefs.getBool(_keyCompactUi) ?? false,
    );
    current.value = loaded;
    return loaded;
  }

  static Future<void> save(CommuterPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, preferences.themeMode.name);
    await prefs.setString(_keyPalette, preferences.colorPalette.name);
    await prefs.setBool(_keyMetric, preferences.useMetricUnits);
    await prefs.setBool(_keyContrast, preferences.highContrastMap);
    await prefs.setBool(_keyCompactUi, preferences.compactUi);
    current.value = preferences;
  }
}
