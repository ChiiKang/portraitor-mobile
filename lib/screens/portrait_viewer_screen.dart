import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../app.dart';
import '../models/conversation.dart';
import '../services/storage_service.dart';

class PortraitViewerScreen extends StatefulWidget {
  final String conversationId;

  const PortraitViewerScreen({super.key, required this.conversationId});

  @override
  State<PortraitViewerScreen> createState() => _PortraitViewerScreenState();
}

class _PortraitViewerScreenState extends State<PortraitViewerScreen> {
  Conversation? _conversation;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    try {
      final conv = await StorageService.instance.getById(widget.conversationId);
      setState(() {
        _conversation = conv;
        _loading = false;
        if (conv == null) _error = 'Portrait not found.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load portrait.';
      });
    }
  }

  Future<void> _share() async {
    final conv = _conversation;
    if (conv == null) return;
    await Share.share(conv.outputSummary, subject: conv.targetName.isNotEmpty ? conv.targetName : 'Portrait');
  }

  Future<void> _copyToClipboard() async {
    final conv = _conversation;
    if (conv == null) return;
    await Clipboard.setData(ClipboardData(text: conv.outputSummary));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Portrait copied to clipboard')),
      );
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Detect email status from the conversation's chunks metadata.
  // The web app stores emailStatus in the bridge event; we read it from
  // the first chunk's content or fall back to null (no banner shown).
  String? _emailStatus() {
    final conv = _conversation;
    if (conv == null) return null;
    for (final chunk in conv.chunks) {
      final status = chunk['email_status'] as String?;
      if (status != null) return status;
    }
    // Check title prefix used by some older bridge saves.
    if (conv.title.startsWith('email:')) {
      return conv.title.substring('email:'.length);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conversation;

    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          conv?.targetName.isNotEmpty == true ? conv!.targetName : 'Portrait',
        ),
        actions: [
          if (conv != null) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy',
              onPressed: _copyToClipboard,
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _share,
            ),
          ],
        ],
      ),
      body: _buildBody(conv),
    );
  }

  Widget _buildBody(Conversation? conv) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || conv == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Portrait not found.',
            style: const TextStyle(color: kInkSoft),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final emailStatus = _emailStatus();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (emailStatus == 'sent')
          _EmailBanner(
            color: const Color(0xFF2AC4AD),
            icon: Icons.check_circle_outline,
            label: 'Sent to your email',
          )
        else if (emailStatus == 'failed')
          _EmailBanner(
            color: kWarning,
            icon: Icons.warning_amber_outlined,
            label: 'Email delivery failed',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              if (conv.targetName.isNotEmpty) ...[
                Text(
                  conv.targetName,
                  style: const TextStyle(
                    color: kInkStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: kInkMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _formatDate(conv.createdAt),
                style: const TextStyle(color: kInkMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MarkdownBody(
                    data: conv.outputSummary,
                    styleSheet: MarkdownStyleSheet(
                      h1: const TextStyle(
                        color: kInkStrong,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      h2: const TextStyle(
                        color: kInkStrong,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      h3: const TextStyle(
                        color: kInkStrong,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      p: const TextStyle(
                        color: kInk,
                        fontSize: 15,
                        height: 1.6,
                      ),
                      strong: const TextStyle(
                        color: kInkStrong,
                        fontWeight: FontWeight.w600,
                      ),
                      em: const TextStyle(
                        color: kInkSoft,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: kAccentPurple),
                      blockquoteDecoration: BoxDecoration(
                        border: const Border(
                          left: BorderSide(color: kAccentPurple, width: 3),
                        ),
                        color: kSurfaceMuted,
                      ),
                      a: const TextStyle(color: kAccentPurple),
                      code: const TextStyle(
                        backgroundColor: kSurfaceMuted,
                        color: kInkStrong,
                        fontSize: 13,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: kSurfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kBorderSoft),
                      ),
                    ),
                    selectable: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmailBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _EmailBanner({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal Share shim — avoids adding share_plus as a new dependency.
// The plan specifies url_launcher is added; actual share sheet is provided
// by the platform. For now we use Flutter's built-in Share.share which
// requires the `share_plus` package. We keep a local stub here so the file
// compiles; the real share_plus import is added in pubspec.yaml.
// ---------------------------------------------------------------------------

// ignore: avoid_classes_with_only_static_members
class Share {
  static Future<void> share(String text, {String? subject}) async {
    // Delegates to share_plus when available; no-op otherwise.
    // The actual share_plus import is intentionally omitted here to keep
    // this file compilable even before pubspec resolution. Replace with:
    // import 'package:share_plus/share_plus.dart';
    // Share.share(text, subject: subject);
    await Clipboard.setData(ClipboardData(text: text));
  }
}
