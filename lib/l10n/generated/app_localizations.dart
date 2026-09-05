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

  /// Fallback title for the foreground push banner, used only if the server payload carries no notification.title
  ///
  /// In en, this message translates to:
  /// **'New activity'**
  String get newActivityBannerTitle;

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

  /// No description provided for @tabAssignment.
  ///
  /// In en, this message translates to:
  /// **'Assignment'**
  String get tabAssignment;

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

  /// No description provided for @muteChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteChannelAction;

  /// No description provided for @unmuteChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmuteChannelAction;

  /// No description provided for @testChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get testChannelAction;

  /// No description provided for @channelMutedLabel.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get channelMutedLabel;

  /// No description provided for @channelMutedByLabel.
  ///
  /// In en, this message translates to:
  /// **'Muted by {name}'**
  String channelMutedByLabel(String name);

  /// No description provided for @hideChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideChannelAction;

  /// No description provided for @showChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showChannelAction;

  /// No description provided for @hiddenChannelsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden ({count})'**
  String hiddenChannelsSectionTitle(int count);

  /// No description provided for @disconnectChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectChannelAction;

  /// No description provided for @reconnectChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnectChannelAction;

  /// No description provided for @checkStatusChannelAction.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get checkStatusChannelAction;

  /// No description provided for @connectAnotherNumberAction.
  ///
  /// In en, this message translates to:
  /// **'Connect another number'**
  String get connectAnotherNumberAction;

  /// No description provided for @connectAnotherAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Connect another account'**
  String get connectAnotherAccountAction;

  /// No description provided for @moreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsTooltip;

  /// No description provided for @channelIdentifierLabel.
  ///
  /// In en, this message translates to:
  /// **'ID: {value}'**
  String channelIdentifierLabel(String value);

  /// No description provided for @channelConnectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Connected {when}'**
  String channelConnectedLabel(String when);

  /// No description provided for @channelLastActivityLabel.
  ///
  /// In en, this message translates to:
  /// **'Last activity {when}'**
  String channelLastActivityLabel(String when);

  /// No description provided for @channelNoActivityLabel.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get channelNoActivityLabel;

  /// No description provided for @disconnectChannelDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {channel}?'**
  String disconnectChannelDialogTitle(String channel);

  /// No description provided for @disconnectChannelDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the stored credential. The conversation history stays, but no new messages can be sent or received on this channel until it\'s reconnected.'**
  String get disconnectChannelDialogBody;

  /// No description provided for @channelDisconnectedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{channel} disconnected.'**
  String channelDisconnectedSnackbar(String channel);

  /// No description provided for @openingBrowserMessage.
  ///
  /// In en, this message translates to:
  /// **'Opening browser…'**
  String get openingBrowserMessage;

  /// No description provided for @couldNotOpenBrowserError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the browser for this connection.'**
  String get couldNotOpenBrowserError;

  /// No description provided for @manageFromWebOnlyAction.
  ///
  /// In en, this message translates to:
  /// **'Manage from web'**
  String get manageFromWebOnlyAction;

  /// No description provided for @manageFromWebOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'This action is only available from the web app.'**
  String get manageFromWebOnlyHint;

  /// No description provided for @updateTokenAction.
  ///
  /// In en, this message translates to:
  /// **'Update token'**
  String get updateTokenAction;

  /// No description provided for @updateTokenSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Update access token'**
  String get updateTokenSheetTitle;

  /// No description provided for @updateTokenSheetDescription.
  ///
  /// In en, this message translates to:
  /// **'Replace this number\'s access token if it expired or was regenerated in the Meta dashboard.'**
  String get updateTokenSheetDescription;

  /// No description provided for @otherWaysToConnectSection.
  ///
  /// In en, this message translates to:
  /// **'Other ways to connect'**
  String get otherWaysToConnectSection;

  /// No description provided for @addAnotherNumberAction.
  ///
  /// In en, this message translates to:
  /// **'Add another number'**
  String get addAnotherNumberAction;

  /// No description provided for @addAnotherNumberHint.
  ///
  /// In en, this message translates to:
  /// **'via phone number ID and access token'**
  String get addAnotherNumberHint;

  /// No description provided for @addAnotherNumberSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a WhatsApp number'**
  String get addAnotherNumberSheetTitle;

  /// No description provided for @useInstagramTokenAction.
  ///
  /// In en, this message translates to:
  /// **'Use Instagram token'**
  String get useInstagramTokenAction;

  /// No description provided for @useInstagramTokenSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect with an Instagram token'**
  String get useInstagramTokenSheetTitle;

  /// No description provided for @useInstagramTokenSheetDescription.
  ///
  /// In en, this message translates to:
  /// **'Paste an Instagram user token generated from Meta\'s dashboard. This attaches the account the token identifies.'**
  String get useInstagramTokenSheetDescription;

  /// No description provided for @manageFacebookPagesAction.
  ///
  /// In en, this message translates to:
  /// **'Manage Facebook Pages'**
  String get manageFacebookPagesAction;

  /// No description provided for @phoneNumberIdFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number ID'**
  String get phoneNumberIdFieldLabel;

  /// No description provided for @accessTokenFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get accessTokenFieldLabel;

  /// No description provided for @wabaIdFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Business Account ID'**
  String get wabaIdFieldLabel;

  /// No description provided for @wabaIdFieldOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — derived from the token when left blank.'**
  String get wabaIdFieldOptionalHint;

  /// No description provided for @instagramTokenFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Instagram access token'**
  String get instagramTokenFieldLabel;

  /// No description provided for @fieldRequiredError.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get fieldRequiredError;

  /// No description provided for @channelConnectedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{channel} connected.'**
  String channelConnectedSnackbar(String channel);

  /// No description provided for @channelTokenUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Access token updated.'**
  String get channelTokenUpdatedSnackbar;

  /// No description provided for @connectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectAction;

  /// No description provided for @updateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateAction;

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

  /// No description provided for @navTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get navTemplates;

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

  /// No description provided for @categorySection.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categorySection;

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

  /// No description provided for @categoryUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Category updated'**
  String get categoryUpdatedMessage;

  /// No description provided for @categoryNoneOption.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get categoryNoneOption;

  /// No description provided for @noPermissionToChange.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change this conversation.'**
  String get noPermissionToChange;

  /// No description provided for @conversationHistoryAction.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get conversationHistoryAction;

  /// No description provided for @conversationHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get conversationHistoryTitle;

  /// No description provided for @conversationHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet.'**
  String get conversationHistoryEmpty;

  /// No description provided for @conversionsAction.
  ///
  /// In en, this message translates to:
  /// **'Conversions'**
  String get conversionsAction;

  /// No description provided for @conversionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing reported to Meta yet.'**
  String get conversionsEmpty;

  /// No description provided for @reportConversionAction.
  ///
  /// In en, this message translates to:
  /// **'Report now'**
  String get reportConversionAction;

  /// No description provided for @conversionsTruncatedNote.
  ///
  /// In en, this message translates to:
  /// **'Showing the most recent {shown} of {total}.'**
  String conversionsTruncatedNote(int shown, int total);

  /// No description provided for @internalNotesAction.
  ///
  /// In en, this message translates to:
  /// **'Internal notes'**
  String get internalNotesAction;

  /// No description provided for @internalNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Internal notes'**
  String get internalNotesTitle;

  /// No description provided for @internalNotesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No internal notes yet.'**
  String get internalNotesEmpty;

  /// No description provided for @internalNoteInputHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note for your team…'**
  String get internalNoteInputHint;

  /// No description provided for @addNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get addNoteAction;

  /// No description provided for @replyTab.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyTab;

  /// No description provided for @internalNoteTab.
  ///
  /// In en, this message translates to:
  /// **'Internal note'**
  String get internalNoteTab;

  /// No description provided for @templateTab.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get templateTab;

  /// No description provided for @notVisibleToCustomer.
  ///
  /// In en, this message translates to:
  /// **'Not visible to customer'**
  String get notVisibleToCustomer;

  /// No description provided for @notSentToCustomer.
  ///
  /// In en, this message translates to:
  /// **'Not sent to the customer'**
  String get notSentToCustomer;

  /// No description provided for @saveNote.
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get saveNote;

  /// No description provided for @approvedTemplate.
  ///
  /// In en, this message translates to:
  /// **'Approved template'**
  String get approvedTemplate;

  /// No description provided for @chooseTemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose a template…'**
  String get chooseTemplate;

  /// No description provided for @sendTemplate.
  ///
  /// In en, this message translates to:
  /// **'Send template'**
  String get sendTemplate;

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

  /// No description provided for @followUpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Follow up'**
  String get followUpTooltip;

  /// No description provided for @markFollowUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow up'**
  String get markFollowUpTitle;

  /// No description provided for @editFollowUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit follow-up'**
  String get editFollowUpTitle;

  /// No description provided for @followUpSwitchLabel.
  ///
  /// In en, this message translates to:
  /// **'Mark as follow-up'**
  String get followUpSwitchLabel;

  /// No description provided for @followUpDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Follow-up date'**
  String get followUpDateLabel;

  /// No description provided for @noFollowUpDate.
  ///
  /// In en, this message translates to:
  /// **'No date set'**
  String get noFollowUpDate;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearDate;

  /// No description provided for @removeFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Remove follow-up'**
  String get removeFollowUp;

  /// No description provided for @saveFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveFollowUp;

  /// No description provided for @followUpUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Follow-up updated'**
  String get followUpUpdatedMessage;

  /// No description provided for @followUpClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'Follow-up removed'**
  String get followUpClearedMessage;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

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

  /// No description provided for @attachmentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachmentTooltip;

  /// No description provided for @attachFromGalleryAction.
  ///
  /// In en, this message translates to:
  /// **'Photo from gallery'**
  String get attachFromGalleryAction;

  /// No description provided for @attachFromCameraAction.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get attachFromCameraAction;

  /// No description provided for @removeAttachmentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachmentTooltip;

  /// No description provided for @attachmentUploadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get attachmentUploadingLabel;

  /// No description provided for @attachmentUploadFailedError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload that file. Please try again.'**
  String get attachmentUploadFailedError;

  /// No description provided for @attachmentPermissionDeniedError.
  ///
  /// In en, this message translates to:
  /// **'Permission was denied. Enable it in your device settings to attach photos.'**
  String get attachmentPermissionDeniedError;

  /// No description provided for @recordVoiceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Record a voice message'**
  String get recordVoiceTooltip;

  /// No description provided for @recordingLabel.
  ///
  /// In en, this message translates to:
  /// **'Recording {duration}'**
  String recordingLabel(String duration);

  /// No description provided for @cancelRecordingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get cancelRecordingTooltip;

  /// No description provided for @stopRecordingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop and send'**
  String get stopRecordingTooltip;

  /// No description provided for @microphonePermissionDeniedError.
  ///
  /// In en, this message translates to:
  /// **'Microphone access was denied. Enable it in your device settings to record a voice message.'**
  String get microphonePermissionDeniedError;

  /// No description provided for @recordingFailedError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording. Please try again.'**
  String get recordingFailedError;

  /// No description provided for @voiceMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessageLabel;

  /// No description provided for @voiceNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNoteLabel;

  /// No description provided for @recordingText.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recordingText;

  /// No description provided for @playVoiceMessageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play voice message'**
  String get playVoiceMessageTooltip;

  /// No description provided for @pauseVoiceMessageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause voice message'**
  String get pauseVoiceMessageTooltip;

  /// No description provided for @voiceMessagePlaybackFailedError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this voice message.'**
  String get voiceMessagePlaybackFailedError;

  /// No description provided for @imageLoadFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load image'**
  String get imageLoadFailedLabel;

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

  /// No description provided for @deleteMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessageAction;

  /// No description provided for @deleteMessageConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this message?'**
  String get deleteMessageConfirmTitle;

  /// No description provided for @deleteMessageConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes it from the timeline for everyone. It does not unsend it on the platform — the customer still has it.'**
  String get deleteMessageConfirmBody;

  /// No description provided for @deleteMessageReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get deleteMessageReasonLabel;

  /// No description provided for @deleteMessageDeletedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get deleteMessageDeletedSnackbar;

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

  /// No description provided for @recentActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivityTitle;

  /// No description provided for @openInboxButton.
  ///
  /// In en, this message translates to:
  /// **'Open inbox'**
  String get openInboxButton;

  /// No description provided for @noRecentActivityMessage.
  ///
  /// In en, this message translates to:
  /// **'No recent activity yet.'**
  String get noRecentActivityMessage;

  /// No description provided for @stageNewLead.
  ///
  /// In en, this message translates to:
  /// **'New lead'**
  String get stageNewLead;

  /// No description provided for @stageQualifiedLead.
  ///
  /// In en, this message translates to:
  /// **'Qualified lead'**
  String get stageQualifiedLead;

  /// No description provided for @stageHotLead.
  ///
  /// In en, this message translates to:
  /// **'Hot lead'**
  String get stageHotLead;

  /// No description provided for @stagePurchaseIntent.
  ///
  /// In en, this message translates to:
  /// **'Purchase intent'**
  String get stagePurchaseIntent;

  /// No description provided for @stagePurchased.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get stagePurchased;

  /// No description provided for @stageLost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get stageLost;

  /// No description provided for @stageDisqualified.
  ///
  /// In en, this message translates to:
  /// **'Disqualified'**
  String get stageDisqualified;

  /// No description provided for @profileDetailsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get profileDetailsSectionTitle;

  /// No description provided for @jobTitleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Job title'**
  String get jobTitleFieldLabel;

  /// No description provided for @saveProfileButton.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get saveProfileButton;

  /// No description provided for @profileUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdatedSnackbar;

  /// No description provided for @profileFirstNameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'First name cannot be empty.'**
  String get profileFirstNameRequiredError;

  /// No description provided for @autoAssignmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic conversation assignment'**
  String get autoAssignmentTitle;

  /// No description provided for @autoAssignmentDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically routes incoming conversations to available agents based on workload and schedule. Affects new allocatable work only.'**
  String get autoAssignmentDescription;

  /// No description provided for @autoAssignmentStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get autoAssignmentStatusActive;

  /// No description provided for @autoAssignmentStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get autoAssignmentStatusInactive;

  /// No description provided for @autoAssignmentToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable automatic assignment'**
  String get autoAssignmentToggleLabel;

  /// No description provided for @defaultChatCapacityTitle.
  ///
  /// In en, this message translates to:
  /// **'Default chat capacity'**
  String get defaultChatCapacityTitle;

  /// No description provided for @defaultChatCapacityDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum open conversations assigned to an agent at one time.'**
  String get defaultChatCapacityDescription;

  /// No description provided for @maxOpenChatsFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Max open chats'**
  String get maxOpenChatsFieldLabel;

  /// No description provided for @maxOpenChatsInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number greater than 0.'**
  String get maxOpenChatsInvalidError;

  /// No description provided for @saveCapacityAction.
  ///
  /// In en, this message translates to:
  /// **'Save capacity'**
  String get saveCapacityAction;

  /// No description provided for @timezoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get timezoneTitle;

  /// No description provided for @timezoneDescription.
  ///
  /// In en, this message translates to:
  /// **'Organization-level time zone. Changing this reinterprets existing schedules without rewriting them.'**
  String get timezoneDescription;

  /// No description provided for @timezoneFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Select time zone'**
  String get timezoneFieldLabel;

  /// No description provided for @saveTimezoneAction.
  ///
  /// In en, this message translates to:
  /// **'Save time zone'**
  String get saveTimezoneAction;

  /// No description provided for @assignmentPolicyUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Assignment settings updated'**
  String get assignmentPolicyUpdatedSnackbar;

  /// No description provided for @routingPolicyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load assignment settings.'**
  String get routingPolicyLoadFailed;

  /// No description provided for @routingPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to manage assignment settings.'**
  String get routingPermissionDenied;

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

  /// No description provided for @confirmedPurchasesFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed purchases'**
  String get confirmedPurchasesFieldLabel;

  /// No description provided for @customerNotesFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customerNotesFieldLabel;

  /// No description provided for @recordedDetailsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Recorded details'**
  String get recordedDetailsSectionTitle;

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

  /// No description provided for @confidenceWithCorrectHintLabel.
  ///
  /// In en, this message translates to:
  /// **'{percent}% confidence · tap to correct'**
  String confidenceWithCorrectHintLabel(int percent);

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

  /// No description provided for @recordDetailDescription.
  ///
  /// In en, this message translates to:
  /// **'Something the customer shared — an address, a phone number, a preference.'**
  String get recordDetailDescription;

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

  /// No description provided for @removeLineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove line'**
  String get removeLineTooltip;

  /// No description provided for @atLeastOneProductError.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one product name.'**
  String get atLeastOneProductError;

  /// No description provided for @validPriceError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid price.'**
  String get validPriceError;

  /// No description provided for @detailRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter both detail and value.'**
  String get detailRequiredError;

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

  /// No description provided for @cancelOrderConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get cancelOrderConfirmTitle;

  /// No description provided for @cancelOrderConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This won\'t be counted as a sale. You can\'t undo this from here.'**
  String get cancelOrderConfirmBody;

  /// No description provided for @keepOrderAction.
  ///
  /// In en, this message translates to:
  /// **'Keep order'**
  String get keepOrderAction;

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

  /// No description provided for @recordedByMessage.
  ///
  /// In en, this message translates to:
  /// **'Recorded by {name}'**
  String recordedByMessage(String name);

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
  /// **'Record an order'**
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

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @deactivateAction.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivateAction;

  /// No description provided for @editCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get editCustomerTitle;

  /// No description provided for @customerUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Customer updated'**
  String get customerUpdatedSnackbar;

  /// No description provided for @displayNameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameFieldLabel;

  /// No description provided for @cityFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityFieldLabel;

  /// No description provided for @countryFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get countryFieldLabel;

  /// No description provided for @tagsFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsFieldLabel;

  /// No description provided for @addEmployeeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add employee'**
  String get addEmployeeTitle;

  /// No description provided for @editEmployeeTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit employee'**
  String get editEmployeeTitle;

  /// No description provided for @employeeAddedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Employee added'**
  String get employeeAddedSnackbar;

  /// No description provided for @employeeUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Employee updated'**
  String get employeeUpdatedSnackbar;

  /// No description provided for @employeeFormRequiredFieldsError.
  ///
  /// In en, this message translates to:
  /// **'Enter an email, first name and last name.'**
  String get employeeFormRequiredFieldsError;

  /// No description provided for @employeeFormPasswordRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter a password for the new employee.'**
  String get employeeFormPasswordRequiredError;

  /// No description provided for @firstNameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstNameFieldLabel;

  /// No description provided for @lastNameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastNameFieldLabel;

  /// No description provided for @roleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleFieldLabel;

  /// No description provided for @employeeTitleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get employeeTitleFieldLabel;

  /// No description provided for @avatarUrlFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Avatar URL'**
  String get avatarUrlFieldLabel;

  /// No description provided for @newPasswordOptionalFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'New password (leave blank to keep current)'**
  String get newPasswordOptionalFieldLabel;

  /// No description provided for @activeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeFieldLabel;

  /// No description provided for @teamsFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get teamsFieldLabel;

  /// No description provided for @teamsLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load teams.'**
  String get teamsLoadFailedMessage;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get roleSupervisor;

  /// No description provided for @roleTeamLeader.
  ///
  /// In en, this message translates to:
  /// **'Team leader'**
  String get roleTeamLeader;

  /// No description provided for @roleQa.
  ///
  /// In en, this message translates to:
  /// **'QA'**
  String get roleQa;

  /// No description provided for @roleAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get roleAgent;

  /// No description provided for @deactivateEmployeeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate employee?'**
  String get deactivateEmployeeConfirmTitle;

  /// No description provided for @deactivateEmployeeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer be able to sign in or receive conversations. Their history and past conversations are kept.'**
  String deactivateEmployeeConfirmBody(String name);

  /// No description provided for @employeeDeactivatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} deactivated'**
  String employeeDeactivatedSnackbar(String name);

  /// No description provided for @addTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Add team'**
  String get addTeamTitle;

  /// No description provided for @editTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit team'**
  String get editTeamTitle;

  /// No description provided for @teamAddedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Team added'**
  String get teamAddedSnackbar;

  /// No description provided for @teamUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Team updated'**
  String get teamUpdatedSnackbar;

  /// No description provided for @addTeamNameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter a team name.'**
  String get addTeamNameRequiredError;

  /// No description provided for @teamNameFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Team name'**
  String get teamNameFieldLabel;

  /// No description provided for @descriptionFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionFieldLabel;

  /// No description provided for @colorFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorFieldLabel;

  /// No description provided for @leadersFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Leaders'**
  String get leadersFieldLabel;

  /// No description provided for @membersFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersFieldLabel;

  /// No description provided for @employeesLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load employees.'**
  String get employeesLoadFailedMessage;

  /// No description provided for @deactivateTeamConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate team?'**
  String get deactivateTeamConfirmTitle;

  /// No description provided for @deactivateTeamConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer be available for routing conversations. Existing conversations and assignment history are kept.'**
  String deactivateTeamConfirmBody(String name);

  /// No description provided for @teamDeactivatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'{name} deactivated'**
  String teamDeactivatedSnackbar(String name);

  /// No description provided for @rerunAnalysisTooltip.
  ///
  /// In en, this message translates to:
  /// **'Re-run analysis'**
  String get rerunAnalysisTooltip;

  /// No description provided for @loadingIntelligenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading intelligence…'**
  String get loadingIntelligenceLabel;

  /// No description provided for @notAnalyzedYetTitle.
  ///
  /// In en, this message translates to:
  /// **'Not analyzed yet'**
  String get notAnalyzedYetTitle;

  /// No description provided for @notAnalyzedYetMessage.
  ///
  /// In en, this message translates to:
  /// **'This conversation has no intelligence read yet. It appears once the analyzer runs, automatically or on demand.'**
  String get notAnalyzedYetMessage;

  /// No description provided for @runAnalysisButton.
  ///
  /// In en, this message translates to:
  /// **'Run analysis'**
  String get runAnalysisButton;

  /// No description provided for @reviewBannerDefaultReason.
  ///
  /// In en, this message translates to:
  /// **'This conversation needs a human look.'**
  String get reviewBannerDefaultReason;

  /// No description provided for @intelligenceSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get intelligenceSummaryLabel;

  /// No description provided for @suggestedNextStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggested next step'**
  String get suggestedNextStepLabel;

  /// No description provided for @interestedInLabel.
  ///
  /// In en, this message translates to:
  /// **'Interested in'**
  String get interestedInLabel;

  /// No description provided for @buyingSignalsLabel.
  ///
  /// In en, this message translates to:
  /// **'Buying signals'**
  String get buyingSignalsLabel;

  /// No description provided for @objectionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Objections'**
  String get objectionsLabel;

  /// No description provided for @lastAnalyzedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last analyzed {when}'**
  String lastAnalyzedLabel(String when);

  /// No description provided for @resetToAiButton.
  ///
  /// In en, this message translates to:
  /// **'Reset to AI'**
  String get resetToAiButton;

  /// No description provided for @setScoreByHandTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set score by hand'**
  String get setScoreByHandTooltip;

  /// No description provided for @handedBackToAnalyzerMessage.
  ///
  /// In en, this message translates to:
  /// **'Handed back to the analyzer'**
  String get handedBackToAnalyzerMessage;

  /// No description provided for @leadScoreUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Lead score updated'**
  String get leadScoreUpdatedMessage;

  /// No description provided for @setLeadScoreDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set the lead score'**
  String get setLeadScoreDialogTitle;

  /// No description provided for @leadScoreRangeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Score (0–100)'**
  String get leadScoreRangeFieldLabel;

  /// No description provided for @leadScoreFieldHelper.
  ///
  /// In en, this message translates to:
  /// **'This overrides the analyzer\'s number.'**
  String get leadScoreFieldHelper;

  /// No description provided for @setByEmployeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Set by {name}'**
  String setByEmployeeLabel(String name);

  /// No description provided for @aiGeneratedLabel.
  ///
  /// In en, this message translates to:
  /// **'AI-generated'**
  String get aiGeneratedLabel;

  /// No description provided for @analyzerOwnReadLabel.
  ///
  /// In en, this message translates to:
  /// **'Analyzer\'s own read: {score}'**
  String analyzerOwnReadLabel(int score);

  /// No description provided for @unconfirmedPurchaseClaimLabel.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed purchase claim'**
  String get unconfirmedPurchaseClaimLabel;

  /// No description provided for @confirmPurchaseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm this purchase?'**
  String get confirmPurchaseDialogTitle;

  /// No description provided for @rejectPurchaseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject this claim?'**
  String get rejectPurchaseDialogTitle;

  /// No description provided for @noteOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptionalLabel;

  /// No description provided for @notYetButton.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get notYetButton;

  /// No description provided for @purchaseConfirmedMessage.
  ///
  /// In en, this message translates to:
  /// **'Purchase confirmed'**
  String get purchaseConfirmedMessage;

  /// No description provided for @purchaseNotConfirmedMessage.
  ///
  /// In en, this message translates to:
  /// **'Recorded as not confirmed'**
  String get purchaseNotConfirmedMessage;

  /// No description provided for @purchaseHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase confirmation history'**
  String get purchaseHistoryTitle;

  /// No description provided for @purchaseHistoryLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the history.'**
  String get purchaseHistoryLoadError;

  /// No description provided for @purchaseHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rulings recorded yet.'**
  String get purchaseHistoryEmpty;

  /// No description provided for @notConfirmedBadge.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed'**
  String get notConfirmedBadge;

  /// No description provided for @anEmployeeLabel.
  ///
  /// In en, this message translates to:
  /// **'An employee'**
  String get anEmployeeLabel;

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Message templates'**
  String get templatesTitle;

  /// No description provided for @templatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pre-approved WhatsApp messages you can send outside the 24-hour window.'**
  String get templatesSubtitle;

  /// No description provided for @wabaAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Business account'**
  String get wabaAccountLabel;

  /// No description provided for @templatesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 template on this account} other{{count} templates on this account}}'**
  String templatesCount(int count);

  /// No description provided for @refreshAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshAction;

  /// No description provided for @createTemplateAction.
  ///
  /// In en, this message translates to:
  /// **'Create template'**
  String get createTemplateAction;

  /// No description provided for @templateNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get templateNameLabel;

  /// No description provided for @templateCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get templateCategoryLabel;

  /// No description provided for @templateLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get templateLanguageLabel;

  /// No description provided for @templateStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get templateStatusLabel;

  /// No description provided for @templateMetaIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Meta ID'**
  String get templateMetaIdLabel;

  /// No description provided for @noTemplatesFound.
  ///
  /// In en, this message translates to:
  /// **'No templates found'**
  String get noTemplatesFound;

  /// No description provided for @noTemplatesMessage.
  ///
  /// In en, this message translates to:
  /// **'No message templates have been created for this WhatsApp Business account.'**
  String get noTemplatesMessage;

  /// No description provided for @noWabaAccounts.
  ///
  /// In en, this message translates to:
  /// **'No WhatsApp accounts connected'**
  String get noWabaAccounts;

  /// No description provided for @noWabaAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'Connect a WhatsApp Business account in Settings to manage message templates.'**
  String get noWabaAccountsMessage;

  /// No description provided for @createTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create message template'**
  String get createTemplateTitle;

  /// No description provided for @createTemplateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Submit a new WhatsApp message template for Meta review.'**
  String get createTemplateSubtitle;

  /// No description provided for @templateNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letters, numbers, and underscores only'**
  String get templateNameHelper;

  /// No description provided for @templateBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Message body'**
  String get templateBodyLabel;

  /// No description provided for @templateBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the template message text. You can include variables.'**
  String get templateBodyHint;

  /// No description provided for @submitForReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get submitForReviewAction;

  /// No description provided for @templateSubmittedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Template submitted for review'**
  String get templateSubmittedSnackbar;

  /// No description provided for @templateInvalidNameError.
  ///
  /// In en, this message translates to:
  /// **'Template name must use lowercase letters, numbers and underscores only.'**
  String get templateInvalidNameError;

  /// No description provided for @templateEmptyBodyError.
  ///
  /// In en, this message translates to:
  /// **'Template body cannot be empty.'**
  String get templateEmptyBodyError;

  /// No description provided for @templateRejectedReason.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason: {reason}'**
  String templateRejectedReason(String reason);

  /// No description provided for @templateUnsupportedNotice.
  ///
  /// In en, this message translates to:
  /// **'Unsupported components: {components}'**
  String templateUnsupportedNotice(String components);

  /// No description provided for @loadingTemplates.
  ///
  /// In en, this message translates to:
  /// **'Loading templates…'**
  String get loadingTemplates;

  /// No description provided for @noTemplatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No templates available'**
  String get noTemplatesAvailable;

  /// No description provided for @groupedConversationsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 conversation} other{{count} conversations}}'**
  String groupedConversationsCount(int count);

  /// No description provided for @selectConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Select conversation'**
  String get selectConversationTitle;

  /// No description provided for @selectConversationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Available WhatsApp conversations for this customer'**
  String get selectConversationSubtitle;

  /// No description provided for @switchConversationAction.
  ///
  /// In en, this message translates to:
  /// **'Switch conversation'**
  String get switchConversationAction;

  /// No description provided for @openConversationAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openConversationAction;

  /// No description provided for @currentConversationBadge.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentConversationBadge;

  /// No description provided for @whatsappConversationsGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp conversations'**
  String get whatsappConversationsGroupTitle;
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
