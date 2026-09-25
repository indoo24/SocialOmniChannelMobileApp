import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/shimmer.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/conversations/inbox_skeleton.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_skeleton.dart';
import 'package:scenario_mobile/features/messages/conversation_skeleton.dart';
import 'package:scenario_mobile/features/settings/settings_skeleton.dart';

Widget _wrap(
  Widget child, {
  ThemeData? theme,
  TextDirection dir = TextDirection.ltr,
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.dark,
    home: Directionality(
      textDirection: dir,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Shimmer & Skeleton Core Components', () {
    testWidgets('SkeletonBox, Circle, Text and Card render without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppShimmer(
            child: Column(
              children: [
                SkeletonBox(width: 100, height: 20),
                SkeletonCircle(size: 40),
                SkeletonText(width: 120, height: 14),
                SkeletonCard(child: Text('Card Content')),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(SkeletonCircle), findsOneWidget);
      expect(find.byType(SkeletonText), findsOneWidget);
      expect(find.byType(SkeletonCard), findsOneWidget);
      expect(find.text('Card Content'), findsOneWidget);
    });

    testWidgets('Renders properly in Light Mode and Dark Mode', (tester) async {
      // Dark Mode
      await tester.pumpWidget(
        _wrap(
          const AppShimmer(child: SkeletonBox(width: 50, height: 50)),
          theme: AppTheme.dark,
        ),
      );
      expect(find.byType(SkeletonBox), findsOneWidget);

      // Light Mode
      await tester.pumpWidget(
        _wrap(
          const AppShimmer(child: SkeletonBox(width: 50, height: 50)),
          theme: AppTheme.light,
        ),
      );
      expect(find.byType(SkeletonBox), findsOneWidget);
    });
  });

  group('Conversation & Inbox Skeletons', () {
    testWidgets(
      'ConversationSkeleton contains avatar, name, time, preview, and chips',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const AppShimmer(child: ConversationSkeleton())),
        );

        expect(find.byType(ConversationSkeleton), findsOneWidget);
        expect(find.byType(SkeletonCircle), findsOneWidget);
        expect(find.byType(SkeletonText), findsWidgets);
        expect(find.byType(SkeletonBox), findsWidgets);
      },
    );

    testWidgets(
      'InboxSkeleton renders filter bars and conversation list rows',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_wrap(const InboxSkeleton(itemCount: 4)));

        expect(find.byType(InboxSkeleton), findsOneWidget);
        expect(find.byType(ConversationSkeleton), findsNWidgets(4));
      },
    );

    testWidgets('InboxSkeleton renders in RTL Arabic without error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const InboxSkeleton(itemCount: 3), dir: TextDirection.rtl),
      );

      expect(find.byType(InboxSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dashboard Skeleton', () {
    testWidgets('DashboardSkeleton renders all sections and metric cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrap(const DashboardSkeleton()));

      expect(find.byType(DashboardSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'DashboardSkeleton renders on narrow 320px screen in RTL without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _wrap(const DashboardSkeleton(), dir: TextDirection.rtl),
        );

        expect(find.byType(DashboardSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Settings Skeletons', () {
    testWidgets('ChannelsSkeleton renders platform cards and account rows', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ChannelsSkeleton()));

      expect(find.byType(ChannelsSkeleton), findsOneWidget);
      expect(find.byType(SkeletonCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AssignmentSkeleton renders routing policy cards', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const AssignmentSkeleton()));

      expect(find.byType(AssignmentSkeleton), findsOneWidget);
      expect(find.byType(SkeletonCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'CustomerFieldsSkeleton renders both scrollable and non-scrollable',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const CustomerFieldsSkeleton(scrollable: true)),
        );
        expect(find.byType(CustomerFieldsSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _wrap(
            const SingleChildScrollView(
              child: CustomerFieldsSkeleton(scrollable: false),
            ),
          ),
        );
        expect(find.byType(CustomerFieldsSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SavedRepliesSkeleton renders both scrollable and non-scrollable',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const SavedRepliesSkeleton(scrollable: true)),
        );
        expect(find.byType(SavedRepliesSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _wrap(
            const SingleChildScrollView(
              child: SavedRepliesSkeleton(scrollable: false),
            ),
          ),
        );
        expect(find.byType(SavedRepliesSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SettingsSkeleton renders full screen skeleton without errors',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_wrap(const SettingsSkeleton()));

        expect(find.byType(SettingsSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Conversation Details Skeleton', () {
    testWidgets(
      'ConversationHeaderSkeleton renders avatar, name, and channel badges',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const AppShimmer(child: ConversationHeaderSkeleton())),
        );

        expect(find.byType(ConversationHeaderSkeleton), findsOneWidget);
        expect(find.byType(SkeletonCircle), findsOneWidget);
        expect(find.byType(SkeletonText), findsWidgets);
        expect(find.byType(SkeletonBox), findsWidgets);
      },
    );

    testWidgets(
      'ConversationThreadSkeleton renders incoming/outgoing bubbles, attachment, and composer',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_wrap(const ConversationThreadSkeleton()));

        expect(find.byType(ConversationThreadSkeleton), findsOneWidget);
        expect(find.byType(ConversationComposerSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ConversationDetailsSkeleton renders in RTL Arabic without layout overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _wrap(const ConversationDetailsSkeleton(), dir: TextDirection.rtl),
        );

        expect(find.byType(ConversationDetailsSkeleton), findsOneWidget);
        expect(find.byType(ConversationHeaderSkeleton), findsOneWidget);
        expect(find.byType(ConversationComposerSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
