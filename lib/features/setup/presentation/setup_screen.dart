import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:portraitor_mobile/features/funnel/application/funnel_draft_provider.dart';
import 'package:portraitor_mobile/features/import/services/chat_normalizer.dart';
import 'package:portraitor_mobile/features/setup/application/setup_provider.dart';
import 'package:portraitor_mobile/features/import/services/date_parser.dart';
import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_background.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_range_slider.dart';

class SetupScreen extends ConsumerStatefulWidget {
  final String normalizedText;
  final String format;
  final List<String> detectedNames;
  final int messageCount;
  final Map<String, DateTime?>? dateRange;

  const SetupScreen({
    super.key,
    required this.normalizedText,
    required this.format,
    required this.detectedNames,
    required this.messageCount,
    this.dateRange,
  });

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DateRange? range;
      if (widget.dateRange != null &&
          widget.dateRange!['start'] != null &&
          widget.dateRange!['end'] != null) {
        range = DateRange(
          start: widget.dateRange!['start']!,
          end: widget.dateRange!['end']!,
        );
      }
      ref
          .read(setupProvider.notifier)
          .initialize(
            normalizedText: widget.normalizedText,
            detectedNames: widget.detectedNames,
            messageCount: widget.messageCount,
            dateRange: range,
          );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupProvider);

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: PortraitorTokens.space16),
                      _ChatImportedChip(
                        normalizedText: widget.normalizedText,
                        dateRange: widget.dateRange,
                      ),
                      const SizedBox(height: PortraitorTokens.space32),
                      const Text(
                        'Who do you want to analyze?',
                        style: PortraitorTokens.titleSm,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pick a person from the chat or type their name',
                        style: PortraitorTokens.bodySm.copyWith(
                          color: PortraitorTokens.inkMuted,
                        ),
                      ),
                      const SizedBox(height: PortraitorTokens.space16),
                      _NameChips(
                        names: setup.detectedNames,
                        selected: setup.targetName,
                        onSelected: (name) {
                          ref.read(setupProvider.notifier).setTargetName(name);
                          _nameController.text = name;
                        },
                      ),
                      const SizedBox(height: PortraitorTokens.space16),
                      _NameTextField(
                        controller: _nameController,
                        currentName: setup.targetName,
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            ref
                                .read(setupProvider.notifier)
                                .setTargetName(value);
                          }
                        },
                      ),
                      if (setup.fullRangeStart != null &&
                          setup.fullRangeEnd != null) ...[
                        const SizedBox(height: PortraitorTokens.space32),
                        const Text(
                          'Date range',
                          style: PortraitorTokens.titleSm,
                        ),
                        const SizedBox(height: PortraitorTokens.space12),
                        _DateRangeSelector(setup: setup),
                      ],
                      const SizedBox(height: 160),
                    ],
                  ),
                ),
              ),
              _BottomBar(
                tokenEstimate: setup.tokenEstimate,
                onGenerate:
                    setup.targetName.isNotEmpty
                        ? () => _navigateToPayment(setup)
                        : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 28),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              Text(
                'STEP 2 OF 3',
                style: PortraitorTokens.labelSm.copyWith(
                  color: PortraitorTokens.inkMuted,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: const Text(
              'Configure portrait',
              style: PortraitorTokens.titleLg,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToPayment(SetupState setup) {
    final range =
        setup.rangeStart != null && setup.rangeEnd != null
            ? DateRange(start: setup.rangeStart!, end: setup.rangeEnd!)
            : null;
    final draft = ref.read(funnelDraftProvider.notifier);
    draft.setFromImport(
      normalized: NormalizationResult(
        text: setup.filteredText,
        format: ChatFormat.values.firstWhere(
          (value) => value.name == widget.format,
          orElse: () => ChatFormat.unknown,
        ),
        detectedNames: setup.detectedNames,
        messageCount: setup.filteredMessages,
      ),
      dateRange: range,
      tokenEstimate: setup.tokenEstimate,
    );
    draft.setSelectedNames([setup.targetName]);
    context.push('/funnel/plan');
  }
}

class _ChatImportedChip extends StatelessWidget {
  final String normalizedText;
  final Map<String, DateTime?>? dateRange;
  const _ChatImportedChip({required this.normalizedText, this.dateRange});

  @override
  Widget build(BuildContext context) {
    final start = dateRange?['start'];
    final end = dateRange?['end'];
    final dateStr =
        start != null && end != null
            ? _formatMonthRange(start, end)
            : 'Date range unavailable';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF25D366),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conversation imported', style: PortraitorTokens.titleSm),
                Text(
                  dateStr,
                  style: PortraitorTokens.bodySm.copyWith(
                    color: PortraitorTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder:
                    (dialogContext) => _ConversationPreviewDialog(
                      normalizedText: normalizedText,
                      onChange: () {
                        Navigator.of(dialogContext).pop();
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                    ),
              );
            },
            child: Text(
              'View',
              style: PortraitorTokens.labelMd.copyWith(
                color: PortraitorTokens.brandPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMonthRange(DateTime start, DateTime end) {
    final formatter = DateFormat('MMM yyyy');
    return '${formatter.format(start)} – ${formatter.format(end)}';
  }
}

class _ConversationPreviewDialog extends StatelessWidget {
  final String normalizedText;
  final VoidCallback onChange;

  const _ConversationPreviewDialog({
    required this.normalizedText,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          const Expanded(child: Text('Conversation')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: SingleChildScrollView(child: SelectableText(normalizedText)),
      ),
      actions: [TextButton(onPressed: onChange, child: const Text('Change'))],
    );
  }
}

class _NameChips extends StatefulWidget {
  final List<String> names;
  final String selected;
  final ValueChanged<String> onSelected;
  const _NameChips({
    required this.names,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_NameChips> createState() => _NameChipsState();
}

class _NameChipsState extends State<_NameChips> {
  bool _isOverflowing = false;
  bool _checked = false;

  @override
  void didUpdateWidget(covariant _NameChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.names != widget.names) _checked = false;
  }

  void _onScrollMetrics(ScrollMetrics metrics) {
    if (_checked) return;
    final overflows = metrics.maxScrollExtent > 0;
    if (overflows != _isOverflowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isOverflowing = overflows);
      });
    }
    _checked = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _onScrollMetrics(notification.metrics);
            return false;
          },
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children:
                  widget.names.map((name) {
                    final isSelected = name == widget.selected;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onSelected(name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? PortraitorTokens.ink
                                    : PortraitorTokens.surface,
                            borderRadius: BorderRadius.circular(
                              PortraitorTokens.radiusPill,
                            ),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? PortraitorTokens.ink
                                      : PortraitorTokens.borderStrong,
                            ),
                          ),
                          child: Text(
                            name,
                            style: PortraitorTokens.labelMd.copyWith(
                              color:
                                  isSelected
                                      ? Colors.white
                                      : PortraitorTokens.ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
        if (_isOverflowing) ...[
          const SizedBox(height: 6),
          Container(
            height: 3,
            width: 40,
            decoration: BoxDecoration(
              color: PortraitorTokens.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

class _NameTextField extends StatelessWidget {
  final TextEditingController controller;
  final String currentName;
  final ValueChanged<String> onChanged;
  const _NameTextField({
    required this.controller,
    required this.currentName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(
          color: PortraitorTokens.brandPurple.withValues(alpha: 0.5),
        ),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: currentName.isNotEmpty ? currentName : 'Type a name...',
          prefixIcon: Icon(
            Icons.person_outline,
            size: 20,
            color: PortraitorTokens.inkMuted,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

enum _DateRangeOption { all, latest1, latest3, latest6, custom }

class _DateRangeSelector extends StatefulWidget {
  final SetupState setup;
  const _DateRangeSelector({required this.setup});

  @override
  State<_DateRangeSelector> createState() => _DateRangeSelectorState();
}

class _DateRangeSelectorState extends State<_DateRangeSelector> {
  _DateRangeOption _selected = _DateRangeOption.all;

  List<Widget> _buildDateLabels(DateTime fullStart, DateTime fullEnd) {
    final totalMonths =
        (fullEnd.year - fullStart.year) * 12 + fullEnd.month - fullStart.month;
    final labelStyle = PortraitorTokens.bodySm.copyWith(
      color: PortraitorTokens.inkDim,
      fontSize: 11,
    );

    if (totalMonths <= 6) {
      // Short range: show start and end
      return [
        Text(DateFormat('MMM yyyy').format(fullStart), style: labelStyle),
        Text(DateFormat('MMM yyyy').format(fullEnd), style: labelStyle),
      ];
    }

    // Longer range: show ~4 evenly spaced labels
    final labels = <Widget>[];
    final step = totalMonths ~/ 3;
    for (int i = 0; i <= 3; i++) {
      final monthsToAdd = i == 3 ? totalMonths : i * step;
      final date = DateTime(fullStart.year, fullStart.month + monthsToAdd);
      final label =
          i == 0 || i == 3
              ? DateFormat('MMM yyyy').format(date)
              : date.year.toString();
      labels.add(Text(label, style: labelStyle));
    }
    return labels;
  }

  void _applyOption(WidgetRef ref, _DateRangeOption option) {
    final fullStart = widget.setup.fullRangeStart!;
    final fullEnd = widget.setup.fullRangeEnd!;

    setState(() => _selected = option);

    switch (option) {
      case _DateRangeOption.all:
        ref.read(setupProvider.notifier).setDateRange(fullStart, fullEnd);
        break;
      case _DateRangeOption.latest1:
        final start = fullEnd.subtract(const Duration(days: 30));
        ref
            .read(setupProvider.notifier)
            .setDateRange(
              start.isBefore(fullStart) ? fullStart : start,
              fullEnd,
            );
        break;
      case _DateRangeOption.latest3:
        final start = fullEnd.subtract(const Duration(days: 90));
        ref
            .read(setupProvider.notifier)
            .setDateRange(
              start.isBefore(fullStart) ? fullStart : start,
              fullEnd,
            );
        break;
      case _DateRangeOption.latest6:
        final start = fullEnd.subtract(const Duration(days: 180));
        ref
            .read(setupProvider.notifier)
            .setDateRange(
              start.isBefore(fullStart) ? fullStart : start,
              fullEnd,
            );
        break;
      case _DateRangeOption.custom:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.setup.rangeStart!;
    final end = widget.setup.rangeEnd!;
    final fullStart = widget.setup.fullRangeStart!;
    final fullEnd = widget.setup.fullRangeEnd!;
    final totalDays = fullEnd.difference(fullStart).inDays.toDouble();

    if (totalDays <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdown
        Consumer(
          builder: (context, ref, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: PortraitorTokens.surface,
                borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
                border: Border.all(color: PortraitorTokens.borderSoft),
              ),
              child: DropdownButton<_DateRangeOption>(
                value: _selected,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: PortraitorTokens.inkMuted,
                ),
                style: PortraitorTokens.labelMd.copyWith(
                  color: PortraitorTokens.ink,
                ),
                items:
                    _DateRangeOption.values.map((option) {
                      final labels = {
                        _DateRangeOption.all: 'Process all messages',
                        _DateRangeOption.latest1: 'Latest 1 month',
                        _DateRangeOption.latest3: 'Latest 3 months',
                        _DateRangeOption.latest6: 'Latest 6 months',
                        _DateRangeOption.custom: 'Custom range',
                      };
                      return DropdownMenuItem(
                        value: option,
                        child: Text(labels[option]!),
                      );
                    }).toList(),
                onChanged: (option) {
                  if (option != null) _applyOption(ref, option);
                },
              ),
            );
          },
        ),

        // Range slider (shown for presets + custom, hidden for "all")
        if (_selected != _DateRangeOption.all) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'FROM',
                  style: PortraitorTokens.labelSm.copyWith(
                    color: PortraitorTokens.inkMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  'TO',
                  style: PortraitorTokens.labelSm.copyWith(
                    color: PortraitorTokens.inkMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Opacity(
            opacity: _selected == _DateRangeOption.custom ? 1.0 : 0.5,
            child: IgnorePointer(
              ignoring: _selected != _DateRangeOption.custom,
              child: Consumer(
                builder: (context, ref, _) {
                  return GradientRangeSlider(
                    startValue: start.difference(fullStart).inDays.toDouble(),
                    endValue: end.difference(fullStart).inDays.toDouble(),
                    min: 0,
                    max: totalDays,
                    startLabel: DateParser.formatDateShort(fullStart),
                    endLabel: DateParser.formatDateShort(fullEnd),
                    onChanged: (values) {
                      final newStart = fullStart.add(
                        Duration(days: values.start.round()),
                      );
                      final newEnd = fullStart.add(
                        Duration(days: values.end.round()),
                      );
                      ref
                          .read(setupProvider.notifier)
                          .setDateRange(newStart, newEnd);
                    },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _buildDateLabels(fullStart, fullEnd),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${DateFormat('MMM yyyy').format(start)} — ${DateFormat('MMM yyyy').format(end)}',
              style: PortraitorTokens.labelMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              _selected == _DateRangeOption.custom
                  ? 'Custom range selected'
                  : 'Select "Custom range" to drag',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.inkMuted,
              ),
            ),
          ),
        ],

        if (_selected == _DateRangeOption.all) const SizedBox(height: 12),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int tokenEstimate;
  final VoidCallback? onGenerate;

  const _BottomBar({required this.tokenEstimate, this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: PortraitorTokens.surface,
        border: Border(top: BorderSide(color: PortraitorTokens.borderSoft)),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOKEN ESTIMATE',
                  style: PortraitorTokens.labelSm.copyWith(
                    color: PortraitorTokens.inkMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '~${_formatTokens(tokenEstimate)}',
                  style: PortraitorTokens.titleMd,
                ),
              ],
            ),
          ),
          const SizedBox(height: PortraitorTokens.space16),
          GradientButton(
            onPressed: onGenerate,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('Generate portrait'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(0)},${(tokens % 1000).toString().padLeft(3, '0')}';
    }
    return tokens.toString();
  }
}
