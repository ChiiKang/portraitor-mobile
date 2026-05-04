import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'app.dart';
import 'providers/conversation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: PortraitorApp(),
    ),
  );
}

/// Listens for incoming share intents and forwards them to the provider.
///
/// This widget sits at the root so the listener is active for the full app
/// lifecycle, whether the app was cold-started from a share or was already
/// running in the background.
class ShareIntentHandler extends ConsumerStatefulWidget {
  final Widget child;
  const ShareIntentHandler({super.key, required this.child});

  @override
  ConsumerState<ShareIntentHandler> createState() => _ShareIntentHandlerState();
}

class _ShareIntentHandlerState extends ConsumerState<ShareIntentHandler> {
  @override
  void initState() {
    super.initState();
    _initShareIntent();
  }

  void _initShareIntent() {
    // Handle intent that launched the app (cold start from share sheet).
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        ref
            .read(conversationProvider.notifier)
            .handleSharedFiles(files);
      }
    });

    // Handle intents received while the app is running (warm start).
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        ref
            .read(conversationProvider.notifier)
            .handleSharedFiles(files);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
