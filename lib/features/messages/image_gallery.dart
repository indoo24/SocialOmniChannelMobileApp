/// Full-screen, swipeable image gallery for a conversation.
///
/// ## What is in it
///
/// Every image the conversation shows **inline** — the agent's and the
/// customer's — in timeline order (oldest first, as the thread reads), and
/// within a message in attachment order. "Inline" is exactly what the bubble
/// renders as a picture ([isGalleryImage]): an image sent as a WhatsApp
/// *document* stays a document there, so it stays out of here; videos, voice
/// notes and files are never included.
///
/// ## Boundaries and pagination
///
/// The thread pages history newest-first, so the images the app holds are
/// only those of the pages loaded so far. The gallery never presents that as
/// the whole conversation:
///
/// * Reaching the first loaded image while older history exists loads older
///   pages — through the same `messages` endpoint, into the gallery's **own**
///   list. The thread underneath is left exactly as it was: its prepend
///   scroll-compensation only works while it is on screen, so filling it
///   from here would move the agent's place when they come back.
/// * Until history is exhausted the counter reads "3 / 12+" — at least 12.
/// * New messages arriving while the gallery is open are appended live.
///
/// ## Gestures
///
/// Swipe between images; pinch or double-tap to zoom; drag to pan while
/// zoomed. Paging is switched off while an image is zoomed, so a pan never
/// turns into a page change. Right to left follows the reading direction:
/// in Arabic, newer images are to the left.
///
/// ## Loading
///
/// Only the page on screen loads (plus the one a swipe is revealing), through
/// the same [CachedNetworkImage] cache the thread uses — with the session
/// cookie the attachment content endpoint needs. A failed image offers a
/// retry that drops the cached failure and asks again with fresh headers.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/utils/attachment_helper.dart';
import '../../core/utils/safe_url.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_controller.dart';

/// One picture in the gallery: the attachment, and where it came from.
class GalleryImage {
  const GalleryImage({
    required this.key,
    required this.attachment,
    this.messageId,
  });

  /// Stable across rebuilds and pages: `<message>:<attachment index>`.
  final String key;
  final MessageAttachment attachment;

  /// The server id of the message, for the download action; null for a
  /// message not yet confirmed by the server.
  final int? messageId;
}

/// True for an attachment the thread renders inline as a picture — and so
/// one the gallery shows. Mirrors the bubble: an inline image with either the
/// agent's own just-picked file or a URL that is safe to load.
bool isGalleryImage(MessageAttachment attachment) {
  if (!attachment.isInlineImage) return false;
  final local = attachment.localFilePath;
  if (local != null && local.isNotEmpty) return true;
  return SafeUrl.forImage(attachment.resolvedUrl).isNotEmpty;
}

/// The key of attachment [index] of [message]. A message the server has not
/// confirmed yet has no id; its local id stands in.
String galleryKey(Message message, int index) {
  final owner = message.id > 0
      ? '${message.id}'
      : 'local-${message.localId ?? message.clientMessageId}';
  return '$owner:$index';
}

/// The gallery images of [messages], which must already be in timeline order.
List<GalleryImage> galleryImagesOf(Iterable<Message> messages) => [
  for (final message in messages)
    for (var i = 0; i < message.attachments.length; i++)
      if (isGalleryImage(message.attachments[i]))
        GalleryImage(
          key: galleryKey(message, i),
          attachment: message.attachments[i],
          messageId: message.id > 0 ? message.id : null,
        ),
];

