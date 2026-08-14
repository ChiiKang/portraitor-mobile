import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

/// Blocking save-your-code moment.
///
/// The Pass code is revealed exactly once and cannot be reissued: it is stored
/// as a peppered HMAC, and V1 has no rotation. Losing it costs cross-platform
/// use of a Pass the user paid for, which is why this is a screen the user
/// must acknowledge rather than a toast they can miss.
///
/// When [passCode] is null the code was never delivered. That is a
/// Portraitor-side failure with no user-facing recovery, so the screen states
/// the consequence plainly instead of offering an action that cannot work.
class SavePassScreen extends StatefulWidget {
  const SavePassScreen({
    super.key,
    required this.passCode,
    required this.onContinue,
  });

  final String? passCode;
  final VoidCallback onContinue;

  @override
  State<SavePassScreen> createState() => _SavePassScreenState();
}

class _SavePassScreenState extends State<SavePassScreen> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final code = widget.passCode;
    final delivered = code != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                delivered ? 'Save your Pass code' : 'Purchase complete',
                style: PortraitorTokens.displaySm.copyWith(
                  color: PortraitorTokens.onboardingInk,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                delivered
                    ? 'This is the only time we can show you this code. It is '
                        'how you use your Pass on the web or another device.'
                    : 'Your purchase is confirmed and works on this device. We '
                        'could not deliver your Pass code, so it cannot be '
                        'used anywhere else.',
                style: PortraitorTokens.bodyMd.copyWith(
                  color: PortraitorTokens.onboardingInkSoft,
                ),
              ),
              const SizedBox(height: 24),
              if (delivered) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius:
                        BorderRadius.circular(PortraitorTokens.radiusLg),
                    border: Border.all(color: PortraitorTokens.borderSoft),
                  ),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: PortraitorTokens.titleMd.copyWith(
                      color: PortraitorTokens.onboardingInk,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('save_pass_copy'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
                const Spacer(),
                CheckboxListTile(
                  key: const Key('save_pass_confirm'),
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  title: Text(
                    'I have saved my Pass code',
                    style: PortraitorTokens.bodyMd.copyWith(
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ] else
                const Spacer(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: PortraitorTokens.buttonHeightLg,
                child: FilledButton(
                  key: const Key('save_pass_continue'),
                  onPressed:
                      (!delivered || _confirmed) ? widget.onContinue : null,
                  child: Text('Continue', style: PortraitorTokens.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
