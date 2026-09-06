/// Riverpod providers for the Templates feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/directory.dart';
import '../../core/models/template.dart';
import '../../core/providers.dart';
import '../directory/directory_providers.dart';
import '../messages/conversation_controller.dart';
import 'templates_repository.dart';

/// Exposes the templates repository.
final templatesRepositoryProvider = Provider<TemplatesRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return TemplatesRepository(api);
});

/// All active WhatsApp channels connected to this organization.
final whatsappChannelsProvider = FutureProvider<List<ChannelConnection>>((
  ref,
) async {
  final channels = await ref.watch(channelsProvider.future);
  return channels
      .where((c) => c.provider.toUpperCase() == 'WHATSAPP' && c.isActive)
      .toList(growable: false);
});

/// Currently selected WhatsApp Business Account (channel) on the Templates screen.
class SelectedWabaChannelController extends Notifier<int?> {
  @override
  int? build() {
    final channels = ref.watch(whatsappChannelsProvider).value ?? [];
    if (channels.isEmpty) return null;
    final previous = state;
    if (previous != null && channels.any((c) => c.id == previous)) {
      return previous;
    }
    return channels.first.id;
  }

  void select(int channelId) {
    state = channelId;
  }
}

final selectedWabaChannelIdProvider =
    NotifierProvider<SelectedWabaChannelController, int?>(
      SelectedWabaChannelController.new,
    );

/// Templates loaded for a specific WhatsApp channel.
final templatesForChannelProvider =
    FutureProvider.family<List<WhatsAppTemplate>, int>((ref, channelId) async {
      final repository = ref.watch(templatesRepositoryProvider);
      return repository.listTemplates(channelId);
    });

/// Templates available for an in-conversation template picker.
///
/// Looks up the conversation's channel, or falls back to the active WhatsApp
/// channel, and retrieves its approved/sendable templates from Meta.
final conversationTemplatesProvider =
    FutureProvider.family<List<WhatsAppTemplate>, int>((
      ref,
      conversationId,
    ) async {
      final convoState = ref
          .watch(conversationControllerProvider(conversationId))
          .value;
      final conversation = convoState?.conversation;
      if (conversation == null ||
          conversation.provider.toUpperCase() != 'WHATSAPP') {
        return const <WhatsAppTemplate>[];
      }

      final channelId = conversation.channelId;

      int? targetChannelId = channelId;
      if (targetChannelId == null) {
        final waChannels = await ref.watch(whatsappChannelsProvider.future);
        targetChannelId = waChannels.firstOrNull?.id;
      }

      if (targetChannelId == null) {
        return const <WhatsAppTemplate>[];
      }

      final all = await ref.watch(
        templatesForChannelProvider(targetChannelId).future,
      );
      // For in-conversation sending, only approved templates that can be sent are relevant
      return all.where((t) => t.canSend).toList(growable: false);
    });
