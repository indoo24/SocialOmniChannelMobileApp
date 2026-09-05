// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get newActivityBannerTitle => 'New activity';

  @override
  String get tabChannels => 'Channels';

  @override
  String get tabProfile => 'Profile';

  @override
  String get tabSecurity => 'Security';

  @override
  String get tabAssignment => 'Assignment';

  @override
  String get signOutDialogTitle => 'Sign out?';

  @override
  String get signOutDialogMessage =>
      'You will stop receiving new conversations on this device.';

  @override
  String get cancel => 'Cancel';

  @override
  String get signOut => 'Sign out';

  @override
  String get availabilitySectionTitle => 'AVAILABILITY';

  @override
  String get availabilityHint =>
      'Only ONLINE receives automatically assigned conversations.';

  @override
  String get availabilityOnline => 'Online';

  @override
  String get availabilityAway => 'Away';

  @override
  String get availabilityOnBreak => 'On break';

  @override
  String get availabilityOffline => 'Offline';

  @override
  String get organizationLabel => 'Organization';

  @override
  String visibilityLabel(String scope) {
    return 'Visibility: $scope';
  }

  @override
  String get preferencesSectionTitle => 'PREFERENCES';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageLabel => 'Language';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get currentPasswordLabel => 'Current password';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get newPasswordHint => 'At least 10 characters';

  @override
  String get passwordChangedMessage => 'Password changed';

  @override
  String get updatePasswordButton => 'Update password';

  @override
  String get sessionInfoTitle => 'How your session works';

  @override
  String get sessionInfoBody =>
      'This app signs in with an httpOnly session cookie, the same credential the web client uses. Platform tokens for Meta and WhatsApp stay encrypted on the server and are never sent to this device.';

  @override
  String get noChannelsTitle => 'No channels connected';

  @override
  String get noChannelsMessage =>
      'Connect Instagram, Messenger or WhatsApp from the web app to start receiving conversations.';

  @override
  String get channelStatusConnected => 'Connected';

  @override
  String get channelStatusDegraded => 'Degraded';

  @override
  String get channelStatusError => 'Error';

  @override
  String get channelStatusDisconnected => 'Disconnected';

  @override
  String get channelStatusPending => 'Pending setup';

  @override
  String channelConversationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations',
      one: '1 conversation',
    );
    return '$_temp0';
  }

  @override
  String get muteChannelAction => 'Mute';

  @override
  String get unmuteChannelAction => 'Unmute';

  @override
  String get testChannelAction => 'Test';

  @override
  String get channelMutedLabel => 'Muted';

  @override
  String channelMutedByLabel(String name) {
    return 'Muted by $name';
  }

  @override
  String get hideChannelAction => 'Hide';

  @override
  String get showChannelAction => 'Show';

  @override
  String hiddenChannelsSectionTitle(int count) {
    return 'Hidden ($count)';
  }

  @override
  String get disconnectChannelAction => 'Disconnect';

  @override
  String get reconnectChannelAction => 'Reconnect';

  @override
  String get checkStatusChannelAction => 'Check status';

  @override
  String get connectAnotherNumberAction => 'Connect another number';

  @override
  String get connectAnotherAccountAction => 'Connect another account';

  @override
  String get moreActionsTooltip => 'More actions';

  @override
  String channelIdentifierLabel(String value) {
    return 'ID: $value';
  }

  @override
  String channelConnectedLabel(String when) {
    return 'Connected $when';
  }

  @override
  String channelLastActivityLabel(String when) {
    return 'Last activity $when';
  }

  @override
  String get channelNoActivityLabel => 'No activity yet';

  @override
  String disconnectChannelDialogTitle(String channel) {
    return 'Disconnect $channel?';
  }

  @override
  String get disconnectChannelDialogBody =>
      'This removes the stored credential. The conversation history stays, but no new messages can be sent or received on this channel until it\'s reconnected.';

  @override
  String channelDisconnectedSnackbar(String channel) {
    return '$channel disconnected.';
  }

  @override
  String get openingBrowserMessage => 'Opening browser…';

  @override
  String get couldNotOpenBrowserError =>
      'Couldn\'t open the browser for this connection.';

  @override
  String get manageFromWebOnlyAction => 'Manage from web';

  @override
  String get manageFromWebOnlyHint =>
      'This action is only available from the web app.';

  @override
  String get updateTokenAction => 'Update token';

  @override
  String get updateTokenSheetTitle => 'Update access token';

  @override
  String get updateTokenSheetDescription =>
      'Replace this number\'s access token if it expired or was regenerated in the Meta dashboard.';

  @override
  String get otherWaysToConnectSection => 'Other ways to connect';

  @override
  String get addAnotherNumberAction => 'Add another number';

  @override
  String get addAnotherNumberHint => 'via phone number ID and access token';

  @override
  String get addAnotherNumberSheetTitle => 'Add a WhatsApp number';

  @override
  String get useInstagramTokenAction => 'Use Instagram token';

  @override
  String get useInstagramTokenSheetTitle => 'Connect with an Instagram token';

  @override
  String get useInstagramTokenSheetDescription =>
      'Paste an Instagram user token generated from Meta\'s dashboard. This attaches the account the token identifies.';

  @override
  String get manageFacebookPagesAction => 'Manage Facebook Pages';

  @override
  String get phoneNumberIdFieldLabel => 'Phone number ID';

  @override
  String get accessTokenFieldLabel => 'Access token';

  @override
  String get wabaIdFieldLabel => 'WhatsApp Business Account ID';

  @override
  String get wabaIdFieldOptionalHint =>
      'Optional — derived from the token when left blank.';

  @override
  String get instagramTokenFieldLabel => 'Instagram access token';

  @override
  String get fieldRequiredError => 'This field is required.';

  @override
  String channelConnectedSnackbar(String channel) {
    return '$channel connected.';
  }

  @override
  String get channelTokenUpdatedSnackbar => 'Access token updated.';

  @override
  String get connectAction => 'Connect';

  @override
  String get updateAction => 'Update';

  @override
  String get noConnectionTitle => 'No connection';

  @override
  String get genericErrorTitle => 'Something went wrong';

  @override
  String get genericErrorFallbackMessage => 'Please try again.';

  @override
  String get retryButton => 'Try again';

  @override
  String get commonSave => 'Save';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonCloseSearch => 'Close search';

  @override
  String get timeNow => 'now';

  @override
  String get dayToday => 'Today';

  @override
  String get dayYesterday => 'Yesterday';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navInbox => 'Inbox';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navEmployees => 'Employees';

  @override
  String get navTeams => 'Teams';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navTemplates => 'Templates';

  @override
  String get navSettings => 'Settings';

  @override
  String get noAccessTitle => 'You don\'t have access';

  @override
  String noAccessMessage(String section) {
    return 'Your role does not include $section. Ask an administrator if you need it.';
  }

  @override
  String get reconnecting => 'Reconnecting…';

  @override
  String get notFoundTitle => 'Not found';

  @override
  String get notFoundMessage => 'That screen does not exist.';

  @override
  String get backToInbox => 'Back to inbox';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInSubtitle => 'Use your Scenario employee account.';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailHint => 'you@company.com';

  @override
  String get emailValidationError => 'Enter your email address.';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordValidationError => 'Enter your password.';

  @override
  String get signInButton => 'Sign in';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String get searchConversationsHint => 'Search conversations';

  @override
  String get filtersTooltip => 'Filters';

  @override
  String get noConversationsTitle => 'No conversations yet';

  @override
  String get noConversationsMessage =>
      'New customer messages will appear here as they arrive.';

  @override
  String get noFilterMatchesTitle => 'Nothing matches those filters';

  @override
  String get noFilterMatchesMessage => 'Try widening or clearing the filters.';

  @override
  String get clearFiltersButton => 'Clear filters';

  @override
  String get noMessagesYetPreview => 'No messages yet';

  @override
  String get unassignedBadge => 'Unassigned';

  @override
  String get youBadge => 'You';

  @override
  String get filtersTitle => 'Filters';

  @override
  String get clearAll => 'Clear all';

  @override
  String get assignmentSection => 'Assignment';

  @override
  String get assignedToMeFilter => 'Assigned to me';

  @override
  String get unassignedFilter => 'Unassigned';

  @override
  String get statusSection => 'Status';

  @override
  String get prioritySection => 'Priority';

  @override
  String get categorySection => 'Category';

  @override
  String get channelSection => 'Channel';

  @override
  String get showResultsButton => 'Show results';

  @override
  String get statusNew => 'New';

  @override
  String get statusOpen => 'Open';

  @override
  String get statusWaitingCustomer => 'Waiting on customer';

  @override
  String get statusWaitingInternal => 'Waiting internally';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get statusClosed => 'Closed';

  @override
  String get priorityUrgent => 'Urgent';

  @override
  String get priorityHigh => 'High';

  @override
  String get priorityNormal => 'Normal';

  @override
  String get priorityLow => 'Low';

  @override
  String get providerWhatsapp => 'WhatsApp';

  @override
  String get providerFacebook => 'Messenger';

  @override
  String get providerInstagram => 'Instagram';

  @override
  String get providerTiktok => 'TikTok';

  @override
  String get providerSandbox => 'Sandbox';

  @override
  String get actionsTitle => 'Actions';

  @override
  String get assignToMe => 'Assign to me';

  @override
  String get assignedToYouMessage => 'Assigned to you';

  @override
  String get unassignAction => 'Unassign';

  @override
  String get unassignedMessage => 'Unassigned';

  @override
  String get statusUpdatedMessage => 'Status updated';

  @override
  String get priorityUpdatedMessage => 'Priority updated';

  @override
  String get categoryUpdatedMessage => 'Category updated';

  @override
  String get categoryNoneOption => 'Uncategorized';

  @override
  String get noPermissionToChange =>
      'You do not have permission to change this conversation.';

  @override
  String get conversationHistoryAction => 'View history';

  @override
  String get conversationHistoryTitle => 'History';

  @override
  String get conversationHistoryEmpty => 'No activity recorded yet.';

  @override
  String get conversionsAction => 'Conversions';

  @override
  String get conversionsEmpty => 'Nothing reported to Meta yet.';

  @override
  String get reportConversionAction => 'Report now';

  @override
  String conversionsTruncatedNote(int shown, int total) {
    return 'Showing the most recent $shown of $total.';
  }

  @override
  String get internalNotesAction => 'Internal notes';

  @override
  String get internalNotesTitle => 'Internal notes';

  @override
  String get internalNotesEmpty => 'No internal notes yet.';

  @override
  String get internalNoteInputHint => 'Add a note for your team…';

  @override
  String get addNoteAction => 'Add note';

  @override
  String get replyTab => 'Reply';

  @override
  String get internalNoteTab => 'Internal note';

  @override
  String get templateTab => 'Template';

  @override
  String get notVisibleToCustomer => 'Not visible to customer';

  @override
  String get notSentToCustomer => 'Not sent to the customer';

  @override
  String get saveNote => 'Save note';

  @override
  String get approvedTemplate => 'Approved template';

  @override
  String get chooseTemplate => 'Choose a template…';

  @override
  String get sendTemplate => 'Send template';

  @override
  String get conversationFallbackTitle => 'Conversation';

  @override
  String get customerDetailsTooltip => 'Customer details';

  @override
  String get actionsTooltip => 'Actions';

  @override
  String get ordersTooltip => 'Orders and customer details';

  @override
  String get intelligenceTooltip => 'Conversation intelligence';

  @override
  String get followUpTooltip => 'Follow up';

  @override
  String get markFollowUpTitle => 'Follow up';

  @override
  String get editFollowUpTitle => 'Edit follow-up';

  @override
  String get followUpSwitchLabel => 'Mark as follow-up';

  @override
  String get followUpDateLabel => 'Follow-up date';

  @override
  String get noFollowUpDate => 'No date set';

  @override
  String get clearDate => 'Clear date';

  @override
  String get removeFollowUp => 'Remove follow-up';

  @override
  String get saveFollowUp => 'Save';

  @override
  String get followUpUpdatedMessage => 'Follow-up updated';

  @override
  String get followUpClearedMessage => 'Follow-up removed';

  @override
  String get selectDate => 'Select date';

  @override
  String get loadingConversation => 'Loading conversation…';

  @override
  String get noMessagesYetTitle => 'No messages yet';

  @override
  String get noMessagesYetMessage => 'This conversation has no history.';

  @override
  String get writeReplyHint => 'Write a reply…';

  @override
  String get readOnlyLabel => 'Read only';

  @override
  String get attachmentTooltip => 'Attach';

  @override
  String get attachFromGalleryAction => 'Photo from gallery';

  @override
  String get attachFromCameraAction => 'Take photo';

  @override
  String get removeAttachmentTooltip => 'Remove attachment';

  @override
  String get attachmentUploadingLabel => 'Uploading…';

  @override
  String get attachmentUploadFailedError =>
      'Couldn\'t upload that file. Please try again.';

  @override
  String get attachmentPermissionDeniedError =>
      'Permission was denied. Enable it in your device settings to attach photos.';

  @override
  String get recordVoiceTooltip => 'Record a voice message';

  @override
  String recordingLabel(String duration) {
    return 'Recording $duration';
  }

  @override
  String get cancelRecordingTooltip => 'Cancel recording';

  @override
  String get stopRecordingTooltip => 'Stop and send';

  @override
  String get microphonePermissionDeniedError =>
      'Microphone access was denied. Enable it in your device settings to record a voice message.';

  @override
  String get recordingFailedError =>
      'Couldn\'t start recording. Please try again.';

  @override
  String get voiceMessageLabel => 'Voice message';

  @override
  String get voiceNoteLabel => 'Voice note';

  @override
  String get recordingText => 'Recording';

  @override
  String get playVoiceMessageTooltip => 'Play voice message';

  @override
  String get pauseVoiceMessageTooltip => 'Pause voice message';

  @override
  String get voiceMessagePlaybackFailedError =>
      'Couldn\'t play this voice message.';

  @override
  String get imageLoadFailedLabel => 'Couldn\'t load image';

  @override
  String get notDeliveredFallback => 'Not delivered.';

  @override
  String get discardAction => 'Discard';

  @override
  String get retryMessageAction => 'Retry';

  @override
  String get deleteMessageAction => 'Delete message';

  @override
  String get deleteMessageConfirmTitle => 'Delete this message?';

  @override
  String get deleteMessageConfirmBody =>
      'This removes it from the timeline for everyone. It does not unsend it on the platform — the customer still has it.';

  @override
  String get deleteMessageReasonLabel => 'Reason (optional)';

  @override
  String get deleteMessageDeletedSnackbar => 'Message deleted';

  @override
  String get customerTitle => 'Customer';

  @override
  String get conversationSectionTitle => 'Conversation';

  @override
  String get categoryFieldLabel => 'Category';

  @override
  String get assignedToFieldLabel => 'Assigned to';

  @override
  String get teamFieldLabel => 'Team';

  @override
  String get channelFieldLabel => 'Channel';

  @override
  String get messagesFieldLabel => 'Messages';

  @override
  String get startedFieldLabel => 'Started';

  @override
  String get lastMessageFieldLabel => 'Last message';

  @override
  String get customerSectionTitle => 'Customer';

  @override
  String get lifecycleFieldLabel => 'Lifecycle';

  @override
  String get intelligenceSectionTitle => 'Intelligence';

  @override
  String get stageFieldLabel => 'Stage';

  @override
  String get leadScoreFieldLabel => 'Lead score';

  @override
  String get purchaseFieldLabel => 'Purchase';

  @override
  String get reviewFieldLabel => 'Review';

  @override
  String get needsHumanReviewValue => 'Needs human review';

  @override
  String dashboardGreeting(String name) {
    return 'Good to see you, $name';
  }

  @override
  String get conversationsSectionTitle => 'Conversations';

  @override
  String get openMetric => 'Open';

  @override
  String get waitingMetric => 'Waiting';

  @override
  String get resolvedTodayMetric => 'Resolved today';

  @override
  String get customerIntelligenceSectionTitle => 'Customer intelligence';

  @override
  String get qualifiedLeadsMetric => 'Qualified leads';

  @override
  String get hotLeadsMetric => 'Hot leads';

  @override
  String get purchaseClaimsMetric => 'Purchase claims';

  @override
  String get purchaseClaimsHint => 'Said they ordered. Not verified.';

  @override
  String get confirmedMetric => 'Confirmed';

  @override
  String get confirmedHint => 'Checked by an employee.';

  @override
  String reviewNeededMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations need review',
      one: '1 conversation needs review',
    );
    return '$_temp0';
  }

  @override
  String get reviewNeededDescription =>
      'A customer claimed a purchase. Scenario cannot verify payments — check your records and confirm.';

  @override
  String get checkInboxButton => 'Check Inbox';

  @override
  String get myLast14DaysTitle => 'Your last 14 days';

  @override
  String get teamWorkloadTitle => 'Team workload';

  @override
  String onlineAgentsSuffix(int count) {
    return '$count online';
  }

  @override
  String get nothingAssignedMessage => 'Nothing assigned right now.';

  @override
  String get recentActivityTitle => 'Recent activity';

  @override
  String get openInboxButton => 'Open inbox';

  @override
  String get noRecentActivityMessage => 'No recent activity yet.';

  @override
  String get stageNewLead => 'New lead';

  @override
  String get stageQualifiedLead => 'Qualified lead';

  @override
  String get stageHotLead => 'Hot lead';

  @override
  String get stagePurchaseIntent => 'Purchase intent';

  @override
  String get stagePurchased => 'Purchased';

  @override
  String get stageLost => 'Lost';

  @override
  String get stageDisqualified => 'Disqualified';

  @override
  String get profileDetailsSectionTitle => 'Personal details';

  @override
  String get jobTitleFieldLabel => 'Job title';

  @override
  String get saveProfileButton => 'Save profile';

  @override
  String get profileUpdatedSnackbar => 'Profile updated';

  @override
  String get profileFirstNameRequiredError => 'First name cannot be empty.';

  @override
  String get autoAssignmentTitle => 'Automatic conversation assignment';

  @override
  String get autoAssignmentDescription =>
      'Automatically routes incoming conversations to available agents based on workload and schedule. Affects new allocatable work only.';

  @override
  String get autoAssignmentStatusActive => 'Active';

  @override
  String get autoAssignmentStatusInactive => 'Disabled';

  @override
  String get autoAssignmentToggleLabel => 'Enable automatic assignment';

  @override
  String get defaultChatCapacityTitle => 'Default chat capacity';

  @override
  String get defaultChatCapacityDescription =>
      'Maximum open conversations assigned to an agent at one time.';

  @override
  String get maxOpenChatsFieldLabel => 'Max open chats';

  @override
  String get maxOpenChatsInvalidError => 'Enter a valid number greater than 0.';

  @override
  String get saveCapacityAction => 'Save capacity';

  @override
  String get timezoneTitle => 'Time zone';

  @override
  String get timezoneDescription =>
      'Organization-level time zone. Changing this reinterprets existing schedules without rewriting them.';

  @override
  String get timezoneFieldLabel => 'Select time zone';

  @override
  String get saveTimezoneAction => 'Save time zone';

  @override
  String get assignmentPolicyUpdatedSnackbar => 'Assignment settings updated';

  @override
  String get routingPolicyLoadFailed => 'Couldn\'t load assignment settings.';

  @override
  String get routingPermissionDenied =>
      'You don\'t have permission to manage assignment settings.';

  @override
  String openUnreadSummary(int open, int unread) {
    return '$open open · $unread unread';
  }

  @override
  String openSummary(int open) {
    return '$open open';
  }

  @override
  String get analyticsInfoBanner =>
      'Computed live from the conversation database. Historical trends need a metrics rollup.';

  @override
  String get volumeByChannelTitle => 'Volume by channel';

  @override
  String get noConversationsRecorded => 'No conversations recorded yet.';

  @override
  String get leadPipelineTitle => 'Lead pipeline';

  @override
  String get qualifiedMetric => 'Qualified';

  @override
  String get avgScoreMetric => 'Avg score';

  @override
  String get awaitingReviewMetric => 'Awaiting review';

  @override
  String get purchaseEvidenceTitle => 'Purchase evidence';

  @override
  String get unverifiedClaimsLabel => 'Unverified customer claims';

  @override
  String get unverifiedClaimsNote =>
      'Customers who said they ordered or paid. Scenario has no payment data and cannot verify these.';

  @override
  String get employeeConfirmedLabel => 'Employee-confirmed';

  @override
  String employeeConfirmedNoteWithCount(int count) {
    return 'A team member checked their own records. $count today.';
  }

  @override
  String get employeeConfirmedNote =>
      'A team member checked their own records and confirmed.';

  @override
  String get scopedToVisibleConversations =>
      'Scoped to the conversations you can see.';

  @override
  String get employeePerformanceTitle => 'Employee performance';

  @override
  String get nobodyHandledMessage =>
      'Nobody handled a conversation in this window.';

  @override
  String totalOpenSuffix(int total, int open) {
    return '$total total · $open open';
  }

  @override
  String get emailFieldLabel => 'Email';

  @override
  String get phoneFieldLabel => 'Phone';

  @override
  String get locationFieldLabel => 'Location';

  @override
  String get lastSeenFieldLabel => 'Last seen';

  @override
  String get confirmedPurchasesFieldLabel => 'Confirmed purchases';

  @override
  String get customerNotesFieldLabel => 'Notes';

  @override
  String get recordedDetailsSectionTitle => 'Recorded details';

  @override
  String get conversationsCapsSectionTitle => 'CONVERSATIONS';

  @override
  String get noVisibleConversations => 'No conversations you can see.';

  @override
  String get searchCustomersHint => 'Search name, email, phone or handle';

  @override
  String get noCustomersTitle => 'No customers';

  @override
  String get noCustomersMessage =>
      'Customers appear the first time they message you.';

  @override
  String chatCountBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats',
      one: '1 chat',
    );
    return '$_temp0';
  }

  @override
  String get searchEmployeesHint => 'Search by name or email';

  @override
  String get onlineNowFilter => 'Online now';

  @override
  String totalCountSuffix(int total) {
    return '$total total';
  }

  @override
  String get nobodyOnlineTitle => 'Nobody is online';

  @override
  String get turnOffFilterMessage => 'Turn off the filter to see everyone.';

  @override
  String get noEmployeesFoundTitle => 'No employees found';

  @override
  String get tryDifferentSearchMessage => 'Try a different search term.';

  @override
  String get inactiveBadge => 'Inactive';

  @override
  String get noTeamsTitle => 'No teams yet';

  @override
  String get noTeamsMessage =>
      'Teams group agents so conversations can be routed and monitored together.';

  @override
  String memberCountBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String ledByLabel(String names) {
    return 'Led by $names';
  }

  @override
  String get suggestedFromChatTitle => 'Suggested from this chat';

  @override
  String get suggestedFromChatDescription =>
      'Read out of the conversation automatically. Nothing here is saved to the customer until you accept it.';

  @override
  String get customerDetailsTitle => 'Customer details';

  @override
  String get nothingRecordedMessage =>
      'Nothing recorded yet. Anything the customer shares — an address, a phone number — can be saved here.';

  @override
  String get ordersTitle => 'Orders';

  @override
  String get orderButton => 'Order';

  @override
  String get noOrdersRecordedMessage =>
      'No orders recorded from this conversation.';

  @override
  String get employeeSourceBadge => 'Employee';

  @override
  String get autoSourceBadge => 'Auto';

  @override
  String get saveToCustomerTooltip => 'Save to the customer';

  @override
  String get dismissSuggestionTooltip =>
      'Dismiss — it won\'t be suggested again';

  @override
  String confidenceLabel(int percent) {
    return '$percent% confidence';
  }

  @override
  String get tapToCorrectHint => 'tap to correct';

  @override
  String confidenceWithCorrectHintLabel(int percent) {
    return '$percent% confidence · tap to correct';
  }

  @override
  String get savedToCustomerMessage => 'Saved to the customer';

  @override
  String get suggestionDismissedMessage => 'Suggestion dismissed';

  @override
  String get recordDetailDialogTitle => 'Record a customer detail';

  @override
  String get recordDetailDescription =>
      'Something the customer shared — an address, a phone number, a preference.';

  @override
  String get detailFieldLabel => 'Detail';

  @override
  String get detailFieldHint => 'address';

  @override
  String get valueFieldLabel => 'Value';

  @override
  String get valueFieldHint => '12 Nile St, Giza';

  @override
  String get removeLineTooltip => 'Remove line';

  @override
  String get atLeastOneProductError => 'Enter at least one product name.';

  @override
  String get validPriceError => 'Enter a valid price.';

  @override
  String get detailRequiredError => 'Enter both detail and value.';

  @override
  String get confirmAction => 'Confirm';

  @override
  String get orderConfirmedMessage => 'Order confirmed';

  @override
  String get cancelOrderTooltip => 'Cancel this order';

  @override
  String get orderCancelledMessage => 'Order cancelled';

  @override
  String get cancelOrderConfirmTitle => 'Cancel this order?';

  @override
  String get cancelOrderConfirmBody =>
      'This won\'t be counted as a sale. You can\'t undo this from here.';

  @override
  String get keepOrderAction => 'Keep order';

  @override
  String get notCountedAsSaleMessage =>
      'Not counted as a sale until someone confirms it.';

  @override
  String confirmedByMessage(String name) {
    return 'Confirmed by $name';
  }

  @override
  String get confirmedByUnknownEmployee => 'an employee';

  @override
  String recordedByMessage(String name) {
    return 'Recorded by $name';
  }

  @override
  String get recordOrderDialogTitle => 'Record an order';

  @override
  String get orderComposerDescription =>
      'What the customer asked for. Scenario has no payment data, so this is a record of the conversation, not a receipt.';

  @override
  String get productFieldLabel => 'Product';

  @override
  String get qtyFieldLabel => 'Qty';

  @override
  String get priceFieldLabel => 'Price';

  @override
  String get addLineButton => 'Add line';

  @override
  String get totalLabel => 'Total';

  @override
  String get recordOrderButton => 'Record an order';

  @override
  String get orderRecordedMessage =>
      'Order recorded. Confirm it once you\'ve checked your own records.';

  @override
  String get avgResponseLabel => 'Avg response';

  @override
  String repliesCountedHint(int count, String median) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies',
      one: '1 reply',
    );
    return '$_temp0 · median $median';
  }

  @override
  String get noRepliesYetHint => 'No replies yet';

  @override
  String get noBaselineRecorded => 'No baseline recorded';

  @override
  String get customersLabel => 'Customers';

  @override
  String messagesSentHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0 sent';
  }

  @override
  String get confirmedOrdersLabel => 'Confirmed orders';

  @override
  String confirmedOrderValueHint(String amount, String currency) {
    return '$amount $currency';
  }

  @override
  String recordedNoneConfirmedHint(int count) {
    return '$count recorded, none confirmed';
  }

  @override
  String get byPlatformSectionTitle => 'BY PLATFORM';

  @override
  String handledFootnote(int count) {
    return '$count handled';
  }

  @override
  String resolvedFootnote(int count) {
    return '$count resolved';
  }

  @override
  String firstReplyFootnote(String duration) {
    return 'First reply $duration';
  }

  @override
  String get hoursSectionTitle => 'HOURS';

  @override
  String get hoursNotRecorded => 'Not recorded for this period.';

  @override
  String adherenceBadge(int percent) {
    return '$percent% adherence';
  }

  @override
  String get onlineHoursLabel => 'Online';

  @override
  String get scheduledHoursLabel => 'Scheduled';

  @override
  String get noShiftsSetMessage => 'No shifts set';

  @override
  String msgCustomersHint(int messages, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers',
      one: '1 customer',
    );
    return '$messages msg · $_temp0';
  }

  @override
  String get misconfiguredTitle => 'No API host configured';

  @override
  String get misconfiguredMessage =>
      'Build with --dart-define=SCENARIO_API_HOST=host:port';

  @override
  String get editAction => 'Edit';

  @override
  String get deactivateAction => 'Deactivate';

  @override
  String get editCustomerTitle => 'Edit customer';

  @override
  String get customerUpdatedSnackbar => 'Customer updated';

  @override
  String get displayNameFieldLabel => 'Display name';

  @override
  String get cityFieldLabel => 'City';

  @override
  String get countryFieldLabel => 'Country';

  @override
  String get tagsFieldLabel => 'Tags';

  @override
  String get addEmployeeTitle => 'Add employee';

  @override
  String get editEmployeeTitle => 'Edit employee';

  @override
  String get employeeAddedSnackbar => 'Employee added';

  @override
  String get employeeUpdatedSnackbar => 'Employee updated';

  @override
  String get employeeFormRequiredFieldsError =>
      'Enter an email, first name and last name.';

  @override
  String get employeeFormPasswordRequiredError =>
      'Enter a password for the new employee.';

  @override
  String get firstNameFieldLabel => 'First name';

  @override
  String get lastNameFieldLabel => 'Last name';

  @override
  String get roleFieldLabel => 'Role';

  @override
  String get employeeTitleFieldLabel => 'Title';

  @override
  String get avatarUrlFieldLabel => 'Avatar URL';

  @override
  String get newPasswordOptionalFieldLabel =>
      'New password (leave blank to keep current)';

  @override
  String get activeFieldLabel => 'Active';

  @override
  String get teamsFieldLabel => 'Teams';

  @override
  String get teamsLoadFailedMessage => 'Couldn\'t load teams.';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleSupervisor => 'Supervisor';

  @override
  String get roleTeamLeader => 'Team leader';

  @override
  String get roleQa => 'QA';

  @override
  String get roleAgent => 'Agent';

  @override
  String get deactivateEmployeeConfirmTitle => 'Deactivate employee?';

  @override
  String deactivateEmployeeConfirmBody(String name) {
    return '$name will no longer be able to sign in or receive conversations. Their history and past conversations are kept.';
  }

  @override
  String employeeDeactivatedSnackbar(String name) {
    return '$name deactivated';
  }

  @override
  String get addTeamTitle => 'Add team';

  @override
  String get editTeamTitle => 'Edit team';

  @override
  String get teamAddedSnackbar => 'Team added';

  @override
  String get teamUpdatedSnackbar => 'Team updated';

  @override
  String get addTeamNameRequiredError => 'Enter a team name.';

  @override
  String get teamNameFieldLabel => 'Team name';

  @override
  String get descriptionFieldLabel => 'Description';

  @override
  String get colorFieldLabel => 'Color';

  @override
  String get leadersFieldLabel => 'Leaders';

  @override
  String get membersFieldLabel => 'Members';

  @override
  String get employeesLoadFailedMessage => 'Couldn\'t load employees.';

  @override
  String get deactivateTeamConfirmTitle => 'Deactivate team?';

  @override
  String deactivateTeamConfirmBody(String name) {
    return '$name will no longer be available for routing conversations. Existing conversations and assignment history are kept.';
  }

  @override
  String teamDeactivatedSnackbar(String name) {
    return '$name deactivated';
  }

  @override
  String get rerunAnalysisTooltip => 'Re-run analysis';

  @override
  String get loadingIntelligenceLabel => 'Loading intelligence…';

  @override
  String get notAnalyzedYetTitle => 'Not analyzed yet';

  @override
  String get notAnalyzedYetMessage =>
      'This conversation has no intelligence read yet. It appears once the analyzer runs, automatically or on demand.';

  @override
  String get runAnalysisButton => 'Run analysis';

  @override
  String get reviewBannerDefaultReason =>
      'This conversation needs a human look.';

  @override
  String get intelligenceSummaryLabel => 'Summary';

  @override
  String get suggestedNextStepLabel => 'Suggested next step';

  @override
  String get interestedInLabel => 'Interested in';

  @override
  String get buyingSignalsLabel => 'Buying signals';

  @override
  String get objectionsLabel => 'Objections';

  @override
  String lastAnalyzedLabel(String when) {
    return 'Last analyzed $when';
  }

  @override
  String get resetToAiButton => 'Reset to AI';

  @override
  String get setScoreByHandTooltip => 'Set score by hand';

  @override
  String get handedBackToAnalyzerMessage => 'Handed back to the analyzer';

  @override
  String get leadScoreUpdatedMessage => 'Lead score updated';

  @override
  String get setLeadScoreDialogTitle => 'Set the lead score';

  @override
  String get leadScoreRangeFieldLabel => 'Score (0–100)';

  @override
  String get leadScoreFieldHelper => 'This overrides the analyzer\'s number.';

  @override
  String setByEmployeeLabel(String name) {
    return 'Set by $name';
  }

  @override
  String get aiGeneratedLabel => 'AI-generated';

  @override
  String analyzerOwnReadLabel(int score) {
    return 'Analyzer\'s own read: $score';
  }

  @override
  String get unconfirmedPurchaseClaimLabel => 'Unconfirmed purchase claim';

  @override
  String get confirmPurchaseDialogTitle => 'Confirm this purchase?';

  @override
  String get rejectPurchaseDialogTitle => 'Reject this claim?';

  @override
  String get noteOptionalLabel => 'Note (optional)';

  @override
  String get notYetButton => 'Not yet';

  @override
  String get purchaseConfirmedMessage => 'Purchase confirmed';

  @override
  String get purchaseNotConfirmedMessage => 'Recorded as not confirmed';

  @override
  String get purchaseHistoryTitle => 'Purchase confirmation history';

  @override
  String get purchaseHistoryLoadError => 'Could not load the history.';

  @override
  String get purchaseHistoryEmpty => 'No rulings recorded yet.';

  @override
  String get notConfirmedBadge => 'Not confirmed';

  @override
  String get anEmployeeLabel => 'An employee';

  @override
  String get templatesTitle => 'Message templates';

  @override
  String get templatesSubtitle =>
      'Pre-approved WhatsApp messages you can send outside the 24-hour window.';

  @override
  String get wabaAccountLabel => 'WhatsApp Business account';

  @override
  String templatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count templates on this account',
      one: '1 template on this account',
    );
    return '$_temp0';
  }

  @override
  String get refreshAction => 'Refresh';

  @override
  String get createTemplateAction => 'Create template';

  @override
  String get templateNameLabel => 'Name';

  @override
  String get templateCategoryLabel => 'Category';

  @override
  String get templateLanguageLabel => 'Language';

  @override
  String get templateStatusLabel => 'Status';

  @override
  String get templateMetaIdLabel => 'Meta ID';

  @override
  String get noTemplatesFound => 'No templates found';

  @override
  String get noTemplatesMessage =>
      'No message templates have been created for this WhatsApp Business account.';

  @override
  String get noWabaAccounts => 'No WhatsApp accounts connected';

  @override
  String get noWabaAccountsMessage =>
      'Connect a WhatsApp Business account in Settings to manage message templates.';

  @override
  String get createTemplateTitle => 'Create message template';

  @override
  String get createTemplateSubtitle =>
      'Submit a new WhatsApp message template for Meta review.';

  @override
  String get templateNameHelper =>
      'Lowercase letters, numbers, and underscores only';

  @override
  String get templateBodyLabel => 'Message body';

  @override
  String get templateBodyHint =>
      'Enter the template message text. You can include variables.';

  @override
  String get submitForReviewAction => 'Submit for review';

  @override
  String get templateSubmittedSnackbar => 'Template submitted for review';

  @override
  String get templateInvalidNameError =>
      'Template name must use lowercase letters, numbers and underscores only.';

  @override
  String get templateEmptyBodyError => 'Template body cannot be empty.';

  @override
  String templateRejectedReason(String reason) {
    return 'Rejection reason: $reason';
  }

  @override
  String templateUnsupportedNotice(String components) {
    return 'Unsupported components: $components';
  }

  @override
  String get loadingTemplates => 'Loading templates…';

  @override
  String get noTemplatesAvailable => 'No templates available';

  @override
  String groupedConversationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations',
      one: '1 conversation',
    );
    return '$_temp0';
  }

  @override
  String get selectConversationTitle => 'Select conversation';

  @override
  String get selectConversationSubtitle =>
      'Available WhatsApp conversations for this customer';

  @override
  String get switchConversationAction => 'Switch conversation';

  @override
  String get openConversationAction => 'Open';

  @override
  String get currentConversationBadge => 'Current';

  @override
  String get whatsappConversationsGroupTitle => 'WhatsApp conversations';
}
