import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

class WhatsAppExportGuideScreen extends StatelessWidget {
  const WhatsAppExportGuideScreen({super.key});

  Future<void> _openWhatsApp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse('whatsapp://app');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('WhatsApp is not available on this device.'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF666675),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF686879), Color(0xFF5D5D6D)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(PortraitorTokens.space20),
                child: _BackButton(onPressed: () => context.pop()),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                PortraitorTokens.space28,
                PortraitorTokens.space20,
                PortraitorTokens.space28,
                bottomPadding + PortraitorTokens.space20,
              ),
              decoration: const BoxDecoration(
                color: PortraitorTokens.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2E000000),
                    offset: Offset(0, -12),
                    blurRadius: 44,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: _SheetHandle()),
                  const SizedBox(height: PortraitorTokens.space28),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/whatsapp.png',
                          width: 52,
                          height: 52,
                        ),
                      ),
                      const SizedBox(width: PortraitorTokens.space16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export from WhatsApp',
                              style: PortraitorTokens.titleLg.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: PortraitorTokens.space4),
                            Text(
                              'Guide for exporting your chat',
                              style: PortraitorTokens.bodySm,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PortraitorTokens.space28),
                  const _StepRow(
                    number: '1',
                    title: 'Open the chat',
                    body:
                        'In WhatsApp, open the conversation you want to analyze.',
                    showLine: true,
                  ),
                  const _StepRow(
                    number: '2',
                    title: 'Tap ⋮ → More → Export chat',
                    body:
                        'Open the chat menu at the top-right, then More, then Export chat.',
                    showLine: true,
                  ),
                  const _StepRow(
                    number: '3',
                    title: 'Choose "Without media"',
                    body: 'Keeps it fast and text-only - exactly what we need.',
                    showLine: true,
                  ),
                  const _StepRow(
                    number: '4',
                    title: 'Pick Portraitor to share',
                    body:
                        'In the share sheet, tap Portraitor. We will take it from there.',
                    showLine: false,
                  ),
                  const SizedBox(height: PortraitorTokens.space24),
                  _WhatsAppButton(onPressed: () => _openWhatsApp(context)),
                  const SizedBox(height: PortraitorTokens.space14),
                  Center(
                    child: Text(
                      'Already exported? Come back here and we will detect it from your clipboard.',
                      textAlign: TextAlign.center,
                      style: PortraitorTokens.labelSm.copyWith(
                        color: PortraitorTokens.inkDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortraitorTokens.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusMd),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.chevron_left, color: PortraitorTokens.ink),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 5,
      decoration: BoxDecoration(
        color: PortraitorTokens.surfaceSunken,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.body,
    required this.showLine,
  });

  final String number;
  final String title;
  final String body;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: PortraitorTokens.brandGradient,
                    boxShadow: [
                      BoxShadow(
                        color: PortraitorTokens.brandGlow,
                        offset: Offset(0, 8),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: PortraitorTokens.button.copyWith(fontSize: 17),
                    ),
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(
                        vertical: PortraitorTokens.space4,
                      ),
                      color: PortraitorTokens.brandSoft,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: PortraitorTokens.space18,
                top: PortraitorTokens.space2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PortraitorTokens.titleSm),
                  const SizedBox(height: PortraitorTokens.space6),
                  Text(
                    body,
                    style: PortraitorTokens.bodySm.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
          ),
          textStyle: PortraitorTokens.button.copyWith(fontSize: 18),
        ),
        icon: const Icon(Icons.chat_bubble, size: 22),
        label: const Text('Open WhatsApp'),
      ),
    );
  }
}
