/// The composer's attachment pieces wired exactly as `_Composer` wires them
/// — the button feeding a real [ComposerUploadQueue], the card bar
/// rendering it — without the rest of the conversation screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/messages/composer_attachment.dart';

class ComposerUploadHarness extends ConsumerStatefulWidget {
  const ComposerUploadHarness({
    this.staged,
    this.errors,
    this.onQueue,
    super.key,
  });

  /// Mirrors the queue's uploaded drafts, in card order.
  final List<StagedAttachment>? staged;

  /// Every message the composer would show: the button's own, and each
  /// upload failure's server reason.
  final List<String>? errors;

  /// Hands the live queue to the test.
  final ValueChanged<ComposerUploadQueue>? onQueue;

  @override
  ConsumerState<ComposerUploadHarness> createState() =>
      _ComposerUploadHarnessState();
}

class _ComposerUploadHarnessState extends ConsumerState<ComposerUploadHarness> {
  late final ComposerUploadQueue _queue;

  @override
  void initState() {
    super.initState();
    _queue = ComposerUploadQueue(
      repository: ref.read(conversationRepositoryProvider),
      conversationId: 42,
      onFailed: (upload) => widget.errors?.add(upload.error?.message ?? ''),
    )..addListener(_sync);
    widget.onQueue?.call(_queue);
  }

  void _sync() {
    widget.staged
      ?..clear()
      ..addAll([for (final u in _queue.uploaded) u.staged!]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _queue
      ..removeListener(_sync)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ComposerAttachmentsPreviewBar(uploads: _queue),
      ComposerAttachmentButton(
        conversationId: 42,
        enabled: true,
        currentStagedCount: _queue.count,
        onPicked: _queue.add,
        onError: (e) => widget.errors?.add(e),
      ),
    ],
  );
}
