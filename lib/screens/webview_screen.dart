import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app.dart';
import '../config/api_config.dart';
import '../services/bridge_service.dart';

// ─── WebView screen ───────────────────────────────────────────────────────────

/// Full-screen WebView that loads the Portraitor web app.
///
/// Accepts optional [pendingChatText] and [pendingMetadata] arguments. When
/// the page finishes loading, the chat text is injected into the web app's
/// textarea via the JS bridge so the user can continue immediately.
///
/// Back navigation checks WebView history first; only pops to the previous
/// native screen when there is no WebView history left.
class WebViewScreen extends StatefulWidget {
  /// The URL to load. Defaults to the production URL with `?mobile=1`.
  final String? initialUrl;

  /// Normalized chat text to inject after the page loads.
  final String? pendingChatText;

  /// Metadata about the imported chat (format, message count, date range, etc.)
  final Map<String, dynamic>? pendingMetadata;

  const WebViewScreen({
    super.key,
    this.initialUrl,
    this.pendingChatText,
    this.pendingMetadata,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  final BridgeService _bridge = BridgeService();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Text that still needs to be injected (cleared after injection).
  String? _pendingText;
  Map<String, dynamic>? _pendingMeta;

  @override
  void initState() {
    super.initState();

    _pendingText = widget.pendingChatText;
    _pendingMeta = widget.pendingMetadata;

    _setupBridgeCallbacks();
    _initController();
  }

  @override
  void dispose() {
    _bridge.detachController();
    super.dispose();
  }

  // ─── Setup ──────────────────────────────────────────────────────────────────

  void _setupBridgeCallbacks() {
    _bridge.onReady = () {
      // Web app bridge JS is initialized — inject if there is pending text.
      _injectPendingText();
    };

    _bridge.onPortraitDone = (event) {
      // TODO(phase-3): save to sqflite via StorageService.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Portrait for ${event.targetName} saved.',
              style: GoogleFonts.spaceGrotesk(color: Colors.white),
            ),
            backgroundColor: kSuccess,
          ),
        );
      }
    };

    _bridge.onPaymentDone = (event) {
      // TODO(phase-3): persist payment record via StorageService.
    };

    _bridge.onError = (event) {
      if (!mounted) return;
      if (!event.recoverable) {
        setState(() {
          _hasError = true;
          _errorMessage = event.message;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              event.message,
              style: GoogleFonts.spaceGrotesk(color: Colors.white),
            ),
          ),
        );
      }
    };
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kPageBg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..addJavaScriptChannel(
        'PortraitorBridge',
        onMessageReceived: (message) {
          _bridge.handleBridgeMessage(message.message);
        },
      )
      ..loadRequest(Uri.parse(_resolveUrl()));

    _bridge.attachController(_controller);
  }

  // ─── URL helpers ─────────────────────────────────────────────────────────────

  String _resolveUrl() {
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      return widget.initialUrl!;
    }
    return _buildBaseUrl();
  }

  /// Build the base URL from [ApiConfig], stripping the `/api` suffix and
  /// appending the `?mobile=1` query parameter.
  String _buildBaseUrl() {
    // kApiBaseUrl ends with "/api" — remove that to get the web app root.
    final apiBase = kApiBaseUrl;
    final webRoot = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
    return '$webRoot/?mobile=1';
  }

  // ─── Domain whitelist ─────────────────────────────────────────────────────────

  /// Returns true if [uri] belongs to an allowed domain that should stay inside
  /// the WebView. All other domains are opened in the system browser.
  bool _isAllowedDomain(Uri uri) {
    const allowed = [
      'portraitor.ai',
      'staging.portraitor.ai',
      'localhost',
      'js.stripe.com',
      'cdnjs.cloudflare.com',
      'api.stripe.com',
      'fonts.googleapis.com',
      'fonts.gstatic.com',
    ];
    final host = uri.host;
    return allowed.any((d) => host == d || host.endsWith('.$d'));
  }

  // ─── Navigation delegate ──────────────────────────────────────────────────────

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    if (_isAllowedDomain(uri)) {
      return NavigationDecision.navigate;
    }

    // External link — open in system browser and block WebView navigation.
    launchUrl(uri, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  void _onPageFinished(String url) {
    if (mounted) setState(() => _isLoading = false);

    // If the bridge's onReady callback didn't fire (older web app without
    // bridge JS), inject here as a fallback.
    _injectPendingText();
  }

  void _onWebResourceError(WebResourceError error) {
    if (!mounted) return;
    // Only surface main-frame errors; sub-resource errors (fonts, CDN) are
    // acceptable and should not show the error screen.
    if (error.isForMainFrame == true) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Could not load Portraitor (${error.description}).';
      });
    }
  }

  // ─── Injection ────────────────────────────────────────────────────────────────

  Future<void> _injectPendingText() async {
    final text = _pendingText;
    if (text == null || text.isEmpty) return;

    final meta = _pendingMeta ?? {};

    final metadata = ChatInjectionMetadata(
      format: meta['format'] as String? ?? 'unknown',
      messageCount: meta['messageCount'] as int? ?? 0,
      startDate: meta['startDate'] as String?,
      endDate: meta['endDate'] as String?,
      participantNames: (meta['participantNames'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      tokenEstimate: meta['tokenEstimate'] as int? ?? 0,
    );

    // Clear pending so we don't inject twice (onReady + onPageFinished can
    // both fire on the same load).
    _pendingText = null;
    _pendingMeta = null;

    await _bridge.injectChatText(text, metadata);
  }

  // ─── Back navigation ──────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false; // Consume the back event.
    }
    return true; // Let the navigator pop to the previous native screen.
  }

  // ─── Retry ───────────────────────────────────────────────────────────────────

  void _retry() {
    setState(() {
      _hasError = false;
      _isLoading = true;
      _errorMessage = '';
    });
    // Restore pending text so it is injected again after the reload.
    _pendingText = widget.pendingChatText;
    _pendingMeta = widget.pendingMetadata;
    _controller.loadRequest(Uri.parse(_resolveUrl()));
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: kPageBg,
        body: SafeArea(
          child: Stack(
            children: [
              // ── WebView ─────────────────────────────────────────────────
              if (!_hasError)
                WebViewWidget(controller: _controller),

              // ── Loading indicator ────────────────────────────────────────
              if (_isLoading && !_hasError)
                const Center(
                  child: CircularProgressIndicator(
                    color: kAccentPurple,
                  ),
                ),

              // ── Error screen ─────────────────────────────────────────────
              if (_hasError)
                _ErrorScreen(
                  message: _errorMessage,
                  onRetry: _retry,
                  onBack: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Error screen ─────────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kPageBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(bottom: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                color: Colors.red.shade400,
                size: 32,
              ),
            ),
            Text(
              'Could not connect',
              style: GoogleFonts.spaceGrotesk(
                color: kInkStrong,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message.isNotEmpty
                  ? message
                  : 'Please check your internet connection and try again.',
              style: GoogleFonts.spaceGrotesk(
                color: kInkSoft,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: kInkSoft,
                minimumSize: const Size(double.infinity, 52),
                side: const BorderSide(color: kBorderStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Go Back',
                style: GoogleFonts.spaceGrotesk(
                  color: kInkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
