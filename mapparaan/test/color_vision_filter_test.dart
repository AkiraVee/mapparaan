import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/local_ui_preferences_service.dart';

void main() {
  test('color vision filter matrices are valid 4-by-5 matrices', () {
    for (final filter in ColorVisionFilter.values) {
      expect(filter.matrix, hasLength(20));
    }
  });

  test('only the six requested profiles and Off are available', () {
    expect(ColorVisionFilter.values.map((filter) => filter.name), [
      'none',
      'redGreen',
      'blueYellow',
      'protanopia',
      'deuteranopia',
      'tritanopia',
      'achromatopsia',
    ]);
  });

  test('copyWith preserves the selected color vision filter', () {
    const preferences = LocalUiPreferences(
      colorVisionFilter: ColorVisionFilter.redGreen,
    );

    final updated = preferences.copyWith(dataSaver: true);

    expect(updated.colorVisionFilter, ColorVisionFilter.redGreen);
    expect(updated.dataSaver, isTrue);
  });
}
