import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/api/api_service.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/ghost_button.dart';

class GDPRScreen extends StatefulWidget {
  const GDPRScreen({super.key});

  @override
  State<GDPRScreen> createState() => _GDPRScreenState();
}

class _GDPRScreenState extends State<GDPRScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _requestExport() async {
    await _performAction('export');
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirm deletion'),
            content: const Text(
              'This will permanently delete all your data from our servers. '
              'Local portraits on your device will not be affected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: PortraitorTokens.error),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true) await _performAction('delete');
  }

  Future<void> _performAction(String action) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Please enter your email');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await ApiService.instance.gdpr(action: action, email: email);
      setState(() {
        _message =
            action == 'export'
                ? 'Data export request submitted. Check your email.'
                : 'Deletion request submitted. Your data will be removed.';
      });
    } catch (e) {
      setState(() => _message = 'Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: PortraitorTokens.brandSoft,
                          borderRadius: BorderRadius.circular(
                            PortraitorTokens.radiusLg,
                          ),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 32,
                          color: PortraitorTokens.brandPurple,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Data & Privacy',
                        style: PortraitorTokens.titleLg,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We process chats once and delete them immediately. '
                        'Use this page to request an export or deletion of any '
                        'remaining records associated with your email.',
                        style: PortraitorTokens.bodyMd,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Your email address',
                          prefixIcon: Icon(Icons.mail_outline, size: 20),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GradientButton(
                        onPressed: _isLoading ? null : _requestExport,
                        isLoading: _isLoading,
                        child: const Text('Request data export'),
                      ),
                      const SizedBox(height: 12),
                      GhostButton(
                        onPressed: _isLoading ? null : _requestDeletion,
                        child: Text(
                          'Delete all my data',
                          style: TextStyle(color: PortraitorTokens.error),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PortraitorTokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(
                              PortraitorTokens.radiusMd,
                            ),
                          ),
                          child: Text(
                            _message!,
                            style: PortraitorTokens.bodyMd,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          const Text('Data & Privacy', style: PortraitorTokens.titleMd),
        ],
      ),
    );
  }
}