/// Timeline order, as the thread sorts it: send time, then id.
List<Message> _chronological(Iterable<Message> messages) =>
    [...messages]..sort((a, b) {
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

/// Marks the subtree as the thread of conversation [conversationId], so an
/// image tapped inside it opens the conversation-wide gallery.
class ConversationGalleryScope extends InheritedWidget {
  const ConversationGalleryScope({
    required this.conversationId,
    required super.child,
    super.key,
  });

  final int conversationId;

  static ConversationGalleryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConversationGalleryScope>();

  @override
  bool updateShouldNotify(ConversationGalleryScope oldWidget) =>
      conversationId != oldWidget.conversationId;
}

/// Opens the gallery at attachment [attachmentIndex] of [message]: across
/// the whole conversation inside a [ConversationGalleryScope], otherwise
/// across that message's own images.
void openImageGallery(
  BuildContext context, {
  required Message message,
  required int attachmentIndex,
}) {
  final initialKey = galleryKey(message, attachmentIndex);
  final scope = ConversationGalleryScope.maybeOf(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => scope != null
          ? ConversationGalleryScreen(
              conversationId: scope.conversationId,
              initialKey: initialKey,
            )
          : ImageGalleryViewer(
              images: galleryImagesOf([message]),
              initialKey: initialKey,
            ),
    ),
  );
}

/// The gallery over a whole conversation: the thread's loaded messages, live,
/// plus older pages it loads itself when the agent swipes back past them.
class ConversationGalleryScreen extends ConsumerStatefulWidget {
  const ConversationGalleryScreen({
    required this.conversationId,
    required this.initialKey,
    super.key,
  });

  final int conversationId;
  final String initialKey;

  @override
  ConsumerState<ConversationGalleryScreen> createState() =>
      _ConversationGalleryScreenState();
}

class _ConversationGalleryScreenState
    extends ConsumerState<ConversationGalleryScreen> {
  /// Older history fetched by the gallery, never written to the thread.
  final _older = <Message>[];
  int? _nextPage;
  bool? _hasMore;
  bool _loading = false;
  bool _failed = false;

  Future<void> _loadOlder() async {
    final thread = ref
        .read(conversationControllerProvider(widget.conversationId))
        .value;
    if (thread == null || _loading) return;
    final hasMore = _hasMore ?? thread.hasMore;
    if (!hasMore) return;
    final page = _nextPage ?? thread.nextPage;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await ref
          .read(conversationRepositoryProvider)
          .messages(widget.conversationId, page: page);
      if (!mounted) return;
      setState(() {
        _older.addAll(result.results);
        _nextPage = page + 1;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref
        .watch(conversationControllerProvider(widget.conversationId))
        .value;
    final loaded = thread?.messages ?? const <Message>[];
    // The thread's messages win over a copy the gallery fetched: they carry
    // realtime updates.
    final ids = {for (final m in loaded) m.id};
    final messages = _chronological([
      for (final m in _older)
        if (!ids.contains(m.id)) m,
      ...loaded,
    ]);
    return ImageGalleryViewer(
      images: galleryImagesOf(messages),
      initialKey: widget.initialKey,
      hasMoreBefore: _hasMore ?? thread?.hasMore ?? false,
      loadingBefore: _loading,
      failedBefore: _failed,
      onReachStart: _loadOlder,
    );
  }
}

/// The full-screen viewer itself, over a list of [images].
class ImageGalleryViewer extends ConsumerStatefulWidget {
  const ImageGalleryViewer({
    required this.images,
    required this.initialKey,
    this.hasMoreBefore = false,
    this.loadingBefore = false,
    this.failedBefore = false,
    this.onReachStart,
    super.key,
  });

  final List<GalleryImage> images;
  final String initialKey;

  /// Older images may exist that are not in [images] yet.
  final bool hasMoreBefore;
  final bool loadingBefore;
  final bool failedBefore;

  /// Asked for older images when the first one is on screen.
  final VoidCallback? onReachStart;

  @override
  ConsumerState<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends ConsumerState<ImageGalleryViewer> {
  late PageController _pages;
  late String _currentKey;
  late int _index;
  bool _zoomed = false;
  late Future<Map<String, String>> _headers;

  @override
  void initState() {
    super.initState();
    _index = _indexOf(widget.initialKey) ?? 0;
    _currentKey = widget.images.isEmpty
        ? widget.initialKey
        : widget.images[_index].key;
    _pages = PageController(initialPage: _index);
    _headers = ref.read(apiClientProvider).mediaAuthHeaders();
    _askForOlderIfAtStart();
  }

  int? _indexOf(String key) {
    final i = widget.images.indexWhere((image) => image.key == key);
    return i < 0 ? null : i;
  }

  @override
  void didUpdateWidget(ImageGalleryViewer old) {
    super.didUpdateWidget(old);
    if (widget.images.isEmpty) return;
    // Older images arrived in front, or new ones behind: keep the same
    // picture on screen, wherever it now sits.
    final at =
        _indexOf(_currentKey) ?? _index.clamp(0, widget.images.length - 1);
    _currentKey = widget.images[at].key;
    if (at != _index) {
      _index = at;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
    }
    _askForOlderIfAtStart();
  }

  /// At the first loaded image with older history unloaded: ask for more,
  /// page after page, until an older image turns up or history runs out.
  void _askForOlderIfAtStart() {
    if (_index != 0 ||
        !widget.hasMoreBefore ||
        widget.loadingBefore ||
        widget.failedBefore) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _index == 0) widget.onReachStart?.call();
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _currentKey = widget.images[index].key;
      _zoomed = false;
    });
    _askForOlderIfAtStart();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.images.length) return;
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _refreshHeaders() {
    setState(() {
      _headers = ref.read(apiClientProvider).mediaAuthHeaders();
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final images = widget.images;
    final count = images.length;
    final current = count == 0 ? null : images[_index.clamp(0, count - 1)];
    final position = '${_index + 1}';
    final total = '$count';
    final counter = widget.hasMoreBefore
        ? l10n.galleryCounterMore(position, total)
        : l10n.galleryCounter(position, total);
    final counterSemantics = widget.hasMoreBefore
        ? l10n.galleryCounterMoreSemantics(position, total)
        : l10n.galleryCounterSemantics(position, total);
    final atStart = _index == 0;

    return Scaffold(
      key: const ValueKey('imageGallery'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          key: const ValueKey('galleryClose'),
          icon: const Icon(Icons.close_rounded),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: count > 1 || widget.hasMoreBefore
            ? Semantics(
                label: counterSemantics,
                excludeSemantics: true,
                child: Text(
                  counter,
                  key: const ValueKey('galleryCounter'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
        actions: [
          if (current != null)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: l10n.downloadAttachmentAction,
              onPressed: () => AttachmentHelper.saveAttachmentToDownloads(
                context: context,
                attachment: current.attachment,
                api: ref.read(apiClientProvider),
                messageId: current.messageId,
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            key: const ValueKey('galleryPages'),
            controller: _pages,
            // A zoomed image owns every drag: panning it must never turn
            // into a page change.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: count,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => _GalleryPage(
              key: ValueKey('galleryPage_${images[index].key}'),
              image: images[index],
              headers: _headers,
              onRetry: _refreshHeaders,
              onZoomChanged: (zoomed) {
                if (index == _index && zoomed != _zoomed) {
                  setState(() => _zoomed = zoomed);
                }
              },
            ),
          ),
          if (!_zoomed && count > 1) ...[
            if (_index > 0)
              _StepButton(
                key: const ValueKey('galleryPrevious'),
                previous: true,
                tooltip: l10n.galleryPreviousImage,
                onPressed: () => _go(-1),
              ),
            if (_index < count - 1)
              _StepButton(
                key: const ValueKey('galleryNext'),
                previous: false,
                tooltip: l10n.galleryNextImage,
                onPressed: () => _go(1),
              ),
          ],
          if (atStart && (widget.loadingBefore || widget.failedBefore))
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                // Inside the screen at any text size: the message wraps.
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _EarlierStatus(
                  loading: widget.loadingBefore,
                  onRetry: widget.onReachStart,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A round previous/next control on the matching edge: the start edge holds
/// "previous" in either reading direction.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.previous,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final bool previous;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Points away from the middle, toward the edge it sits on.
    final pointsLeft = previous != rtl;
    return Align(
      alignment: previous
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            foregroundColor: Colors.white,
          ),
          icon: Icon(
            pointsLeft
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
          ),
        ),
      ),
    );
  }
}

class _EarlierStatus extends StatelessWidget {
  const _EarlierStatus({required this.loading, this.onRetry});

  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const style = TextStyle(color: Colors.white, fontSize: 13);
    return Container(
      key: ValueKey(loading ? 'galleryLoadingEarlier' : 'galleryEarlierFailed'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Text(l10n.galleryLoadingEarlier, style: style),
              ),
            ),
          ] else ...[
            Flexible(child: Text(l10n.galleryEarlierFailed, style: style)),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(l10n.retryButton),
            ),
          ],
        ],
      ),
    );
  }
}

