import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'app.dart';
import 'providers/import_provider.dart';
import 'services/storage_service.dart';

/// Holds the initial shared files detected at cold start (before widget tree).
/// ShareIntentHandler consumes this once and then processes the files.
List<SharedMediaFile>? _pendingInitialFiles;

/// Set to true when the app was launched/resumed via a share intent.
/// The router redirect uses this to skip onboarding.
final shareIntentPending = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StorageService.instance.init();
  } catch (_) {}

  // Check for initial share intent BEFORE building the widget tree.
  // We store the files so ShareIntentHandler can process them (avoids double-read).
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      final initialFiles =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialFiles.isNotEmpty) {
        _pendingInitialFiles = initialFiles;
        shareIntentPending.value = true;
        debugPrint('[ShareIntent] Cold start detected ${initialFiles.length} files');
        for (final f in initialFiles) {
          debugPrint('[ShareIntent]   path=${f.path}, type=${f.type}');
        }
      }
    } catch (e) {
      debugPrint('[ShareIntent] Error checking initial media: $e');
    }
  }

  runApp(const ProviderScope(child: PortraitorApp()));
}

class ShareIntentHandler extends ConsumerStatefulWidget {
  final Widget child;
  final bool? enableShareIntent;
  const ShareIntentHandler({
    super.key,
    required this.child,
    this.enableShareIntent,
  });

  @override
  ConsumerState<ShareIntentHandler> createState() => _ShareIntentHandlerState();
}

class _ShareIntentHandlerState extends ConsumerState<ShareIntentHandler> {
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    if (!_shouldEnableShareIntent) return;
    _initShareIntent();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  bool get _shouldEnableShareIntent {
    if (widget.enableShareIntent != null) return widget.enableShareIntent!;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _initShareIntent() {
    // Defer processing to after the widget tree finishes building
    Future.microtask(() {
      if (!mounted) return;

      // If we already captured files in main(), process them now
      if (_pendingInitialFiles != null && _pendingInitialFiles!.isNotEmpty) {
        final files = _pendingInitialFiles!;
        _pendingInitialFiles = null;
        debugPrint('[ShareIntent] Processing ${files.length} pre-captured files');
        _handleIncomingShare(files);
      } else {
        // Fallback: try getInitialMedia in case the main() check missed it
        ReceiveSharingIntent.instance.getInitialMedia().then((files) {
          if (!mounted) return;
          if (files.isNotEmpty) {
            debugPrint('[ShareIntent] getInitialMedia returned ${files.length} files');
            _handleIncomingShare(files);
          }
        });
      }
    });

    // Handle media received while app is already running (warm start)
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        debugPrint('[ShareIntent] Stream received ${files.length} files');
        _handleIncomingShare(files);
      }
    });
  }

  void _handleIncomingShare(List<SharedMediaFile> files) {
    shareIntentPending.value = true;
    debugPrint('[ShareIntent] handleIncomingShare: processing files...');
    ref.read(importProvider.notifier).handleSharedFiles(files);
    _pollAndNavigate();
  }

  void _pollAndNavigate([int attempts = 0]) {
    if (!mounted || attempts > 40) {
      debugPrint('[ShareIntent] Gave up after $attempts attempts');
      shareIntentPending.value = false;
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _navigateToSetupIfReady(attempts);
    });
  }

  void _navigateToSetupIfReady([int attempts = 0]) {
    final state = ref.read(importProvider);
    debugPrint('[ShareIntent] Poll #$attempts: isLoading=${state.isLoading}, '
        'normalized=${state.normalized != null}, error=${state.error}');

    if (state.normalized != null) {
      debugPrint('[ShareIntent] Success! Navigating to /setup with '
          '${state.normalized!.detectedNames.length} names, '
          '${state.normalized!.messageCount} messages');
      shareIntentPending.value = false;
      router.go('/setup', extra: {
        'normalizedText': state.normalized!.text,
        'format': state.normalized!.format.name,
        'detectedNames': state.normalized!.detectedNames,
        'messageCount': state.normalized!.messageCount,
        'dateRange': state.dateRange != null
            ? {'start': state.dateRange!.start, 'end': state.dateRange!.end}
            : null,
      });
    } else if (state.isLoading) {
      _pollAndNavigate(attempts + 1);
    } else if (state.error != null) {
      debugPrint('[ShareIntent] Error: ${state.error}');
      shareIntentPending.value = false;
    } else if (attempts < 10) {
      // File read hasn't started yet — give it more time
      _pollAndNavigate(attempts + 1);
    } else {
      debugPrint('[ShareIntent] No data after $attempts attempts, giving up');
      shareIntentPending.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
