import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/l10n/app_localizations.dart';
import 'package:frontend/screens/legal/legal_content.dart';

/// The AI consent dialog and the Privacy Policy must name the AI provider,
/// say what is sent, and disclose United States processing, in every
/// supported language. Guards against a translation silently falling back
/// to English or losing one of these disclosures.
void main() {
  // Per language: the provider, the US-transfer phrase, and the words for
  // budget / language / weather that must appear in the consent text.
  const expectations = <String, List<String>>{
    'en': ['Groq', 'United States', 'budget', 'language', 'weather'],
    'es': ['Groq', 'Estados Unidos', 'presupuesto', 'idioma', 'tiempo'],
    'fr': ['Groq', 'États-Unis', 'budget', 'langue', 'météo'],
    'de': ['Groq', 'USA', 'Budget', 'Sprache', 'Wettervorhersage'],
    'it': ['Groq', 'Stati Uniti', 'budget', 'lingua', 'meteo'],
    'pt': ['Groq', 'Estados Unidos', 'orçamento', 'idioma', 'previsão do tempo'],
  };

  group('AI consent disclosure (planner.aiDisclosureBody)', () {
    final english = AppLocalizations.resolve('planner.aiDisclosureBody', 'en');

    for (final entry in expectations.entries) {
      test('${entry.key}: names Groq, data sent and US processing', () {
        final text =
            AppLocalizations.resolve('planner.aiDisclosureBody', entry.key);
        for (final phrase in entry.value) {
          expect(text, contains(phrase), reason: '${entry.key}: "$phrase"');
        }
        if (entry.key != 'en') {
          expect(text, isNot(english), reason: 'falls back to English');
        }
      });
    }

    test('no unverifiable "solely" / exclusivity claim remains', () {
      for (final code in expectations.keys) {
        final text =
            AppLocalizations.resolve('planner.aiDisclosureBody', code)
                .toLowerCase();
        for (final word in [
          'solely', 'exclusivamente', 'uniquement', 'ausschließlich',
          'solo per', 'apenas para gerar',
        ]) {
          expect(text, isNot(contains(word)), reason: '$code: "$word"');
        }
      }
    });
  });

  group('Privacy Policy section 4', () {
    final section = PrivacyContent.sections.firstWhere(
      (s) => s.title == '4. Third-Party AI Processing',
    );
    final body = section.body;

    test('names Groq and every data category actually sent', () {
      for (final phrase in [
        'Groq',
        'destination',
        'travel dates',
        'number of travelers',
        'budget',
        'travel style',
        'interests',
        'language preference',
        'weather forecast',
        'activity being replaced',
        'other activities already planned',
        'We do not send your name, email',
      ]) {
        expect(body, contains(phrase), reason: phrase);
      }
    });

    test('discloses US processing, retention and training terms', () {
      expect(body, contains('processed and stored in the United States'));
      expect(body, contains('up to 30 days'));
      expect(body, contains('not permitted to use these inputs and outputs'));
    });

    test('separates Tripora practices from Groq; no blanket guarantee', () {
      expect(body, contains('Tripora does not use your trip details for '
          'advertising'));
      expect(body, isNot(contains('solely')));
      expect(body, isNot(contains('build profiles')));
      expect(body.split('\n\n').length, greaterThanOrEqualTo(3));
    });
  });
}
