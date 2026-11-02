// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get language => 'மொழி';

  @override
  String get languageSheetTitle => 'மொழியைத் தேர்ந்தெடுக்கவும்';

  @override
  String get tryAgain => 'மீண்டும் முயற்சிக்கவும்';

  @override
  String get goBack => 'திரும்பிச் செல்';

  @override
  String get maintenanceTitleDefault => 'SEVO-வை மேம்படுத்துகிறோம்';

  @override
  String get maintenanceMessageDefault => 'விரைவில் திரும்பி வருவோம்.';

  @override
  String get maintenanceBackIn => 'திரும்ப வர';

  @override
  String get maintenanceAnyMoment => 'இன்னும் சில நொடிகளில்';

  @override
  String get maintenanceChecking => 'சரிபார்க்கிறது...';

  @override
  String get maintenanceAutoCheck =>
      'ஒவ்வொரு 30 வினாடிக்கும் தானாகச் சரிபார்க்கிறோம்.';

  @override
  String unavailableTitle(String label) {
    return '$label தற்போது கிடைக்கவில்லை';
  }

  @override
  String get unavailableBody =>
      'இதைச் சரிசெய்து கொண்டிருக்கிறோம். சிறிது நேரம் கழித்து மீண்டும் முயற்சிக்கவும்.';

  @override
  String get serverUnreachable =>
      'SEVO-வை அடைய முடியவில்லை. மீண்டும் முயல்கிறோம்...';

  @override
  String get permContinue => 'தொடரவும்';

  @override
  String get permNotNow => 'இப்போது வேண்டாம்';

  @override
  String get permNeeded => 'அனுமதி தேவை';

  @override
  String get permOpenSettings => 'அமைப்புகளைத் திற';

  @override
  String get permCancel => 'ரத்து செய்';

  @override
  String get devicesTitle => 'உங்கள் சாதனங்கள்';

  @override
  String get devicesIntro =>
      'இந்த ஃபோன்கள் உங்கள் SEVO கணக்கில் உள்நுழைந்துள்ளன.';

  @override
  String get thisDevice => 'இந்தச் சாதனம்';

  @override
  String get signOut => 'வெளியேறு';

  @override
  String get signOutAllOthers => 'மற்ற எல்லா சாதனங்களிலிருந்தும் வெளியேறு';

  @override
  String get notifSettingsTitle => 'அறிவிப்பு அமைப்புகள்';

  @override
  String get notifSettingsIntro =>
      'SEVO எதைப் பற்றி உங்களுக்குத் தெரிவிக்க வேண்டும் என்பதைத் தேர்ந்தெடுக்கவும். நடப்பில் உள்ள முன்பதிவு தகவல்கள் எப்போதும் உங்கள் அறிவிப்புப் பட்டியலில் சேமிக்கப்படும்.';

  @override
  String get feedbackTitle => 'கருத்தை அனுப்பு';

  @override
  String get feedbackSend => 'அனுப்பு';

  @override
  String get feedbackSending => 'அனுப்புகிறது...';

  @override
  String get feedbackHint => 'உங்கள் செய்தியை இங்கே எழுதவும்';

  @override
  String get feedbackThanks => 'நன்றி - உங்கள் கருத்து எங்களுக்குக் கிடைத்தது.';
}
