import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_range_slider.dart';

/// Step 3/4 — Configure the read.
/// You tier is interactive; Partner/Family land here only if ungated later.
class ConfigureScreen extends ConsumerStatefulWidget {
  const ConfigureScreen({super.key});

  @override
  ConsumerState<ConfigureScreen> createState() => _ConfigureScreenState();
}

enum _DatePreset { all, months3, months12, custom }

class _ConfigureScreenState extends ConsumerState<ConfigureScreen> {
  late final TextEditingController _nameController;
  _DatePreset _preset = _DatePreset.all;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(funnelDraftProvider);
    final initial =
        draft.selectedNames.isNotEmpty
            ? draft.selectedNames.first
            : (draft.normalized?.detectedNames.isNotEmpty == true
                ? draft.normalized!.detectedNames.first
                : '');
    _nameController = TextEditingController(text: initial);
  }

  void _applyPreset(_DatePreset preset) {
    final span = ref.read(funnelDraftProvider).dateRange;
    setState(() => _preset = preset);
    if (span == null) return;
    final end = span.end;
    DateTime start;
    switch (preset) {
      case _DatePreset.all:
        start = span.start;
        break;
      case _DatePreset.months3:
        start = DateTime(end.year, end.month - 3, end.day);
        if (start.isBefore(span.start)) start = span.start;
        break;
      case _DatePreset.months12:
        start = DateTime(end.year - 1, end.month, end.day);
        if (start.isBefore(span.start)) start = span.start;
        break;
      case _DatePreset.custom:
        start = ref.read(funnelDraftProvider).rangeStart ?? span.start;
        break;
    }
    ref.read(funnelDraftProvider.notifier).setDateRange(
          start: start,
          end: end,
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _continue() {
    final draft = ref.read(funnelDraftProvider);
    if (!draft.selectedTier.isEnabledInV1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${draft.selectedTier.label} isn’t available yet.',
          ),
        ),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter whose portrait to generate')),
      );
      return;
    }
    if (!draft.ownConversationConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm this is your own conversation to continue'),
        ),
      );
      return;
    }
    ref.read(funnelDraftProvider.notifier).setSelectedNames([name]);
    context.push('/funnel/confirm');
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final names = draft.normalized?.detectedNames ?? const <String>[];
    final dateRange = draft.dateRange;
    final start = draft.rangeStart ?? dateRange?.start;
    final end = draft.rangeEnd ?? dateRange?.end;

    return FunnelChrome(
      step: 3,
      title: 'Configure the read',
      lead: 'One portrait for the person you choose.',
      ctaLabel: 'Continue — ${draft.selectedTier.priceLabel}',
      onCta: _continue,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.normalized != null) _SourceCard(draft: draft),
          const SizedBox(height: 20),
          Text(
            'Which person in the conversation do you want to analyse?',
            style: PortraitorTokens.titleSm.copyWith(
              color: PortraitorTokens.onboardingInk,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: PortraitorTokens.bodyLg.copyWith(
              color: PortraitorTokens.onboardingInk,
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.person_outline),
              hintText: "Enter the person's name",
              filled: true,
              fillColor: const Color(0xFFF3F0FF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              ref.read(funnelDraftProvider.notifier).setSelectedNames(
                    value.trim().isEmpty ? const [] : [value.trim()],
                  );
            },
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Detected:', style: PortraitorTokens.bodySm),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  names
                      .map(
                        (name) => ActionChip(
                          label: Text(_initials(name)),
                          onPressed: () {
                            _nameController.text = name;
                            ref
                                .read(funnelDraftProvider.notifier)
                                .setSelectedNames([name]);
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Analyse messages from',
            style: PortraitorTokens.titleSm.copyWith(
              color: PortraitorTokens.onboardingInk,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          if (start != null &&
              end != null &&
              dateRange != null &&
              dateRange.end.isAfter(dateRange.start))
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: PortraitorTokens.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PresetChip(
                        label: 'All',
                        selected: _preset == _DatePreset.all,
                        onTap: () => _applyPreset(_DatePreset.all),
                      ),
                      _PresetChip(
                        label: '3 mo',
                        selected: _preset == _DatePreset.months3,
                        onTap: () => _applyPreset(_DatePreset.months3),
                      ),
                      _PresetChip(
                        label: '12 mo',
                        selected: _preset == _DatePreset.months12,
                        onTap: () => _applyPreset(_DatePreset.months12),
                      ),
                      _PresetChip(
                        label: 'Custom',
                        selected: _preset == _DatePreset.custom,
                        onTap: () => _applyPreset(_DatePreset.custom),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: _preset == _DatePreset.custom ? 1 : 0.45,
                    child: IgnorePointer(
                      ignoring: _preset != _DatePreset.custom,
                      child: _DateRangeBlock(
                        spanStart: dateRange.start,
                        spanEnd: dateRange.end,
                        start: start,
                        end: end,
                        onChanged: (s, e) {
                          setState(() => _preset = _DatePreset.custom);
                          ref
                              .read(funnelDraftProvider.notifier)
                              .setDateRange(start: s, end: e);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Process all messages',
              style: PortraitorTokens.bodyMd.copyWith(
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
          const SizedBox(height: 20),
          const _PrivacyNote(),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.ownConversationConsent,
            onChanged: (value) {
              ref
                  .read(funnelDraftProvider.notifier)
                  .setOwnConversationConsent(value ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'This is my own conversation — a chat I’m part of.',
              style: PortraitorTokens.bodyMd.copyWith(
                color: PortraitorTokens.onboardingInkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
    }
    return (parts[0].isNotEmpty ? parts[0][0] : '') +
        (parts[1].isNotEmpty ? parts[1][0] : '');
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected
              ? PortraitorTokens.onboardingPrimary.withValues(alpha: 0.14)
              : PortraitorTokens.surfaceMuted,
      borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: PortraitorTokens.labelMd.copyWith(
              color:
                  selected
                      ? PortraitorTokens.onboardingPrimary
                      : PortraitorTokens.onboardingMuted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.draft});

  final FunnelDraft draft;

  @override
  Widget build(BuildContext context) {
    final count = draft.normalized?.messageCount ?? 0;
    final names = draft.normalized?.detectedNames ?? const <String>[];
    final title =
        names.length >= 2
            ? 'Chat with ${names.where((n) => n.toLowerCase() != 'you').take(1).join()}'
            : 'Imported chat';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: PortraitorTokens.onboardingBrandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.forum_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PortraitorTokens.titleSm.copyWith(color: Colors.white),
                ),
                Text(
                  '$count messages',
                  style: PortraitorTokens.bodySm.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
            ),
            child: Text(
              draft.selectedTier.label,
              style: PortraitorTokens.labelSm.copyWith(
                color: Colors.white,
                letterSpacing: 0.04,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeBlock extends StatelessWidget {
  const _DateRangeBlock({
    required this.spanStart,
    required this.spanEnd,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime spanStart;
  final DateTime spanEnd;
  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onChanged;

  @override
  Widget build(BuildContext context) {
    final minMs = spanStart.millisecondsSinceEpoch.toDouble();
    final maxMs = spanEnd.millisecondsSinceEpoch.toDouble();
    if (maxMs <= minMs) {
      return Text(
        'Process all messages',
        style: PortraitorTokens.bodyMd.copyWith(
          color: PortraitorTokens.onboardingMuted,
        ),
      );
    }

    final startMs = start.millisecondsSinceEpoch
        .toDouble()
        .clamp(minMs, maxMs);
    final endMs = end.millisecondsSinceEpoch.toDouble().clamp(minMs, maxMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(start), style: PortraitorTokens.bodySm),
            Text(_fmt(end), style: PortraitorTokens.bodySm),
          ],
        ),
        GradientRangeSlider(
          startValue: startMs <= endMs ? startMs : minMs,
          endValue: endMs >= startMs ? endMs : maxMs,
          min: minMs,
          max: maxMs,
          onChanged: (values) {
            onChanged(
              DateTime.fromMillisecondsSinceEpoch(values.start.round()),
              DateTime.fromMillisecondsSinceEpoch(values.end.round()),
            );
          },
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 20,
            color: PortraitorTokens.onboardingPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Privacy filter strips names, emails, and numbers on-device before '
              'analysis. It runs automatically when you generate — no action needed.',
              style: PortraitorTokens.bodySm.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
