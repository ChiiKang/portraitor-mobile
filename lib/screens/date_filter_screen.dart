import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/conversation_provider.dart';

class DateFilterScreen extends ConsumerStatefulWidget {
  const DateFilterScreen({super.key});

  @override
  ConsumerState<DateFilterScreen> createState() => _DateFilterScreenState();
}

class _DateFilterScreenState extends ConsumerState<DateFilterScreen> {
  DateTime? _start;
  DateTime? _end;
  bool _filterEnabled = false;

  @override
  void initState() {
    super.initState();
    final imported = ref.read(conversationProvider).pendingImport;
    if (imported != null) {
      _start = imported.firstDate;
      _end = imported.lastDate;
    }
    // Default to a wide range if no dates detected.
    _start ??= DateTime.now().subtract(const Duration(days: 365));
    _end ??= DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imported = ref.watch(conversationProvider).pendingImport;

    // Token estimate for the current range.
    final totalTokens = imported?.tokenAnalysis.totalTokens ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Date Range Filter'),
        actions: [
          TextButton(
            onPressed: () => context.push('/payment'),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Info card ───────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.tune_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Filter by date range',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Analyzing a shorter range reduces cost and focuses the portrait on a specific period.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Toggle ──────────────────────────────────────────────────
            Card(
              child: SwitchListTile(
                title: const Text('Enable date filter'),
                subtitle: const Text('Only analyze messages in a date range'),
                value: _filterEnabled,
                onChanged: (v) => setState(() => _filterEnabled = v),
                activeThumbColor: theme.colorScheme.primary,
                activeTrackColor: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),

            const SizedBox(height: 16),

            // ── Date pickers ────────────────────────────────────────────
            AnimatedOpacity(
              opacity: _filterEnabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_filterEnabled,
                child: Column(
                  children: [
                    _DatePickerTile(
                      label: 'Start date',
                      date: _start,
                      onPick: (d) => setState(() => _start = d),
                      firstDate: DateTime(2010),
                      lastDate: _end ?? DateTime.now(),
                    ),
                    const SizedBox(height: 8),
                    _DatePickerTile(
                      label: 'End date',
                      date: _end,
                      onPick: (d) => setState(() => _end = d),
                      firstDate: _start ?? DateTime(2010),
                      lastDate: DateTime.now(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Token estimate ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.data_usage_outlined,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated tokens',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          '~${_fmtTokens(totalTokens)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Apply / Skip ────────────────────────────────────────────
            ElevatedButton(
              onPressed: _canApply ? _apply : null,
              child: const Text('Apply & Continue'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push('/payment'),
              child: const Text('Skip — Analyze Full Chat'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canApply {
    if (!_filterEnabled) return true;
    return _start != null &&
        _end != null &&
        !_end!.isBefore(_start!);
  }

  void _apply() {
    if (_filterEnabled && _start != null && _end != null) {
      ref
          .read(conversationProvider.notifier)
          .applyDateRange(_start!, _end!);
    }
    context.push('/payment');
  }

  String _fmtTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return n.toString();
  }
}

// ─── Date picker tile ─────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPick;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onPick,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: Icon(
          Icons.event_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(label, style: theme.textTheme.bodySmall),
        subtitle: Text(
          date != null
              ? '${date!.day}/${date!.month}/${date!.year}'
              : 'Tap to select',
          style: theme.textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: firstDate,
            lastDate: lastDate,
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme,
                ),
                child: child!,
              );
            },
          );
          if (picked != null) onPick(picked);
        },
      ),
    );
  }
}
