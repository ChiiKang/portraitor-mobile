import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/shared/widgets/funnel_chrome.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_range_slider.dart';

/// Step 3/4 — Configure the read (You / Partner / Family layouts).
class ConfigureScreen extends ConsumerStatefulWidget {
  const ConfigureScreen({super.key});

  @override
  ConsumerState<ConfigureScreen> createState() => _ConfigureScreenState();
}

enum _DatePreset { all, months3, months12, custom }

class _ConfigureScreenState extends ConsumerState<ConfigureScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _partnerA;
  late final TextEditingController _partnerB;
  late final TextEditingController _familyType;
  late List<String> _familySelected;
  _DatePreset _preset = _DatePreset.all;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(funnelDraftProvider);
    final detected = draft.normalized?.detectedNames ?? const <String>[];
    final initial =
        draft.selectedNames.isNotEmpty
            ? draft.selectedNames.first
            : (detected.isNotEmpty ? detected.first : '');
    _nameController = TextEditingController(text: initial);
    _partnerA = TextEditingController(
      text: draft.selectedNames.isNotEmpty ? draft.selectedNames[0] : '',
    );
    _partnerB = TextEditingController(
      text: draft.selectedNames.length > 1 ? draft.selectedNames[1] : '',
    );
    _familyType = TextEditingController();
    _familySelected =
        draft.selectedNames.isNotEmpty
            ? List<String>.from(draft.selectedNames.take(5))
            : (detected.isNotEmpty ? [detected.first] : <String>[]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _partnerA.dispose();
    _partnerB.dispose();
    _familyType.dispose();
    super.dispose();
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
    ref.read(funnelDraftProvider.notifier).setDateRange(start: start, end: end);
  }

  void _continue() {
    final draft = ref.read(funnelDraftProvider);
    final tier = draft.selectedTier;

    List<String> names;
    switch (tier) {
      case FunnelTier.you:
      case FunnelTier.pass:
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          _toast("Enter whose portrait to generate");
          return;
        }
        names = [name];
        break;
      case FunnelTier.partner:
        final a = _partnerA.text.trim();
        final b = _partnerB.text.trim();
        if (a.isEmpty || b.isEmpty) {
          _toast('Enter both names');
          return;
        }
        names = [a, b];
        break;
      case FunnelTier.family:
        if (_familySelected.isEmpty) {
          _toast('Add at least one person');
          return;
        }
        names = List<String>.from(_familySelected);
        break;
    }

    if (!draft.ownConversationConsent) {
      _toast('Confirm consent to continue');
      return;
    }

    ref.read(funnelDraftProvider.notifier).setSelectedNames(names);
    context.push('/funnel/confirm');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(funnelDraftProvider);
    final tier = draft.selectedTier;
    final names = draft.normalized?.detectedNames ?? const <String>[];
    final dateRange = draft.dateRange;
    final start = draft.rangeStart ?? dateRange?.start;
    final end = draft.rangeEnd ?? dateRange?.end;

    return FunnelChrome(
      step: 3,
      title: 'Configure the read',
      lead: tier.configureLead,
      ctaLabel: 'Continue',
      onCta: _continue,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.normalized != null) _SourceCard(draft: draft),
          const SizedBox(height: 20),
          if (tier == FunnelTier.family)
            _FamilyBlock(
              selected: _familySelected,
              suggested: names
                  .where((n) => !_familySelected.contains(n))
                  .toList(),
              typeController: _familyType,
              onAdd: (name) {
                if (_familySelected.length >= 5) return;
                setState(() {
                  if (!_familySelected.contains(name)) {
                    _familySelected = [..._familySelected, name];
                  }
                });
              },
              onRemove: (name) {
                setState(() {
                  _familySelected =
                      _familySelected.where((n) => n != name).toList();
                });
              },
            )
          else ...[
            Text(
              tier == FunnelTier.partner
                  ? 'Which two people in the conversation do you want to analyse?'
                  : 'Which person in the conversation do you want to analyse?',
              style: PortraitorTokens.titleSm.copyWith(
                color: PortraitorTokens.onboardingInk,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                letterSpacing: -0.16,
              ),
            ),
            const SizedBox(height: 12),
            if (tier == FunnelTier.partner)
              Row(
                children: [
                  Expanded(
                    child: _NameField(
                      controller: _partnerA,
                      hint: 'First person',
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NameField(
                      controller: _partnerB,
                      hint: 'Second person',
                      onChanged: (_) {},
                    ),
                  ),
                ],
              )
            else
              _NameField(
                controller: _nameController,
                hint: "Enter the person's name",
                onChanged: (value) {
                  ref.read(funnelDraftProvider.notifier).setSelectedNames(
                        value.trim().isEmpty ? const [] : [value.trim()],
                      );
                },
              ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetectedInitials(
                names: names,
                onPick: (name) {
                  if (tier == FunnelTier.partner) {
                    if (_partnerA.text.trim().isEmpty) {
                      _partnerA.text = name;
                    } else if (_partnerB.text.trim().isEmpty) {
                      _partnerB.text = name;
                    } else {
                      _partnerB.text = name;
                    }
                    setState(() {});
                  } else {
                    _nameController.text = name;
                    ref
                        .read(funnelDraftProvider.notifier)
                        .setSelectedNames([name]);
                    setState(() {});
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
            _SwitchHint(
              partnerMode: tier == FunnelTier.partner,
              onSwitch: () {
                ref.read(funnelDraftProvider.notifier).selectTier(
                      tier == FunnelTier.partner
                          ? FunnelTier.you
                          : FunnelTier.partner,
                    );
                setState(() {});
              },
            ),
          ],
          const SizedBox(height: 22),
          _DatesCard(
            preset: _preset,
            onPreset: _applyPreset,
            dateRange: dateRange,
            start: start,
            end: end,
            onCustomRange: (s, e) {
              setState(() => _preset = _DatePreset.custom);
              ref
                  .read(funnelDraftProvider.notifier)
                  .setDateRange(start: s, end: e);
            },
          ),
          const SizedBox(height: 16),
          const _PrivacyNote(),
          const SizedBox(height: 14),
          _ConsentRow(
            value: draft.ownConversationConsent,
            label: tier.consentLabel,
            onChanged: (value) {
              ref
                  .read(funnelDraftProvider.notifier)
                  .setOwnConversationConsent(value);
            },
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      style: PortraitorTokens.bodyLg.copyWith(
        color: PortraitorTokens.onboardingInk,
        fontFamily: PortraitorTokens.fontBody,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.person_outline_rounded,
          color: PortraitorTokens.onboardingPrimary.withValues(alpha: 0.75),
        ),
        hintText: hint,
        hintStyle: PortraitorTokens.bodyMd.copyWith(
          color: PortraitorTokens.inkDim,
        ),
        filled: true,
        fillColor: const Color(0xFFF3F0FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _DetectedInitials extends StatelessWidget {
  const _DetectedInitials({required this.names, required this.onPick});

  final List<String> names;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Detected:',
          style: PortraitorTokens.bodySm.copyWith(
            color: PortraitorTokens.onboardingMuted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                names.map((name) {
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      PortraitorTokens.radiusPill,
                    ),
                    child: InkWell(
                      onTap: () => onPick(name),
                      borderRadius: BorderRadius.circular(
                        PortraitorTokens.radiusPill,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            PortraitorTokens.radiusPill,
                          ),
                          border: Border.all(color: PortraitorTokens.borderSoft),
                        ),
                        child: Text(
                          _initials(name),
                          style: PortraitorTokens.labelMd.copyWith(
                            fontFamily: PortraitorTokens.fontFamily,
                            fontWeight: FontWeight.w600,
                            color: PortraitorTokens.onboardingInk,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length.clamp(0, 2)).toUpperCase();
    }
    return ((parts[0].isNotEmpty ? parts[0][0] : '') +
            (parts[1].isNotEmpty ? parts[1][0] : ''))
        .toUpperCase();
  }
}

class _SwitchHint extends StatelessWidget {
  const _SwitchHint({required this.partnerMode, required this.onSwitch});

  final bool partnerMode;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          partnerMode ? 'Just one? ' : 'Need two? ',
          style: PortraitorTokens.bodySm.copyWith(
            color: PortraitorTokens.onboardingMuted,
          ),
        ),
        GestureDetector(
          onTap: onSwitch,
          child: Text(
            partnerMode
                ? 'Switch to “Just you”'
                : 'Switch to “You + a partner”',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.onboardingPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyBlock extends StatelessWidget {
  const _FamilyBlock({
    required this.selected,
    required this.suggested,
    required this.typeController,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> selected;
  final List<String> suggested;
  final TextEditingController typeController;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Analyse these people',
                style: PortraitorTokens.titleSm.copyWith(
                  color: PortraitorTokens.onboardingInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '${selected.length} / 5',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.onboardingMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              selected
                  .map(
                    (name) => Chip(
                      label: Text(name),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => onRemove(name),
                      backgroundColor: PortraitorTokens.onboardingPrimary
                          .withValues(alpha: 0.12),
                      labelStyle: PortraitorTokens.labelMd.copyWith(
                        color: PortraitorTokens.onboardingPrimaryDeep,
                      ),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
        ),
        if (suggested.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Suggested from chat',
            style: PortraitorTokens.bodySm.copyWith(
              color: PortraitorTokens.onboardingMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                suggested
                    .map(
                      (name) => ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(name),
                        onPressed:
                            selected.length >= 5 ? null : () => onAdd(name),
                      ),
                    )
                    .toList(),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: typeController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Type a name',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: PortraitorTokens.onboardingPrimary.withValues(
                  alpha: 0.35,
                ),
                style: BorderStyle.solid,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: PortraitorTokens.onboardingPrimary.withValues(
                  alpha: 0.28,
                ),
              ),
            ),
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isEmpty || selected.length >= 5) return;
            onAdd(name);
            typeController.clear();
          },
        ),
      ],
    );
  }
}

class _DatesCard extends StatelessWidget {
  const _DatesCard({
    required this.preset,
    required this.onPreset,
    required this.dateRange,
    required this.start,
    required this.end,
    required this.onCustomRange,
  });

  final _DatePreset preset;
  final ValueChanged<_DatePreset> onPreset;
  final dynamic dateRange;
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime start, DateTime end) onCustomRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Analyse messages from',
            style: PortraitorTokens.titleSm.copyWith(
              color: PortraitorTokens.onboardingInk,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: 'All',
                selected: preset == _DatePreset.all,
                onTap: () => onPreset(_DatePreset.all),
              ),
              _PresetChip(
                label: '3 mo',
                selected: preset == _DatePreset.months3,
                onTap: () => onPreset(_DatePreset.months3),
              ),
              _PresetChip(
                label: '12 mo',
                selected: preset == _DatePreset.months12,
                onTap: () => onPreset(_DatePreset.months12),
              ),
              _PresetChip(
                label: 'Custom',
                selected: preset == _DatePreset.custom,
                onTap: () => onPreset(_DatePreset.custom),
              ),
            ],
          ),
          if (start != null &&
              end != null &&
              dateRange != null &&
              dateRange.end.isAfter(dateRange.start)) ...[
            const SizedBox(height: 12),
            Opacity(
              opacity: preset == _DatePreset.custom ? 1 : 0.5,
              child: IgnorePointer(
                ignoring: preset != _DatePreset.custom,
                child: _DateRangeBlock(
                  spanStart: dateRange.start,
                  spanEnd: dateRange.end,
                  start: start!,
                  end: end!,
                  onChanged: onCustomRange,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
              fontFamily: PortraitorTokens.fontBody,
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
    final other =
        names
            .where((n) => n.toLowerCase() != 'you')
            .take(1)
            .toList();
    final title =
        other.isNotEmpty ? 'Chat with ${other.first}' : 'Imported chat';

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
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
            ),
            child: Text(
              draft.selectedTier == FunnelTier.partner
                  ? 'Partner'
                  : draft.selectedTier.label,
              style: PortraitorTokens.labelSm.copyWith(
                color: Colors.white,
                letterSpacing: 0.02,
                fontWeight: FontWeight.w600,
                fontSize: 12,
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

    final startMs = start.millisecondsSinceEpoch.toDouble().clamp(minMs, maxMs);
    final endMs = end.millisecondsSinceEpoch.toDouble().clamp(minMs, maxMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'From ',
                    style: PortraitorTokens.bodySm.copyWith(
                      color: PortraitorTokens.onboardingMuted,
                    ),
                  ),
                  TextSpan(
                    text: _fmt(start),
                    style: PortraitorTokens.bodySm.copyWith(
                      fontFamily: PortraitorTokens.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'To ',
                    style: PortraitorTokens.bodySm.copyWith(
                      color: PortraitorTokens.onboardingMuted,
                    ),
                  ),
                  TextSpan(
                    text: _fmt(end),
                    style: PortraitorTokens.bodySm.copyWith(
                      fontFamily: PortraitorTokens.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: PortraitorTokens.onboardingInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: PortraitorTokens.onboardingPrimary.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Privacy filter runs automatically — names, emails & numbers '
              'are stripped on your device.',
              style: PortraitorTokens.bodySm.copyWith(
                height: 1.45,
                color: PortraitorTokens.onboardingInkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color:
                    value
                        ? PortraitorTokens.onboardingPrimary
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      value
                          ? PortraitorTokens.onboardingPrimary
                          : PortraitorTokens.borderStrong,
                  width: 1.5,
                ),
              ),
              child:
                  value
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: PortraitorTokens.bodyMd.copyWith(
                  color: PortraitorTokens.onboardingInkSoft,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
