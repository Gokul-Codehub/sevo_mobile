import 'dart:io';

import 'package:calservices_customer/core/l10n/locale_controller.dart';
import 'package:calservices_customer/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemStore extends LocaleStore {
  MemStore([this.saved]);
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String code) async => saved = code;
}

void main() {
  test('English is the only language: the list and the supported locales both say so', () {
    expect(kLanguages.keys.toList(), ['en']);
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode).toList(), ['en']);
  });

  test('no Hindi or Tamil translation files are left behind', () {
    for (final f in ['app_hi.arb', 'app_ta.arb', 'app_localizations_hi.dart', 'app_localizations_ta.dart']) {
      expect(File('lib/l10n/$f').existsSync(), isFalse, reason: f);
    }
  });

  test('English until chosen; only English can be chosen; other codes are ignored', () async {
    final store = MemStore();
    final c = LocaleController(store);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, const Locale('en'));
    await c.choose('hi');
    await c.choose('ta');
    await c.choose('xx');
    expect(c.state, const Locale('en'));
    expect(store.saved, isNull); // nothing odd was saved
  });

  test('a Hindi or Tamil choice saved by an older version is dropped: the app stays in English', () async {
    for (final old in ['hi', 'ta']) {
      final store = MemStore(old);
      final c = LocaleController(store);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state, const Locale('en'), reason: old);
      expect(store.saved, 'en', reason: '$old is replaced by English in storage');
    }
  });

  testWidgets('a phone set to Hindi or Tamil still gets the English app', (tester) async {
    for (final code in ['hi', 'ta']) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Builder(builder: (c) => Text(c.l10n.tryAgain))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget, reason: code);
    }
  });

  testWidgets('the Language sheet lists English only and says why', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [localeStoreProvider.overrideWithValue(MemStore())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) => ElevatedButton(onPressed: () => showLanguageSheet(context, ref), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिन्दी'), findsNothing);
    expect(find.text('தமிழ்'), findsNothing);
    expect(find.textContaining('only language available'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget); // English is the selected one
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
