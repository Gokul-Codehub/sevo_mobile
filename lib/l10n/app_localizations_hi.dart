// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get language => 'भाषा';

  @override
  String get languageSheetTitle => 'भाषा चुनें';

  @override
  String get tryAgain => 'फिर से कोशिश करें';

  @override
  String get goBack => 'वापस जाएँ';

  @override
  String get maintenanceTitleDefault => 'हम SEVO को अपग्रेड कर रहे हैं';

  @override
  String get maintenanceMessageDefault => 'हम जल्द ही वापस आएँगे।';

  @override
  String get maintenanceBackIn => 'वापसी में';

  @override
  String get maintenanceAnyMoment => 'बस कुछ ही पल में';

  @override
  String get maintenanceChecking => 'जाँच हो रही है...';

  @override
  String get maintenanceAutoCheck =>
      'हम हर 30 सेकंड में अपने-आप जाँच करते हैं।';

  @override
  String unavailableTitle(String label) {
    return '$label अभी उपलब्ध नहीं है';
  }

  @override
  String get unavailableBody =>
      'हम इस पर काम कर रहे हैं। कृपया थोड़ी देर बाद फिर कोशिश करें।';

  @override
  String get serverUnreachable =>
      'हम SEVO से जुड़ नहीं पाए। फिर कोशिश कर रहे हैं...';

  @override
  String get permContinue => 'आगे बढ़ें';

  @override
  String get permNotNow => 'अभी नहीं';

  @override
  String get permNeeded => 'अनुमति ज़रूरी है';

  @override
  String get permOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get permCancel => 'रद्द करें';

  @override
  String get devicesTitle => 'आपके डिवाइस';

  @override
  String get devicesIntro => 'ये फ़ोन आपके SEVO खाते में साइन इन हैं।';

  @override
  String get thisDevice => 'यह डिवाइस';

  @override
  String get signOut => 'साइन आउट';

  @override
  String get signOutAllOthers => 'बाकी सभी डिवाइस साइन आउट करें';

  @override
  String get notifSettingsTitle => 'सूचना सेटिंग्स';

  @override
  String get notifSettingsIntro =>
      'चुनें कि SEVO आपको किस बारे में बताए। चालू बुकिंग की जानकारी हमेशा आपकी सूचना सूची में सहेजी जाती है।';

  @override
  String get feedbackTitle => 'फ़ीडबैक भेजें';

  @override
  String get feedbackSend => 'भेजें';

  @override
  String get feedbackSending => 'भेजा जा रहा है...';

  @override
  String get feedbackHint => 'अपना संदेश यहाँ लिखें';

  @override
  String get feedbackThanks => 'धन्यवाद - हमें आपका फ़ीडबैक मिल गया है।';
}
