import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';

void main() {
  test('extracts route intent from a natural-language query', () {
    final intent = AiAssistantService.parse('from Taft to Makati fastest');

    expect(intent.origin, 'Taft');
    expect(intent.destination, 'Makati');
    expect(intent.preference, 'fastest');
  });

  test('extracts a simple destination query', () {
    final intent = AiAssistantService.parse('find UP Diliman');

    expect(intent.destination, 'UP Diliman');
    expect(intent.preference, isNull);
  });

  test('supports Taglish route requests', () {
    final intent = AiAssistantService.parse('punta sa BGC cheapest');

    expect(intent.destination, 'BGC');
    expect(intent.preference, 'cheapest');
  });
}
