import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ─── Bridge event data models ────────────────────────────────────────────────

/// Data received from the web app when a portrait analysis is complete.
class PortraitDoneEvent {
  final String text;
  final String targetName;
  final String emailStatus;
  final String? receiptUrl;
  final String conversationId;

  const PortraitDoneEvent({
    required this.text,
    required this.targetName,
    required this.emailStatus,
    this.receiptUrl,
    required this.conversationId,
  });

  factory PortraitDoneEvent.fromMap(Map<String, dynamic> data) {
    return PortraitDoneEvent(
      text: data['text'] as String? ?? '',
      targetName: data['targetName'] as String? ?? '',
      emailStatus: data['emailStatus'] as String? ?? 'unknown',
      receiptUrl: data['receiptUrl'] as String?,
      conversationId: data['conversationId'] as String? ?? '',
    );
  }
}

/// Data received from the web app when a Stripe payment is authorized.
class PaymentDoneEvent {
  final String sessionId;
  final int amountCents;
  final String currency;

  const PaymentDoneEvent({
    required this.sessionId,
    required this.amountCents,
    required this.currency,
  });

  factory PaymentDoneEvent.fromMap(Map<String, dynamic> data) {
    return PaymentDoneEvent(
      sessionId: data['sessionId'] as String? ?? '',
      amountCents: data['amountCents'] as int? ?? 0,
      currency: data['currency'] as String? ?? 'usd',
    );
  }
}

/// Data received from the web app when an error occurs.
class BridgeErrorEvent {
  final String message;
  final String? code;
  final bool recoverable;

  const BridgeErrorEvent({
    required this.message,
    this.code,
    required this.recoverable,
  });

  factory BridgeErrorEvent.fromMap(Map<String, dynamic> data) {
    return BridgeErrorEvent(
      message: data['message'] as String? ?? 'An unknown error occurred',
      code: data['code'] as String?,
      recoverable: data['recoverable'] as bool? ?? false,
    );
  }
}

// ─── Metadata for chat injection ─────────────────────────────────────────────

/// Metadata about the imported chat, sent alongside the normalized text.
class ChatInjectionMetadata {
  final String format;
  final int messageCount;
  final String? startDate;
  final String? endDate;
  final List<String> participantNames;
  final int tokenEstimate;

  const ChatInjectionMetadata({
    required this.format,
    required this.messageCount,
    this.startDate,
    this.endDate,
    required this.participantNames,
    required this.tokenEstimate,
  });

  Map<String, dynamic> toMap() {
    return {
      'format': format,
      'messageCount': messageCount,
      'startDate': startDate,
      'endDate': endDate,
      'participantNames': participantNames,
      'tokenEstimate': tokenEstimate,
    };
  }
}

// ─── Bridge service ───────────────────────────────────────────────────────────

/// Encapsulates the JavaScript bridge between the Flutter native layer and the
/// Portraitor web app running inside a WebView.
///
/// **Native → Web:** Call [injectChatText] to inject normalized chat text and
/// metadata into the web app's `#exportInput` textarea.
///
/// **Web → Native:** Register callbacks ([onReady], [onPortraitDone],
/// [onPaymentDone], [onError]) before attaching the controller. The web app
/// sends events via `PortraitorBridge.postMessage(jsonString)`.
class BridgeService {
  WebViewController? _controller;

  // ─── Callbacks (Web → Native) ─────────────────────────────────────────────

  /// Called when the web page has loaded and the bridge JS is initialized.
  VoidCallback? onReady;

  /// Called when portrait analysis is complete.
  void Function(PortraitDoneEvent event)? onPortraitDone;

  /// Called when a Stripe payment is authorized.
  void Function(PaymentDoneEvent event)? onPaymentDone;

  /// Called when the web app reports an error.
  void Function(BridgeErrorEvent event)? onError;

  // ─── Controller attachment ────────────────────────────────────────────────

  /// Attach a [WebViewController] so [injectChatText] can call into the page.
  void attachController(WebViewController controller) {
    _controller = controller;
  }

  /// Detach the controller (call on screen dispose).
  void detachController() {
    _controller = null;
  }

  // ─── Native → Web ─────────────────────────────────────────────────────────

  /// Inject normalized chat [text] and [metadata] into the web app's textarea.
  ///
  /// Escapes the text for safe embedding in a JavaScript string literal:
  /// backslashes, single quotes, newlines, and carriage returns.
  ///
  /// Tries `window.portraitorMobileBridge.injectChat()` first. Falls back to
  /// directly setting the textarea value if the bridge JS has not loaded yet.
  Future<void> injectChatText(
    String text,
    ChatInjectionMetadata metadata,
  ) async {
    final controller = _controller;
    if (controller == null) return;

    // Escape for safe embedding inside a JS single-quoted string literal.
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');

    final metadataJson = jsonEncode(metadata.toMap());

    await controller.runJavaScript('''
(function() {
  var normalizedText = '$escaped';
  var metadata = $metadataJson;
  if (typeof window.portraitorMobileBridge !== 'undefined' &&
      typeof window.portraitorMobileBridge.injectChat === 'function') {
    window.portraitorMobileBridge.injectChat(normalizedText, metadata);
  } else {
    // Fallback: directly set textarea value and fire input event.
    var ta = document.getElementById('exportInput');
    if (ta) {
      ta.value = normalizedText;
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }
  }
})();
''');
  }

  // ─── Web → Native ─────────────────────────────────────────────────────────

  /// Handle a raw JSON string posted by `PortraitorBridge.postMessage()`.
  ///
  /// Dispatches to the appropriate callback based on the event `type` field.
  /// Silently ignores unknown event types and malformed JSON.
  void handleBridgeMessage(String jsonString) {
    Map<String, dynamic> event;
    try {
      event = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      // Malformed JSON from web app — ignore.
      return;
    }

    final type = event['type'] as String?;
    final data = (event['data'] as Map<String, dynamic>?) ?? {};

    switch (type) {
      case 'ready':
        onReady?.call();

      case 'portrait_done':
        onPortraitDone?.call(PortraitDoneEvent.fromMap(data));

      case 'payment_done':
        onPaymentDone?.call(PaymentDoneEvent.fromMap(data));

      case 'error':
        onError?.call(BridgeErrorEvent.fromMap(data));

      case 'navigation':
        // Navigation events are handled directly in WebViewScreen via the
        // NavigationDelegate. Nothing to dispatch here.
        break;

      default:
        // Unknown event type — no-op.
        break;
    }
  }
}
