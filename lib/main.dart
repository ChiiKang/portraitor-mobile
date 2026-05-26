import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'app.dart';
import 'providers/import_provider.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StorageService.instance.init();
  } catch (_) {}

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
  @override
  void initState() {
    super.initState();
    if (!_shouldEnableShareIntent) return;
    _initShareIntent();
  }

  bool get _shouldEnableShareIntent {
    if (widget.enableShareIntent != null) return widget.enableShareIntent!;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _initShareIntent() {
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        ref.read(importProvider.notifier).handleSharedFiles(files);
      }
    });

    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        ref.read(importProvider.notifier).handleSharedFiles(files);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
