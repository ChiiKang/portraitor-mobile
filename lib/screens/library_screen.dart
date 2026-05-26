import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/portraits_provider.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_avatar.dart';
import '../widgets/gradient_background.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portraits = ref.watch(portraitsProvider);

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: portraits.portraits.isEmpty
                    ? _EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: portraits.portraits.length,
                        itemBuilder: (context, index) {
                          final portrait = portraits.portraits[index];
                          return _PortraitCard(
                            portrait: portrait,
                            onTap: () => context.push('/result/${portrait.id}'),
                            onDelete: () => _confirmDelete(context, ref, portrait),
                          );
                        },
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
          const Text('Library', style: PortraitorTokens.titleMd),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Portrait portrait) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete portrait?'),
        content: Text('Remove ${portrait.targetName}\'s portrait? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(portraitsProvider.notifier).deletePortrait(portrait.id);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: PortraitorTokens.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: PortraitorTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
            ),
            child: const Icon(Icons.collections_bookmark_outlined, size: 36, color: PortraitorTokens.inkMuted),
          ),
          const SizedBox(height: PortraitorTokens.space16),
          const Text('No portraits yet', style: PortraitorTokens.titleSm),
          const SizedBox(height: 8),
          Text(
            'Your completed portraits will appear here',
            style: PortraitorTokens.bodyMd.copyWith(color: PortraitorTokens.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _PortraitCard extends StatelessWidget {
  final Portrait portrait;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PortraitCard({
    required this.portrait,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(PortraitorTokens.space14),
            child: Row(
              children: [
                GradientAvatar(name: portrait.targetName, size: 48),
                const SizedBox(width: PortraitorTokens.space14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        portrait.targetName,
                        style: PortraitorTokens.titleSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        portrait.createdAt.isNotEmpty
                            ? _formatDate(portrait.createdAt)
                            : '',
                        style: PortraitorTokens.bodySm,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: PortraitorTokens.inkMuted),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }
}
