// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get tabChannels => 'القنوات';

  @override
  String get tabProfile => 'الملف الشخصي';

  @override
  String get tabSecurity => 'الأمان';

  @override
  String get signOutDialogTitle => 'تسجيل الخروج؟';

  @override
  String get signOutDialogMessage => 'لن تتلقى محادثات جديدة على هذا الجهاز.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get availabilitySectionTitle => 'الحالة';

  @override
  String get availabilityHint =>
      'يتم توزيع المحادثات تلقائيًا فقط على من هو متصل.';

  @override
  String get availabilityOnline => 'متصل';

  @override
  String get availabilityAway => 'غائب';

  @override
  String get availabilityOnBreak => 'في استراحة';

  @override
  String get availabilityOffline => 'غير متصل';

  @override
  String get organizationLabel => 'المؤسسة';

  @override
  String visibilityLabel(String scope) {
    return 'مستوى الرؤية: $scope';
  }

  @override
  String get preferencesSectionTitle => 'التفضيلات';

  @override
  String get themeLabel => 'المظهر';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get languageLabel => 'اللغة';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get currentPasswordLabel => 'كلمة المرور الحالية';

  @override
  String get newPasswordLabel => 'كلمة المرور الجديدة';

  @override
  String get newPasswordHint => '10 أحرف على الأقل';

  @override
  String get passwordChangedMessage => 'تم تغيير كلمة المرور';

  @override
  String get updatePasswordButton => 'تحديث كلمة المرور';

  @override
  String get sessionInfoTitle => 'كيف تعمل جلستك';

  @override
  String get sessionInfoBody =>
      'يسجّل هذا التطبيق الدخول باستخدام كوكي جلسة httpOnly، وهو نفس بيانات الاعتماد التي يستخدمها تطبيق الويب. تبقى رموز الوصول الخاصة بـ Meta وWhatsApp مشفّرة على الخادم ولا تُرسل أبدًا إلى هذا الجهاز.';

  @override
  String get noChannelsTitle => 'لا توجد قنوات متصلة';

  @override
  String get noChannelsMessage =>
      'قم بربط Instagram أو Messenger أو WhatsApp من تطبيق الويب لبدء استقبال المحادثات.';

  @override
  String get channelStatusConnected => 'متصل';

  @override
  String get channelStatusDegraded => 'أداء متدهور';

  @override
  String get channelStatusError => 'خطأ';

  @override
  String get channelStatusDisconnected => 'غير متصل';

  @override
  String get channelStatusPending => 'بانتظار الإعداد';

  @override
  String channelConversationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محادثة',
      many: '$count محادثة',
      few: '$count محادثات',
      two: 'محادثتان',
      one: 'محادثة واحدة',
      zero: 'بدون محادثات',
    );
    return '$_temp0';
  }

  @override
  String get noConnectionTitle => 'لا يوجد اتصال';

  @override
  String get genericErrorTitle => 'حدث خطأ ما';

  @override
  String get genericErrorFallbackMessage => 'يرجى المحاولة مرة أخرى.';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonAdd => 'إضافة';

  @override
  String get commonSearch => 'بحث';

  @override
  String get commonCloseSearch => 'إغلاق البحث';

  @override
  String get timeNow => 'الآن';

  @override
  String get dayToday => 'اليوم';

  @override
  String get dayYesterday => 'أمس';

  @override
  String get navDashboard => 'لوحة التحكم';

  @override
  String get navInbox => 'صندوق الوارد';

  @override
  String get navCustomers => 'العملاء';

  @override
  String get navEmployees => 'الموظفون';

  @override
  String get navTeams => 'الفرق';

  @override
  String get navAnalytics => 'التحليلات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get noAccessTitle => 'لا تملك صلاحية الوصول';

  @override
  String noAccessMessage(String section) {
    return 'دورك لا يشمل $section. اطلب من أحد المسؤولين إن كنت بحاجة إليه.';
  }

  @override
  String get reconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get notFoundTitle => 'غير موجود';

  @override
  String get notFoundMessage => 'هذه الشاشة غير موجودة.';

  @override
  String get backToInbox => 'العودة إلى صندوق الوارد';

  @override
  String get signInTitle => 'تسجيل الدخول';

  @override
  String get signInSubtitle => 'استخدم حساب الموظف الخاص بك في Scenario.';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get emailHint => 'you@company.com';

  @override
  String get emailValidationError => 'أدخل عنوان بريدك الإلكتروني.';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get passwordValidationError => 'أدخل كلمة المرور.';

  @override
  String get signInButton => 'تسجيل الدخول';

  @override
  String get inboxTitle => 'صندوق الوارد';

  @override
  String get searchConversationsHint => 'البحث في المحادثات';

  @override
  String get filtersTooltip => 'التصفية';

  @override
  String get noConversationsTitle => 'لا توجد محادثات بعد';

  @override
  String get noConversationsMessage =>
      'ستظهر رسائل العملاء الجديدة هنا فور وصولها.';

  @override
  String get noFilterMatchesTitle => 'لا توجد نتائج مطابقة لهذه الفلاتر';

  @override
  String get noFilterMatchesMessage => 'حاول توسيع الفلاتر أو مسحها.';

  @override
  String get clearFiltersButton => 'مسح الفلاتر';

  @override
  String get noMessagesYetPreview => 'لا توجد رسائل بعد';

  @override
  String get unassignedBadge => 'غير مُسنَدة';

  @override
  String get youBadge => 'أنت';

  @override
  String get filtersTitle => 'الفلاتر';

  @override
  String get clearAll => 'مسح الكل';

  @override
  String get assignmentSection => 'الإسناد';

  @override
  String get assignedToMeFilter => 'مُسندة إليّ';

  @override
  String get unassignedFilter => 'غير مُسندة';

  @override
  String get statusSection => 'الحالة';

  @override
  String get prioritySection => 'الأولوية';

  @override
  String get categorySection => 'الفئة';

  @override
  String get channelSection => 'القناة';

  @override
  String get showResultsButton => 'عرض النتائج';

  @override
  String get statusNew => 'جديدة';

  @override
  String get statusOpen => 'مفتوحة';

  @override
  String get statusWaitingCustomer => 'بانتظار العميل';

  @override
  String get statusWaitingInternal => 'بانتظار داخلي';

  @override
  String get statusResolved => 'تم الحل';

  @override
  String get statusClosed => 'مغلقة';

  @override
  String get priorityUrgent => 'عاجلة';

  @override
  String get priorityHigh => 'مرتفعة';

  @override
  String get priorityNormal => 'عادية';

  @override
  String get priorityLow => 'منخفضة';

  @override
  String get providerWhatsapp => 'واتساب';

  @override
  String get providerFacebook => 'ماسنجر';

  @override
  String get providerInstagram => 'إنستغرام';

  @override
  String get providerTiktok => 'تيك توك';

  @override
  String get providerSandbox => 'بيئة تجريبية';

  @override
  String get actionsTitle => 'الإجراءات';

  @override
  String get assignToMe => 'إسناد إليّ';

  @override
  String get assignedToYouMessage => 'تم الإسناد إليك';

  @override
  String get unassignAction => 'إلغاء الإسناد';

  @override
  String get unassignedMessage => 'تم إلغاء الإسناد';

  @override
  String get statusUpdatedMessage => 'تم تحديث الحالة';

  @override
  String get priorityUpdatedMessage => 'تم تحديث الأولوية';

  @override
  String get categoryUpdatedMessage => 'تم تحديث الفئة';

  @override
  String get categoryNoneOption => 'بدون فئة';

  @override
  String get noPermissionToChange => 'ليس لديك صلاحية تعديل هذه المحادثة.';

  @override
  String get conversationHistoryAction => 'عرض السجل';

  @override
  String get conversationHistoryTitle => 'السجل';

  @override
  String get conversationHistoryEmpty => 'لا يوجد نشاط مسجل بعد.';

  @override
  String get conversationFallbackTitle => 'المحادثة';

  @override
  String get customerDetailsTooltip => 'بيانات العميل';

  @override
  String get actionsTooltip => 'الإجراءات';

  @override
  String get ordersTooltip => 'الطلبات وبيانات العميل';

  @override
  String get intelligenceTooltip => 'ذكاء المحادثة';

  @override
  String get loadingConversation => 'جارٍ تحميل المحادثة…';

  @override
  String get noMessagesYetTitle => 'لا توجد رسائل بعد';

  @override
  String get noMessagesYetMessage => 'لا يوجد سجل لهذه المحادثة.';

  @override
  String get writeReplyHint => 'اكتب ردًا…';

  @override
  String get readOnlyLabel => 'للقراءة فقط';

  @override
  String get notDeliveredFallback => 'لم يتم التسليم.';

  @override
  String get discardAction => 'تجاهل';

  @override
  String get retryMessageAction => 'إعادة المحاولة';

  @override
  String get deleteMessageAction => 'حذف الرسالة';

  @override
  String get deleteMessageConfirmTitle => 'هل تريد حذف هذه الرسالة؟';

  @override
  String get deleteMessageConfirmBody =>
      'سيؤدي هذا إلى إزالتها من السجل للجميع. لن يتم إلغاء إرسالها على المنصة — ستظل لدى العميل.';

  @override
  String get deleteMessageReasonLabel => 'السبب (اختياري)';

  @override
  String get deleteMessageDeletedSnackbar => 'تم حذف الرسالة';

  @override
  String get customerTitle => 'العميل';

  @override
  String get conversationSectionTitle => 'المحادثة';

  @override
  String get categoryFieldLabel => 'الفئة';

  @override
  String get assignedToFieldLabel => 'مُسندة إلى';

  @override
  String get teamFieldLabel => 'الفريق';

  @override
  String get channelFieldLabel => 'القناة';

  @override
  String get messagesFieldLabel => 'الرسائل';

  @override
  String get startedFieldLabel => 'بدأت';

  @override
  String get lastMessageFieldLabel => 'آخر رسالة';

  @override
  String get customerSectionTitle => 'العميل';

  @override
  String get lifecycleFieldLabel => 'مرحلة دورة الحياة';

  @override
  String get intelligenceSectionTitle => 'الذكاء الاصطناعي';

  @override
  String get stageFieldLabel => 'المرحلة';

  @override
  String get leadScoreFieldLabel => 'نقاط العميل المحتمل';

  @override
  String get purchaseFieldLabel => 'الشراء';

  @override
  String get reviewFieldLabel => 'المراجعة';

  @override
  String get needsHumanReviewValue => 'بحاجة إلى مراجعة بشرية';

  @override
  String dashboardGreeting(String name) {
    return 'سعداء برؤيتك، $name';
  }

  @override
  String get conversationsSectionTitle => 'المحادثات';

  @override
  String get openMetric => 'مفتوحة';

  @override
  String get waitingMetric => 'بانتظار';

  @override
  String get resolvedTodayMetric => 'تم حلها اليوم';

  @override
  String get customerIntelligenceSectionTitle => 'ذكاء العملاء';

  @override
  String get qualifiedLeadsMetric => 'عملاء محتملون مؤهّلون';

  @override
  String get hotLeadsMetric => 'عملاء محتملون واعدون';

  @override
  String get purchaseClaimsMetric => 'ادعاءات شراء';

  @override
  String get purchaseClaimsHint => 'قالوا إنهم طلبوا. غير مؤكَّد.';

  @override
  String get confirmedMetric => 'مؤكَّد';

  @override
  String get confirmedHint => 'تم التحقق منه من قِبل موظف.';

  @override
  String reviewNeededMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محادثة بحاجة لمراجعة',
      many: '$count محادثة بحاجة لمراجعة',
      few: '$count محادثات بحاجة لمراجعة',
      two: 'محادثتان بحاجة لمراجعة',
      one: 'محادثة واحدة بحاجة لمراجعة',
      zero: 'لا توجد محادثات بحاجة لمراجعة',
    );
    return '$_temp0';
  }

  @override
  String get reviewNeededDescription =>
      'ادّعى أحد العملاء إتمام عملية شراء. لا تستطيع Scenario التحقق من المدفوعات — راجع سجلاتك وقم بالتأكيد.';

  @override
  String get checkInboxButton => 'تفقّد صندوق الوارد';

  @override
  String get myLast14DaysTitle => 'آخر 14 يومًا';

  @override
  String get teamWorkloadTitle => 'عبء عمل الفريق';

  @override
  String onlineAgentsSuffix(int count) {
    return '$count متصل';
  }

  @override
  String get nothingAssignedMessage => 'لا توجد مهام مُسندة حاليًا.';

  @override
  String openUnreadSummary(int open, int unread) {
    return '$open مفتوحة · $unread غير مقروءة';
  }

  @override
  String openSummary(int open) {
    return '$open مفتوحة';
  }

  @override
  String get analyticsInfoBanner =>
      'محسوبة مباشرة من قاعدة بيانات المحادثات. الاتجاهات التاريخية تتطلب تجميعًا للمقاييس.';

  @override
  String get volumeByChannelTitle => 'الحجم حسب القناة';

  @override
  String get noConversationsRecorded => 'لا توجد محادثات مسجَّلة بعد.';

  @override
  String get leadPipelineTitle => 'مسار العملاء المحتملين';

  @override
  String get qualifiedMetric => 'مؤهَّل';

  @override
  String get avgScoreMetric => 'متوسط النقاط';

  @override
  String get awaitingReviewMetric => 'بانتظار المراجعة';

  @override
  String get purchaseEvidenceTitle => 'أدلة الشراء';

  @override
  String get unverifiedClaimsLabel => 'ادعاءات عملاء غير مؤكَّدة';

  @override
  String get unverifiedClaimsNote =>
      'عملاء قالوا إنهم طلبوا أو دفعوا. لا تملك Scenario بيانات دفع ولا يمكنها التحقق من ذلك.';

  @override
  String get employeeConfirmedLabel => 'مؤكَّد من موظف';

  @override
  String employeeConfirmedNoteWithCount(int count) {
    return 'تحقّق أحد أعضاء الفريق من سجلاته الخاصة. $count اليوم.';
  }

  @override
  String get employeeConfirmedNote =>
      'تحقّق أحد أعضاء الفريق من سجلاته الخاصة وأكّد ذلك.';

  @override
  String get scopedToVisibleConversations =>
      'مقتصر على المحادثات التي يمكنك رؤيتها.';

  @override
  String get employeePerformanceTitle => 'أداء الموظفين';

  @override
  String get nobodyHandledMessage =>
      'لم يتعامل أحد مع أي محادثة خلال هذه الفترة.';

  @override
  String totalOpenSuffix(int total, int open) {
    return '$total إجمالي · $open مفتوحة';
  }

  @override
  String get emailFieldLabel => 'البريد الإلكتروني';

  @override
  String get phoneFieldLabel => 'الهاتف';

  @override
  String get locationFieldLabel => 'الموقع';

  @override
  String get lastSeenFieldLabel => 'آخر ظهور';

  @override
  String get conversationsCapsSectionTitle => 'المحادثات';

  @override
  String get noVisibleConversations => 'لا توجد محادثات يمكنك رؤيتها.';

  @override
  String get searchCustomersHint =>
      'البحث بالاسم أو البريد الإلكتروني أو الهاتف أو المعرّف';

  @override
  String get noCustomersTitle => 'لا يوجد عملاء';

  @override
  String get noCustomersMessage => 'يظهر العملاء بمجرد إرسالهم أول رسالة إليك.';

  @override
  String chatCountBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محادثة',
      many: '$count محادثة',
      few: '$count محادثات',
      two: 'محادثتان',
      one: 'محادثة واحدة',
      zero: 'بدون محادثات',
    );
    return '$_temp0';
  }

  @override
  String get searchEmployeesHint => 'البحث بالاسم أو البريد الإلكتروني';

  @override
  String get onlineNowFilter => 'متصل الآن';

  @override
  String totalCountSuffix(int total) {
    return '$total إجمالي';
  }

  @override
  String get nobodyOnlineTitle => 'لا يوجد أحد متصل';

  @override
  String get turnOffFilterMessage => 'أوقف الفلتر لرؤية الجميع.';

  @override
  String get noEmployeesFoundTitle => 'لم يتم العثور على موظفين';

  @override
  String get tryDifferentSearchMessage => 'جرّب كلمة بحث مختلفة.';

  @override
  String get inactiveBadge => 'غير نشط';

  @override
  String get noTeamsTitle => 'لا توجد فرق بعد';

  @override
  String get noTeamsMessage =>
      'تجمع الفرق الموظفين معًا بحيث يمكن توجيه المحادثات ومتابعتها بشكل جماعي.';

  @override
  String memberCountBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو',
      many: '$count عضوًا',
      few: '$count أعضاء',
      two: 'عضوان',
      one: 'عضو واحد',
      zero: 'بدون أعضاء',
    );
    return '$_temp0';
  }

  @override
  String ledByLabel(String names) {
    return 'بقيادة $names';
  }

  @override
  String get suggestedFromChatTitle => 'مقترح من هذه المحادثة';

  @override
  String get suggestedFromChatDescription =>
      'تم استخراجه تلقائيًا من المحادثة. لن يُحفظ شيء هنا في ملف العميل حتى تقبله.';

  @override
  String get customerDetailsTitle => 'بيانات العميل';

  @override
  String get nothingRecordedMessage =>
      'لا يوجد شيء مسجَّل بعد. أي معلومة يشاركها العميل — عنوان، رقم هاتف — يمكن حفظها هنا.';

  @override
  String get ordersTitle => 'الطلبات';

  @override
  String get orderButton => 'طلب';

  @override
  String get noOrdersRecordedMessage =>
      'لا توجد طلبات مسجَّلة من هذه المحادثة.';

  @override
  String get employeeSourceBadge => 'موظف';

  @override
  String get autoSourceBadge => 'تلقائي';

  @override
  String get saveToCustomerTooltip => 'حفظ في ملف العميل';

  @override
  String get dismissSuggestionTooltip => 'تجاهل — لن يُقترح مجددًا';

  @override
  String confidenceLabel(int percent) {
    return 'ثقة $percent%';
  }

  @override
  String get tapToCorrectHint => 'اضغط للتصحيح';

  @override
  String get savedToCustomerMessage => 'تم الحفظ في ملف العميل';

  @override
  String get suggestionDismissedMessage => 'تم تجاهل الاقتراح';

  @override
  String get recordDetailDialogTitle => 'تسجيل بيانات عميل';

  @override
  String get detailFieldLabel => 'التفصيل';

  @override
  String get detailFieldHint => 'العنوان';

  @override
  String get valueFieldLabel => 'القيمة';

  @override
  String get valueFieldHint => '١٢ شارع النيل، الجيزة';

  @override
  String get confirmAction => 'تأكيد';

  @override
  String get orderConfirmedMessage => 'تم تأكيد الطلب';

  @override
  String get cancelOrderTooltip => 'إلغاء هذا الطلب';

  @override
  String get orderCancelledMessage => 'تم إلغاء الطلب';

  @override
  String get notCountedAsSaleMessage =>
      'لا يُحتسب كعملية بيع حتى يقوم أحد بتأكيده.';

  @override
  String confirmedByMessage(String name) {
    return 'تم التأكيد بواسطة $name';
  }

  @override
  String get confirmedByUnknownEmployee => 'أحد الموظفين';

  @override
  String get recordOrderDialogTitle => 'تسجيل طلب';

  @override
  String get orderComposerDescription =>
      'ما طلبه العميل. لا تملك Scenario بيانات دفع، لذا هذا سجل للمحادثة وليس إيصالًا.';

  @override
  String get productFieldLabel => 'المنتج';

  @override
  String get qtyFieldLabel => 'الكمية';

  @override
  String get priceFieldLabel => 'السعر';

  @override
  String get addLineButton => 'إضافة سطر';

  @override
  String get totalLabel => 'الإجمالي';

  @override
  String get recordOrderButton => 'تسجيل الطلب';

  @override
  String get orderRecordedMessage =>
      'تم تسجيل الطلب. قم بتأكيده بعد مراجعة سجلاتك الخاصة.';

  @override
  String get avgResponseLabel => 'متوسط زمن الرد';

  @override
  String repliesCountedHint(int count, String median) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رد',
      many: '$count ردًا',
      few: '$count ردود',
      two: 'ردّان',
      one: 'رد واحد',
      zero: 'بدون ردود',
    );
    return '$_temp0 · الوسيط $median';
  }

  @override
  String get noRepliesYetHint => 'لا توجد ردود بعد';

  @override
  String get noBaselineRecorded => 'لا يوجد خط أساس مسجَّل';

  @override
  String get customersLabel => 'العملاء';

  @override
  String messagesSentHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رسالة',
      many: '$count رسالة',
      few: '$count رسائل',
      two: 'رسالتان',
      one: 'رسالة واحدة',
      zero: 'بدون رسائل',
    );
    return '$_temp0 مُرسَلة';
  }

  @override
  String get confirmedOrdersLabel => 'طلبات مؤكَّدة';

  @override
  String confirmedOrderValueHint(String amount, String currency) {
    return '$amount $currency';
  }

  @override
  String recordedNoneConfirmedHint(int count) {
    return '$count مسجَّل، لا شيء مؤكَّد';
  }

  @override
  String get byPlatformSectionTitle => 'حسب المنصة';

  @override
  String handledFootnote(int count) {
    return '$count تمت معالجتها';
  }

  @override
  String resolvedFootnote(int count) {
    return '$count تم حلها';
  }

  @override
  String firstReplyFootnote(String duration) {
    return 'أول رد $duration';
  }

  @override
  String get hoursSectionTitle => 'ساعات العمل';

  @override
  String get hoursNotRecorded => 'غير مسجَّلة لهذه الفترة.';

  @override
  String adherenceBadge(int percent) {
    return 'التزام $percent%';
  }

  @override
  String get onlineHoursLabel => 'متصل';

  @override
  String get scheduledHoursLabel => 'مجدولة';

  @override
  String get noShiftsSetMessage => 'لا توجد نوبات محددة';

  @override
  String msgCustomersHint(int messages, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عميل',
      many: '$count عميلًا',
      few: '$count عملاء',
      two: 'عميلان',
      one: 'عميل واحد',
      zero: 'بدون عملاء',
    );
    return '$messages رسالة · $_temp0';
  }

  @override
  String get misconfiguredTitle => 'لم يتم إعداد مضيف الـ API';

  @override
  String get misconfiguredMessage =>
      'قم بالبناء باستخدام --dart-define=SCENARIO_API_HOST=host:port';
}
