import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Settings screen app bar title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @tabChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get tabChannels;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @tabSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get tabSecurity;

  /// No description provided for @signOutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutDialogTitle;

  /// No description provided for @signOutDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'You will stop receiving new conversations on this device.'**
  String get signOutDialogMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @availabilitySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'AVAILABILITY'**
  String get availabilitySectionTitle;

  /// No description provided for @availabilityHint.
  ///
  /// In en, this message translates to:
  /// **'Only ONLINE receives automatically assigned conversations.'**
  String get availabilityHint;

  /// No description provided for @availabilityOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get availabilityOnline;

  /// No description provided for @availabilityAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get availabilityAway;

  /// No description provided for @availabilityOnBreak.
  ///
  /// In en, this message translates to:
  /// **'On break'**
  String get availabilityOnBreak;

  /// No description provided for @availabilityOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get availabilityOffline;

  /// No description provided for @organizationLabel.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organizationLabel;

  /// Employee's visibility scope shown under their role
  ///
  /// In en, this message translates to:
  /// **'Visibility: {scope}'**
  String visibilityLabel(String scope);

  /// No description provided for @preferencesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get preferencesSectionTitle;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPasswordLabel;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordLabel;

  /// No description provided for @newPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters'**
  String get newPasswordHint;

  /// No description provided for @passwordChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChangedMessage;

  /// No description provided for @updatePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get updatePasswordButton;

  /// No description provided for @sessionInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'How your session works'**
  String get sessionInfoTitle;

  /// No description provided for @sessionInfoBody.
  ///
  /// In en, this message translates to:
  /// **'This app signs in with an httpOnly session cookie, the same credential the web client uses. Platform tokens for Meta and WhatsApp stay encrypted on the server and are never sent to this device.'**
  String get sessionInfoBody;

  /// No description provided for @noChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'No channels connected'**
  String get noChannelsTitle;

  /// No description provided for @noChannelsMessage.
  ///
  /// In en, this message translates to:
  /// **'Connect Instagram, Messenger or WhatsApp from the web app to start receiving conversations.'**
  String get noChannelsMessage;

  /// No description provided for @channelStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get channelStatusConnected;

  /// No description provided for @channelStatusDegraded.
  ///
  /// In en, this message translates to:
  /// **'Degraded'**
  String get channelStatusDegraded;

  /// No description provided for @channelStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get channelStatusError;

  /// No description provided for @channelStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get channelStatusDisconnected;

  /// No description provided for @channelStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending setup'**
  String get channelStatusPending;

  /// No description provided for @channelConversationCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 conversation} other{{count} conversations}}'**
  String channelConversationCount(int count);

  /// No description provided for @noConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get noConnectionTitle;

  /// No description provided for @genericErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get genericErrorTitle;

  /// No description provided for @genericErrorFallbackMessage.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get genericErrorFallbackMessage;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryButton;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get commonCloseSearch;

  /// No description provided for @timeNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get timeNow;

  /// No description provided for @dayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dayToday;

  /// No description provided for @dayYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dayYesterday;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navInbox;

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navEmployees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get navEmployees;

  /// No description provided for @navTeams.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get navTeams;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @noAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access'**
  String get noAccessTitle;

  /// No description provided for @noAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Your role does not include {section}. Ask an administrator if you need it.'**
  String noAccessMessage(String section);

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting;

  /// No description provided for @notFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFoundTitle;

  /// No description provided for @notFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'That screen does not exist.'**
  String get notFoundMessage;

  /// No description provided for @backToInbox.
  ///
  /// In en, this message translates to:
  /// **'Back to inbox'**
  String get backToInbox;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use your Scenario employee account.'**
  String get signInSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'you@company.com'**
  String get emailHint;

  /// No description provided for @emailValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get emailValidationError;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get passwordValidationError;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInButton;

  /// No description provided for @inboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inboxTitle;

  /// No description provided for @searchConversationsHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get searchConversationsHint;

  /// No description provided for @filtersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersTooltip;

  /// No description provided for @noConversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversationsTitle;

  /// No description provided for @noConversationsMessage.
  ///
  /// In en, this message translates to:
  /// **'New customer messages will appear here as they arrive.'**
  String get noConversationsMessage;

  /// No description provided for @noFilterMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches those filters'**
  String get noFilterMatchesTitle;

  /// No description provided for @noFilterMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Try widening or clearing the filters.'**
  String get noFilterMatchesMessage;

  /// No description provided for @clearFiltersButton.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFiltersButton;

  /// No description provided for @noMessagesYetPreview.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYetPreview;

  /// No description provided for @unassignedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassignedBadge;

  /// No description provided for @youBadge.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youBadge;

  /// No description provided for @filtersTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersTitle;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @assignmentSection.
  ///
  /// In en, this message translates to:
  /// **'Assignment'**
  String get assignmentSection;

  /// No description provided for @assignedToMeFilter.
  ///
  /// In en, this message translates to:
  /// **'Assigned to me'**
  String get assignedToMeFilter;

  /// No description provided for @unassignedFilter.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassignedFilter;

  /// No description provided for @statusSection.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusSection;

  /// No description provided for @prioritySection.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get prioritySection;

  /// No description provided for @channelSection.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channelSection;

  /// No description provided for @showResultsButton.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get showResultsButton;

  /// No description provided for @statusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get statusNew;

  /// No description provided for @statusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpen;

  /// No description provided for @statusWaitingCustomer.
  ///
  /// In en, this message translates to:
  /// **'Waiting on customer'**
  String get statusWaitingCustomer;

  /// No description provided for @statusWaitingInternal.
  ///
  /// In en, this message translates to:
  /// **'Waiting internally'**
  String get statusWaitingInternal;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @priorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get priorityUrgent;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @priorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get priorityNormal;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @providerWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get providerWhatsapp;

  /// No description provided for @providerFacebook.
  ///
  /// In en, this message translates to:
  /// **'Messenger'**
  String get providerFacebook;

  /// No description provided for @providerInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get providerInstagram;

  /// No description provided for @providerTiktok.
  ///
  /// In en, this message translates to:
  /// **'TikTok'**
  String get providerTiktok;

  /// No description provided for @providerSandbox.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get providerSandbox;

  /// No description provided for @actionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actionsTitle;

  /// No description provided for @assignToMe.
  ///
  /// In en, this message translates to:
  /// **'Assign to me'**
  String get assignToMe;

  /// No description provided for @assignedToYouMessage.
  ///
  /// In en, this message translates to:
  /// **'Assigned to you'**
  String get assignedToYouMessage;

  /// No description provided for @unassignAction.
  ///
  /// In en, this message translates to:
  /// **'Unassign'**
  String get unassignAction;

  /// No description provided for @unassignedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassignedMessage;

  /// No description provided for @statusUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Status updated'**
  String get statusUpdatedMessage;

  /// No description provided for @priorityUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Priority updated'**
  String get priorityUpdatedMessage;

  /// No description provided for @noPermissionToChange.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change this conversation.'**
  String get noPermissionToChange;

  /// No description provided for @conversationFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversationFallbackTitle;

  /// No description provided for @customerDetailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Customer details'**
  String get customerDetailsTooltip;

  /// No description provided for @actionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actionsTooltip;

  /// No description provided for @ordersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Orders and customer details'**
  String get ordersTooltip;

  /// No description provided for @intelligenceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Conversation intelligence'**
  String get intelligenceTooltip;

  /// No description provided for @loadingConversation.
  ///
  /// In en, this message translates to:
  /// **'Loading conversation…'**
  String get loadingConversation;

  /// No description provided for @noMessagesYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYetTitle;

  /// No description provided for @noMessagesYetMessage.
  ///
  /// In en, this message translates to:
  /// **'This conversation has no history.'**
  String get noMessagesYetMessage;

  /// No description provided for @writeReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get writeReplyHint;

  /// No description provided for @readOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get readOnlyLabel;

  /// No description provided for @notDeliveredFallback.
  ///
  /// In en, this message translates to:
  /// **'Not delivered.'**
  String get notDeliveredFallback;

  /// No description provided for @discardAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardAction;

  /// No description provided for @retryMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryMessageAction;

  /// No description provided for @customerTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerTitle;

  /// No description provided for @conversationSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversationSectionTitle;

  /// No description provided for @categoryFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryFieldLabel;

  /// No description provided for @assignedToFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get assignedToFieldLabel;

  /// No description provided for @teamFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get teamFieldLabel;

  /// No description provided for @channelFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channelFieldLabel;

  /// No description provided for @messagesFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesFieldLabel;

  /// No description provided for @startedFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get startedFieldLabel;

  /// No description provided for @lastMessageFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Last message'**
  String get lastMessageFieldLabel;

  /// No description provided for @customerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerSectionTitle;

  /// No description provided for @lifecycleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Lifecycle'**
  String get lifecycleFieldLabel;

  /// No description provided for @intelligenceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Intelligence'**
  String get intelligenceSectionTitle;

  /// No description provided for @stageFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get stageFieldLabel;

  /// No description provided for @leadScoreFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Lead score'**
  String get leadScoreFieldLabel;

  /// No description provided for @purchaseFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchaseFieldLabel;

  /// No description provided for @reviewFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewFieldLabel;

  /// No description provided for @needsHumanReviewValue.
  ///
  /// In en, this message translates to:
  /// **'Needs human review'**
  String get needsHumanReviewValue;

  /// No description provided for @dashboardGreeting.
  ///
  /// In en, this message translates to:
  /// **'Good to see you, {name}'**
  String dashboardGreeting(String name);

  /// No description provided for @conversationsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsSectionTitle;

  /// No description provided for @openMetric.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openMetric;

  /// No description provided for @waitingMetric.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waitingMetric;

  /// No description provided for @resolvedTodayMetric.
  ///
  /// In en, this message translates to:
  /// **'Resolved today'**
  String get resolvedTodayMetric;

  /// No description provided for @customerIntelligenceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer intelligence'**
  String get customerIntelligenceSectionTitle;

  /// No description provided for @qualifiedLeadsMetric.
  ///
  /// In en, this message translates to:
  /// **'Qualified leads'**
  String get qualifiedLeadsMetric;

  /// No description provided for @hotLeadsMetric.
  ///
  /// In en, this message translates to:
  /// **'Hot leads'**
  String get hotLeadsMetric;

  /// No description provided for @purchaseClaimsMetric.
  ///
  /// In en, this message translates to:
  /// **'Purchase claims'**
  String get purchaseClaimsMetric;

  /// No description provided for @purchaseClaimsHint.
  ///
  /// In en, this message translates to:
  /// **'Said they ordered. Not verified.'**
  String get purchaseClaimsHint;

  /// No description provided for @confirmedMetric.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmedMetric;

  /// No description provided for @confirmedHint.
  ///
  /// In en, this message translates to:
  /// **'Checked by an employee.'**
  String get confirmedHint;

  /// No description provided for @reviewNeededMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 conversation needs review} other{{count} conversations need review}}'**
  String reviewNeededMessage(int count);

  /// No description provided for @reviewNeededDescription.
  ///
  /// In en, this message translates to:
  /// **'A customer claimed a purchase. Scenario cannot verify payments — check your records and confirm.'**
  String get reviewNeededDescription;

  /// No description provided for @checkInboxButton.
  ///
  /// In en, this message translates to:
  /// **'Check Inbox'**
  String get checkInboxButton;

  /// No description provided for @myLast14DaysTitle.
  ///
  /// In en, this message translates to:
  /// **'Your last 14 days'**
  String get myLast14DaysTitle;

  /// No description provided for @teamWorkloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Team workload'**
  String get teamWorkloadTitle;

  /// No description provided for @onlineAgentsSuffix.
  ///
  /// In en, this message translates to:
  /// **'{count} online'**
  String onlineAgentsSuffix(int count);

  /// No description provided for @nothingAssignedMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing assigned right now.'**
  String get nothingAssignedMessage;

  /// No description provided for @openUnreadSummary.
  ///
  /// In en, this message translates to:
  /// **'{open} open · {unread} unread'**
  String openUnreadSummary(int open, int unread);

  /// No description provided for @openSummary.
  ///
  /// In en, this message translates to:
  /// **'{open} open'**
  String openSummary(int open);

  /// No description provided for @analyticsInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Computed live from the conversation database. Historical trends need a metrics rollup.'**
  String get analyticsInfoBanner;

  /// No description provided for @volumeByChannelTitle.
  ///
  /// In en, this message translates to:
  /// **'Volume by channel'**
  String get volumeByChannelTitle;

  /// No description provided for @noConversationsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No conversations recorded yet.'**
  String get noConversationsRecorded;

  /// No description provided for @leadPipelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Lead pipeline'**
  String get leadPipelineTitle;

  /// No description provided for @qualifiedMetric.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get qualifiedMetric;

  /// No description provided for @avgScoreMetric.
  ///
  /// In en, this message translates to:
  /// **'Avg score'**
  String get avgScoreMetric;

  /// No description provided for @awaitingReviewMetric.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get awaitingReviewMetric;

  /// No description provided for @purchaseEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase evidence'**
  String get purchaseEvidenceTitle;

  /// No description provided for @unverifiedClaimsLabel.
  ///
  /// In en, this message translates to:
  /// **'Unverified customer claims'**
  String get unverifiedClaimsLabel;

  /// No description provided for @unverifiedClaimsNote.
  ///
  /// In en, this message translates to:
  /// **'Customers who said they ordered or paid. Scenario has no payment data and cannot verify these.'**
  String get unverifiedClaimsNote;

  /// No description provided for @employeeConfirmedLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee-confirmed'**
  String get employeeConfirmedLabel;

  /// No description provided for @employeeConfirmedNoteWithCount.
  ///
  /// In en, this message translates to:
  /// **'A team member checked their own records. {count} today.'**
  String employeeConfirmedNoteWithCount(int count);

  /// No description provided for @employeeConfirmedNote.
  ///
  /// In en, this message translates to:
  /// **'A team member checked their own records and confirmed.'**
  String get employeeConfirmedNote;

  /// No description provided for @scopedToVisibleConversations.
  ///
  /// In en, this message translates to:
  /// **'Scoped to the conversations you can see.'**
  String get scopedToVisibleConversations;

  /// No description provided for @employeePerformanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee performance'**
  String get employeePerformanceTitle;

  /// No description provided for @nobodyHandledMessage.
  ///
  /// In en, this message translates to:
  /// **'Nobody handled a conversation in this window.'**
  String get nobodyHandledMessage;

  /// No description provided for @totalOpenSuffix.
  ///
  /// In en, this message translates to:
  /// **'{total} total · {open} open'**
  String totalOpenSuffix(int total, int open);

  /// No description provided for @emailFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailFieldLabel;

  /// No description provided for @phoneFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneFieldLabel;

  /// No description provided for @locationFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationFieldLabel;

  /// No description provided for @lastSeenFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeenFieldLabel;

  /// No description provided for @conversationsCapsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'CONVERSATIONS'**
  String get conversationsCapsSectionTitle;

  /// No description provided for @noVisibleConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations you can see.'**
  String get noVisibleConversations;

  /// No description provided for @searchCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, email, phone or handle'**
  String get searchCustomersHint;

  /// No description provided for @noCustomersTitle.
  ///
  /// In en, this message translates to:
  /// **'No customers'**
  String get noCustomersTitle;

  /// No description provided for @noCustomersMessage.
  ///
  /// In en, this message translates to:
  /// **'Customers appear the first time they message you.'**
  String get noCustomersMessage;

  /// No description provided for @chatCountBadge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 chat} other{{count} chats}}'**
  String chatCountBadge(int count);

  /// No description provided for @searchEmployeesHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email'**
  String get searchEmployeesHint;

  /// No description provided for @onlineNowFilter.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get onlineNowFilter;

  /// No description provided for @totalCountSuffix.
  ///
  /// In en, this message translates to:
  /// **'{total} total'**
  String totalCountSuffix(int total);

  /// No description provided for @nobodyOnlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Nobody is online'**
  String get nobodyOnlineTitle;

  /// No description provided for @turnOffFilterMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn off the filter to see everyone.'**
  String get turnOffFilterMessage;

  /// No description provided for @noEmployeesFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'No employees found'**
  String get noEmployeesFoundTitle;

  /// No description provided for @tryDifferentSearchMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get tryDifferentSearchMessage;

  /// No description provided for @inactiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactiveBadge;

  /// No description provided for @noTeamsTitle.
  ///
  /// In en, this message translates to:
  /// **'No teams yet'**
  String get noTeamsTitle;

  /// No description provided for @noTeamsMessage.
  ///
  /// In en, this message translates to:
  /// **'Teams group agents so conversations can be routed and monitored together.'**
  String get noTeamsMessage;

  /// No description provided for @memberCountBadge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 member} other{{count} members}}'**
  String memberCountBadge(int count);

  /// No description provided for @ledByLabel.
  ///
  /// In en, this message translates to:
  /// **'Led by {names}'**
  String ledByLabel(String names);

  /// No description provided for @suggestedFromChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested from this chat'**
  String get suggestedFromChatTitle;

  /// No description provided for @suggestedFromChatDescription.
  ///
  /// In en, this message translates to:
  /// **'Read out of the conversation automatically. Nothing here is saved to the customer until you accept it.'**
  String get suggestedFromChatDescription;

  /// No description provided for @customerDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer details'**
  String get customerDetailsTitle;

  /// No description provided for @nothingRecordedMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet. Anything the customer shares — an address, a phone number — can be saved here.'**
  String get nothingRecordedMessage;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersTitle;

  /// No description provided for @orderButton.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get orderButton;

  /// No description provided for @noOrdersRecordedMessage.
  ///
  /// In en, this message translates to:
  /// **'No orders recorded from this conversation.'**
  String get noOrdersRecordedMessage;

  /// No description provided for @employeeSourceBadge.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get employeeSourceBadge;

  /// No description provided for @autoSourceBadge.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoSourceBadge;

  /// No description provided for @saveToCustomerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save to the customer'**
  String get saveToCustomerTooltip;

  /// No description provided for @dismissSuggestionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss — it won\'t be suggested again'**
  String get dismissSuggestionTooltip;

  /// No description provided for @confidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'{percent}% confidence'**
  String confidenceLabel(int percent);

  /// No description provided for @tapToCorrectHint.
  ///
  /// In en, this message translates to:
  /// **'tap to correct'**
  String get tapToCorrectHint;

  /// No description provided for @savedToCustomerMessage.
  ///
  /// In en, this message translates to:
  /// **'Saved to the customer'**
  String get savedToCustomerMessage;

  /// No description provided for @suggestionDismissedMessage.
  ///
  /// In en, this message translates to:
  /// **'Suggestion dismissed'**
  String get suggestionDismissedMessage;

  /// No description provided for @recordDetailDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a customer detail'**
  String get recordDetailDialogTitle;

  /// No description provided for @detailFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get detailFieldLabel;

  /// No description provided for @detailFieldHint.
  ///
  /// In en, this message translates to:
  /// **'address'**
  String get detailFieldHint;

  /// No description provided for @valueFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get valueFieldLabel;

  /// No description provided for @valueFieldHint.
  ///
  /// In en, this message translates to:
  /// **'12 Nile St, Giza'**
  String get valueFieldHint;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// No description provided for @orderConfirmedMessage.
  ///
  /// In en, this message translates to:
  /// **'Order confirmed'**
  String get orderConfirmedMessage;

  /// No description provided for @cancelOrderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order'**
  String get cancelOrderTooltip;

  /// No description provided for @orderCancelledMessage.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get orderCancelledMessage;

  /// No description provided for @notCountedAsSaleMessage.
  ///
  /// In en, this message translates to:
  /// **'Not counted as a sale until someone confirms it.'**
  String get notCountedAsSaleMessage;

  /// No description provided for @confirmedByMessage.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by {name}'**
  String confirmedByMessage(String name);

  /// No description provided for @confirmedByUnknownEmployee.
  ///
  /// In en, this message translates to:
  /// **'an employee'**
  String get confirmedByUnknownEmployee;

  /// No description provided for @recordOrderDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Record an order'**
  String get recordOrderDialogTitle;

  /// No description provided for @orderComposerDescription.
  ///
  /// In en, this message translates to:
  /// **'What the customer asked for. Scenario has no payment data, so this is a record of the conversation, not a receipt.'**
  String get orderComposerDescription;

  /// No description provided for @productFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productFieldLabel;

  /// No description provided for @qtyFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qtyFieldLabel;

  /// No description provided for @priceFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceFieldLabel;

  /// No description provided for @addLineButton.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get addLineButton;

  /// No description provided for @totalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// No description provided for @recordOrderButton.
  ///
  /// In en, this message translates to:
  /// **'Record order'**
  String get recordOrderButton;

  /// No description provided for @orderRecordedMessage.
  ///
  /// In en, this message translates to:
  /// **'Order recorded. Confirm it once you\'ve checked your own records.'**
  String get orderRecordedMessage;

  /// No description provided for @avgResponseLabel.
  ///
  /// In en, this message translates to:
  /// **'Avg response'**
  String get avgResponseLabel;

  /// No description provided for @repliesCountedHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 reply} other{{count} replies}} · median {median}'**
  String repliesCountedHint(int count, String median);

  /// No description provided for @noRepliesYetHint.
  ///
  /// In en, this message translates to:
  /// **'No replies yet'**
  String get noRepliesYetHint;

  /// No description provided for @noBaselineRecorded.
  ///
  /// In en, this message translates to:
  /// **'No baseline recorded'**
  String get noBaselineRecorded;

  /// No description provided for @customersLabel.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersLabel;

  /// No description provided for @messagesSentHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 message} other{{count} messages}} sent'**
  String messagesSentHint(int count);

  /// No description provided for @confirmedOrdersLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed orders'**
  String get confirmedOrdersLabel;

  /// No description provided for @confirmedOrderValueHint.
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency}'**
  String confirmedOrderValueHint(String amount, String currency);

  /// No description provided for @recordedNoneConfirmedHint.
  ///
  /// In en, this message translates to:
  /// **'{count} recorded, none confirmed'**
  String recordedNoneConfirmedHint(int count);

  /// No description provided for @byPlatformSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'BY PLATFORM'**
  String get byPlatformSectionTitle;

  /// No description provided for @handledFootnote.
  ///
  /// In en, this message translates to:
  /// **'{count} handled'**
  String handledFootnote(int count);

  /// No description provided for @resolvedFootnote.
  ///
  /// In en, this message translates to:
  /// **'{count} resolved'**
  String resolvedFootnote(int count);

  /// No description provided for @firstReplyFootnote.
  ///
  /// In en, this message translates to:
  /// **'First reply {duration}'**
  String firstReplyFootnote(String duration);

  /// No description provided for @hoursSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'HOURS'**
  String get hoursSectionTitle;

  /// No description provided for @hoursNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded for this period.'**
  String get hoursNotRecorded;

  /// No description provided for @adherenceBadge.
  ///
  /// In en, this message translates to:
  /// **'{percent}% adherence'**
  String adherenceBadge(int percent);

  /// No description provided for @onlineHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineHoursLabel;

  /// No description provided for @scheduledHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduledHoursLabel;

  /// No description provided for @noShiftsSetMessage.
  ///
  /// In en, this message translates to:
  /// **'No shifts set'**
  String get noShiftsSetMessage;

  /// No description provided for @msgCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'{messages} msg · {count, plural, one{1 customer} other{{count} customers}}'**
  String msgCustomersHint(int messages, int count);

  /// No description provided for @misconfiguredTitle.
  ///
  /// In en, this message translates to:
  /// **'No API host configured'**
  String get misconfiguredTitle;

  /// No description provided for @misconfiguredMessage.
  ///
  /// In en, this message translates to:
  /// **'Build with --dart-define=SCENARIO_API_HOST=host:port'**
  String get misconfiguredMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