/// One image: pinch, double-tap and pan to zoom; reports when it is zoomed
/// so the pager can stand aside.
class _GalleryPage extends StatefulWidget {
  const _GalleryPage({
    required this.image,
    required this.headers,
    required this.onRetry,
    required this.onZoomChanged,
    super.key,
  });

  final GalleryImage image;
  final Future<Map<String, String>> headers;
  final VoidCallback onRetry;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;

  final _transform = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  /// Bumped by a retry, so the image widget starts over.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _zoomAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final tween = _zoomTween;
          if (tween != null) _transform.value = tween.value;
        });
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  void _toggleZoom() {
    final Matrix4 target;
    if (_zoomed) {
      target = Matrix4.identity();
    } else {
      // Zoom in on the tapped point: it stays under the finger.
      final p = _doubleTapAt;
      const s = _doubleTapScale;
      target = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _zoomTween = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurveTween(curve: Curves.easeOut).animate(_zoomAnimation));
    _zoomAnimation.forward(from: 0);
  }

  void _retry() {
    final url = SafeUrl.forImage(widget.image.attachment.resolvedUrl);
    if (url.isNotEmpty) CachedNetworkImage.evictFromCache(url);
    widget.onRetry();
    setState(() => _attempt++);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _zoomAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        key: const ValueKey('galleryZoom'),
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        // At rest a horizontal drag belongs to the pager; only a zoomed image
        // pans.
        panEnabled: _zoomed,
        child: SizedBox.expand(child: Center(child: _image(context))),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final attachment = widget.image.attachment;
    final local = attachment.localFilePath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      return Image.file(
        File(local),
        key: ValueKey('galleryLocal_$_attempt'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _Failed(onRetry: _retry),
      );
    }
    final url = SafeUrl.forImage(attachment.resolvedUrl);
    if (url.isEmpty) return _Failed(onRetry: null);
    return FutureBuilder<Map<String, String>>(
      future: widget.headers,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _Loading();
        return CachedNetworkImage(
          key: ValueKey('galleryNetwork_$_attempt'),
          imageUrl: url,
          httpHeaders: snapshot.data,
          fit: BoxFit.contain,
          progressIndicatorBuilder: (_, _, progress) =>
              _Loading(value: progress.progress),
          errorWidget: (_, _, _) => _Failed(onRetry: _retry),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('galleryImageLoading'),
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 2.5,
          color: Colors.white70,
        ),
      ),
    );
  }
}

/// A broken, expired or unreachable image: says so and offers a retry.
class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('galleryImageFailed'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          color: Colors.white.withValues(alpha: 0.7),
          size: 48,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.galleryImageFailed,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        if (onRetry != null)
          TextButton(
            key: const ValueKey('galleryRetry'),
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(l10n.retryButton),
          ),
      ],
    );
  }
}
