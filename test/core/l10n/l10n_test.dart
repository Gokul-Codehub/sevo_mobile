import 'dart:convert';
import 'dart:io';

import 'package:calservices_customer/core/l10n/locale_controller.dart';
import 'package:calservices_customer/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> arb(String code) => jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;

class MemStore extends LocaleStore {
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String code) async => saved = code;
}

void main() {
  test('Hindi and Tamil have every key English has, with no empty strings', () {
    final en = arb('en').keys.where((k) => !k.startsWith('@')).toSet();
    for (final code in ['hi', 'ta']) {
      final other = arb(code);
      for (final k in en) {
        expect(other.containsKey(k), isTrue, reason: '$code is missing $k');
        expect((other[k] as String).trim(), isNotEmpty, reason: '$code.$k is empty');
      }
    }
  });

  test('placeholders are preserved in translations', () {
    for (final code in ['hi', 'ta']) {
      expect((arb(code)['unavailableTitle'] as String).contains('{label}'), isTrue, reason: code);
    }
  });

  test('the language list matches the supported locales', () {
    expect(kLanguages.keys.toSet(), AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet());
  });

  test('English until the customer chooses; the choice is remembered and bad codes are ignored', () async {
    final store = MemStore();
    final c = LocaleController(store);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, const Locale('en'));
    await c.choose('hi');
    expect(c.state, const Locale('hi'));
    expect(store.saved, 'hi');
    await c.choose('xx');
    expect(c.state, const Locale('hi'));
    final again = LocaleController(store);
    await Future<void>.delayed(Duration.zero);
    expect(again.state, const Locale('hi'));
  });

  testWidgets('screens render in the chosen language', (tester) async {
    Future<void> pump(Locale locale) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: Builder(builder: (c) => Column(children: [Text(c.l10n.tryAgain), Text(c.l10n.unavailableTitle('Groceries'))]))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await pump(const Locale('en'));
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Groceries is temporarily unavailable'), findsOneWidget);
    await pump(const Locale('hi'));
    expect(find.text('फिर से कोशिश करें'), findsOneWidget);
    await pump(const Locale('ta'));
    expect(find.text('மீண்டும் முயற்சிக்கவும்'), findsOneWidget);
  });

  testWidgets('l10n extension falls back to English with no localization installed', (tester) async {
    late String text;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      text = c.l10n.tryAgain;
      return const SizedBox();
    })));
    expect(text, 'Try again');
  });
}
