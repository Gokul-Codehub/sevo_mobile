// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get language => 'Language';

  @override
  String get languageSheetTitle => 'Choose language';

  @override
  String get tryAgain => 'Try again';

  @override
  String get goBack => 'Go back';

  @override
  String get maintenanceTitleDefault => 'We are upgrading SEVO';

  @override
  String get maintenanceMessageDefault => 'We will be back shortly.';

  @override
  String get maintenanceBackIn => 'Back in';

  @override
  String get maintenanceAnyMoment => 'Any moment now';

  @override
  String get maintenanceChecking => 'Checking...';

  @override
  String get maintenanceAutoCheck => 'We check automatically every 30 seconds.';

  @override
  String unavailableTitle(String label) {
    return '$label is temporarily unavailable';
  }

  @override
  String get unavailableBody =>
      'We are working on it. Please try again in a little while.';

  @override
  String get serverUnreachable => 'We could not reach SEVO. Retrying...';

  @override
  String get permContinue => 'Continue';

  @override
  String get permNotNow => 'Not now';

  @override
  String get permNeeded => 'Permission needed';

  @override
  String get permOpenSettings => 'Open settings';

  @override
  String get permCancel => 'Cancel';

  @override
  String get devicesTitle => 'Your devices';

  @override
  String get devicesIntro => 'These phones are signed in to your SEVO account.';

  @override
  String get thisDevice => 'This device';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutAllOthers => 'Sign out all other devices';

  @override
  String get notifSettingsTitle => 'Notification settings';

  @override
  String get notifSettingsIntro =>
      'Choose what SEVO tells you about. Updates about an active booking are always saved in your notification list.';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackSending => 'Sending...';

  @override
  String get feedbackHint => 'Write your message here';

  @override
  String get feedbackThanks => 'Thank you - we have received your feedback.';
}
