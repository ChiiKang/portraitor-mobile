import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/runtime_config_provider.dart';
import '../providers/setup_provider.dart';
import '../services/date_parser.dart';
import '../theme/tokens.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_button.dart';
import '../widgets/gradient_range_slider.dart';

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
      if (widget.dateRange != null && widget.dateRange!['start'] != null && widget.dateRange!['end'] != null) {
        range = DateRange(
          start: widget.dateRange!['start']!,
          end: widget.dateRange!['end']!,
        );
      }
      ref.read(setupProvider.notifier).initialize(
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
    final configAsync = ref.watch(runtimeConfigProvider);
    final price = configAsync.valueOrNull?.priceUsd ?? 5.0;

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
                        format: widget.format,
                        messageCount: widget.messageCount,
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
                        style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                      ),
                      const SizedBox(height: PortraitorTokens.space16),
                      _NameChips(
                        names: setup.detectedNames,
                        selected: setup.targetName,
                        onSelected: (name) => ref.read(setupProvider.notifier).setTargetName(name),
                      ),
                      const SizedBox(height: PortraitorTokens.space16),
                      _NameTextField(
                        controller: _nameController,
                        currentName: setup.targetName,
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            ref.read(setupProvider.notifier).setTargetName(value);
                          }
                        },
                      ),
                      if (setup.fullRangeStart != null && setup.fullRangeEnd != null) ...[
                        const SizedBox(height: PortraitorTokens.space32),
                        const Text('Date range', style: PortraitorTokens.titleSm),
                        const SizedBox(height: PortraitorTokens.space12),
                        _DateRangeCard(setup: setup),
                      ],
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
              _BottomBar(
                tokenEstimate: setup.tokenEstimate,
                price: price,
                onGenerate: setup.targetName.isNotEmpty
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
            child: const Text('Configure portrait', style: PortraitorTokens.titleLg),
          ),
        ],
      ),
    );
  }

  void _navigateToPayment(SetupState setup) {
    context.push('/payment', extra: {
      'normalizedText': setup.filteredText,
      'targetName': setup.targetName,
      'tokenEstimate': setup.tokenEstimate,
    });
  }
}

class _ChatImportedChip extends StatelessWidget {
  final String format;
  final int messageCount;
  final Map<String, DateTime?>? dateRange;
  const _ChatImportedChip({required this.format, required this.messageCount, this.dateRange});

  @override
  Widget build(BuildContext context) {
    String dateStr = '';
    if (dateRange != null && dateRange!['start'] != null && dateRange!['end'] != null) {
      final start = dateRange!['start']!;
      final end = dateRange!['end']!;
      dateStr = ' · ${DateFormat.MMM().format(start)} – ${DateFormat.MMM().format(end)} ${end.year}';
    }

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
                Text(
                  '${_formatName(format)} chat imported',
                  style: PortraitorTokens.titleSm,
                ),
                Text(
                  '$messageCount messages$dateStr',
                  style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.inkMuted),
                ),
              ],
            ),
          ),
          Text(
            'Change',
            style: PortraitorTokens.labelMd.copyWith(color: PortraitorTokens.brandPurple),
          ),
        ],
      ),
    );
  }

  String _formatName(String format) {
    switch (format.toLowerCase()) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'telegram':
        return 'Telegram';
      case 'imessage':
        return 'iMessage';
      default:
        return format[0].toUpperCase() + format.substring(1);
    }
  }
}

class _NameChips extends StatelessWidget {
  final List<String> names;
  final String selected;
  final ValueChanged<String> onSelected;
  const _NameChips({required this.names, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: names.map((name) {
        final isSelected = name == selected;
        return GestureDetector(
          onTap: () => onSelected(name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? PortraitorTokens.ink : PortraitorTokens.surface,
              borderRadius: BorderRadius.circular(PortraitorTokens.radiusPill),
              border: Border.all(
                color: isSelected ? PortraitorTokens.ink : PortraitorTokens.borderStrong,
              ),
            ),
            child: Text(
              name,
              style: PortraitorTokens.labelMd.copyWith(
                color: isSelected ? Colors.white : PortraitorTokens.ink,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NameTextField extends StatelessWidget {
  final TextEditingController controller;
  final String currentName;
  final ValueChanged<String> onChanged;
  const _NameTextField({required this.controller, required this.currentName, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusLg),
        border: Border.all(color: PortraitorTokens.brandPurple.withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: currentName.isNotEmpty ? currentName : 'Type a name...',
          prefixIcon: Icon(Icons.person_outline, size: 20, color: PortraitorTokens.inkMuted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _DateRangeCard extends StatelessWidget {
  final SetupState setup;
  const _DateRangeCard({required this.setup});

  @override
  Widget build(BuildContext context) {
    final start = setup.rangeStart!;
    final end = setup.rangeEnd!;
    final fullStart = setup.fullRangeStart!;
    final fullEnd = setup.fullRangeEnd!;

    final totalDays = fullEnd.difference(fullStart).inDays.toDouble();
    if (totalDays <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(PortraitorTokens.space20),
      decoration: BoxDecoration(
        color: PortraitorTokens.surface,
        borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
        border: Border.all(color: PortraitorTokens.borderSoft),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FROM',
                    style: PortraitorTokens.labelSm.copyWith(
                      color: PortraitorTokens.inkMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM d, yyyy').format(start),
                    style: PortraitorTokens.titleSm,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TO',
                    style: PortraitorTokens.labelSm.copyWith(
                      color: PortraitorTokens.inkMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM d, yyyy').format(end),
                    style: PortraitorTokens.titleSm,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, ref, _) {
              return GradientRangeSlider(
                startValue: start.difference(fullStart).inDays.toDouble(),
                endValue: end.difference(fullStart).inDays.toDouble(),
                min: 0,
                max: totalDays,
                startLabel: DateParser.formatDateShort(start),
                endLabel: DateParser.formatDateShort(end),
                onChanged: (values) {
                  final newStart = fullStart.add(Duration(days: values.start.round()));
                  final newEnd = fullStart.add(Duration(days: values.end.round()));
                  ref.read(setupProvider.notifier).setDateRange(newStart, newEnd);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${setup.filteredMessages} of ${setup.totalMessages} messages',
            style: PortraitorTokens.bodySm.copyWith(color: PortraitorTokens.brandPurple),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int tokenEstimate;
  final double price;
  final VoidCallback? onGenerate;

  const _BottomBar({
    required this.tokenEstimate,
    required this.price,
    this.onGenerate,
  });

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PRICE',
                    style: PortraitorTokens.labelSm.copyWith(
                      color: PortraitorTokens.inkMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: PortraitorTokens.titleMd.copyWith(color: PortraitorTokens.brandPurple),
                  ),
                ],
              ),
            ],
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
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)},${(tokens % 1000).toString().padLeft(3, '0')}';
    return tokens.toString();
  }
}
