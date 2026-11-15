/// The pieces of the background path that touch the engine and the disk:
/// the grouping-state file (shared between isolates) and the initials
/// avatar (drawn with dart:ui), plus the in-app previews setting.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/notifications/notification_avatar.dart';
import 'package:scenario_mobile/core/notifications/notification_grouping.dart';
import 'package:scenario_mobile/core/notifications/notification_state_store.dart';
import 'package:scenario_mobile/core/preferences/preferences_controller.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';

class _PreviewStore extends SecureStore {
  bool? previews;
  int writes = 0;

  @override
  Future<bool?> readNotificationPreviews() async => previews;

  @override
  Future<void> writeNotificationPreviews(bool enabled) async {
    writes++;
    previews = enabled;
  }
}

NotificationGroupState stateWith(List<int> ids) => NotificationGroupState(
  conversations: [
    for (final id in ids)
      ConversationEntry(
        conversationId: id,
        customerName: 'C$id',
        provider: 'WHATSAPP',
        channelName: '',
        messageCount: 1,
        previews: [MessagePreview(text: 'hi', at: DateTime.utc(2026))],
        lastMessageAt: DateTime.utc(2026),
        postedAt: DateTime.utc(2026),
      ),
  ],
  seenKeys: [for (final id in ids) 'm:$id'],
);

void main() {
  group('NotificationStateStore', () {
    late Directory dir;
    late NotificationStateStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('notif_store');
      store = NotificationStateStore(directory: () async => dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('no file reads as empty', () async {
      expect((await store.read()).isEmpty, isTrue);
    });

    test('round trip through a second instance (another isolate)', () async {
      await store.write(stateWith([1, 2, 3]));
      final other = NotificationStateStore(directory: () async => dir);
      final read = await other.read();
      expect(read.conversations.map((c) => c.conversationId), [1, 2, 3]);
      expect(read.seenKeys, ['m:1', 'm:2', 'm:3']);
      // Atomic write: the temp file never lingers.
      expect(
        dir.listSync().map((e) => e.path).where((p) => p.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('a corrupt file reads as empty instead of throwing', () async {
      await File(
        '${dir.path}${Platform.pathSeparator}notification_groups.json',
      ).writeAsString('{"v":1,"conversations":[{');
      expect((await store.read()).isEmpty, isTrue);
    });

    test('locked() serialises read-modify-write within an isolate', () async {
      // Ten pushes handled "at once" must all land: without the lock, they
      // would all read the same empty state and overwrite each other.
      await Future.wait([
        for (var i = 1; i <= 10; i++)
          store.locked(() async {
            final s = await store.read();
            await Future<void>.delayed(const Duration(milliseconds: 2));
            await store.write(
              stateWith([...s.conversations.map((c) => c.conversationId), i]),
            );
          }),
      ]);
      expect((await store.read()).conversationCount, 10);
    });

    test('a failing body does not jam the lock', () async {
      await expectLater(
        store.locked<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await store.locked(() async => 42), 42);
    });

    test('delete() forgets everything', () async {
      await store.write(stateWith([1]));
      await store.delete();
      expect((await store.read()).isEmpty, isTrue);
    });
  });

  group('NotificationAvatar', () {
    testWidgets('draws a PNG with initials and a channel dot', (tester) async {
      final bytes = await tester.runAsync(
        () => NotificationAvatar.render(
          initials: 'SA',
          conversationId: 306,
          provider: 'WHATSAPP',
        ),
      );
      expect(bytes, isNotNull);
      // PNG signature.
      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    testWidgets('Arabic initials render too', (tester) async {
      final bytes = await tester.runAsync(
        () => NotificationAvatar.render(
          initials: 'مع',
          conversationId: 1,
          provider: '',
        ),
      );
      expect(bytes, isNotNull);
    });

    test('no initials, no avatar (previews off)', () async {
      expect(
        await NotificationAvatar.render(
          initials: '',
          conversationId: 1,
          provider: 'WHATSAPP',
        ),
        isNull,
      );
    });

    test('a conversation keeps its colour', () {
      expect(
        NotificationAvatar.backgroundFor(306),
        NotificationAvatar.backgroundFor(306),
      );
    });
  });

  group('Message previews setting', () {
    test('defaults to on, persists a change', () async {
      final secure = _PreviewStore();
      final container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWithValue(secure)],
      );
      addTearDown(container.dispose);

      expect(await container.read(notificationPreviewsProvider.future), isTrue);
      await container
          .read(notificationPreviewsProvider.notifier)
          .setEnabled(false);
      expect(container.read(notificationPreviewsProvider).value, isFalse);
      expect(secure.previews, isFalse);
      expect(secure.writes, 1);
    });

    test('restores a saved "off"', () async {
      final secure = _PreviewStore()..previews = false;
      final container = ProviderContainer(
        overrides: [secureStoreProvider.overrideWithValue(secure)],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(notificationPreviewsProvider.future),
        isFalse,
      );
    });
  });
}
