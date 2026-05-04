import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';
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
    _start ??= DateTime.now().subtract(const Duration(days: 365));
    _end ??= DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final imported = ref.watch(conversationProvider).pendingImport;
    final totalTokens = imported?.tokenAnalysis.totalTokens ?? 0;

    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        title: const Text('Date Range'),
        actions: [
          TextButton(
            onPressed: () => context.push('/payment'),
            child: Text(
              'Skip',
              style: GoogleFonts.spaceGrotesk(
                color: kAccentPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Info card ───────────────────────────────────────────────
            _LightCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: kGradientStops),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.tune_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filter by date range',
                            style: GoogleFonts.spaceGrotesk(
                              color: kInkStrong,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'A shorter range reduces cost and focuses the portrait on a specific period.',
                            style: GoogleFonts.spaceGrotesk(
                              color: kInkMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Toggle ──────────────────────────────────────────────────
            _LightCard(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enable date filter',
                            style: GoogleFonts.spaceGrotesk(
                              color: kInkStrong,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Only analyze messages in a date range',
                            style: GoogleFonts.spaceGrotesk(
                              color: kInkMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _filterEnabled,
                      onChanged: (v) => setState(() => _filterEnabled = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Date pickers ────────────────────────────────────────────
            AnimatedOpacity(
              opacity: _filterEnabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_filterEnabled,
                child: Column(
                  children: [
                    _DatePickerCard(
                      label: 'Start date',
                      date: _start,
                      onPick: (d) => setState(() => _start = d),
                      firstDate: DateTime(2010),
                      lastDate: _end ?? DateTime.now(),
                    ),
                    const SizedBox(height: 10),
                    _DatePickerCard(
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

            const SizedBox(height: 14),

            // ── Token estimate ──────────────────────────────────────────
            _LightCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kAccentPill,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.data_usage_outlined,
                          color: kAccentPurple, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated tokens',
                          style: GoogleFonts.spaceGrotesk(
                            color: kInkMuted,
                            fontSize: 12,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: kGradientStops,
                          ).createShader(b),
                          child: Text(
                            '~${_fmtTokens(totalTokens)}',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Apply / Skip ────────────────────────────────────────────
            _GradientActionButton(
              label: 'Apply & Continue',
              enabled: _canApply,
              onPressed: _canApply ? _apply : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push('/payment'),
              child: const Text('Skip — Analyze Full Chat'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  bool get _canApply {
    if (!_filterEnabled) return true;
    return _start != null && _end != null && !_end!.isBefore(_start!);
  }

  void _apply() {
    if (_filterEnabled && _start != null && _end != null) {
      ref.read(conversationProvider.notifier).applyDateRange(_start!, _end!);
    }
    context.push('/payment');
  }

  String _fmtTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return n.toString();
  }
}

// ─── Light card ───────────────────────────────────────────────────────────────

class _LightCard extends StatelessWidget {
  final Widget child;
  const _LightCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: kAccentPurple.withValues(alpha: 0.05),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Date picker card ─────────────────────────────────────────────────────────

class _DatePickerCard extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPick;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DatePickerCard({
    required this.label,
    required this.date,
    required this.onPick,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    return _LightCard(
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: firstDate,
            lastDate: lastDate,
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(
                      primary: kAccentPurple,
                    ),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPick(picked);
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kAccentPill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_outlined,
                    color: kAccentPurple, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.spaceGrotesk(
                        color: kInkMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date != null
                          ? '${date!.day}/${date!.month}/${date!.year}'
                          : 'Tap to select',
                      style: GoogleFonts.spaceGrotesk(
                        color: date != null ? kInkStrong : kInkMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: kInkMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Gradient action button ───────────────────────────────────────────────────

class _GradientActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  const _GradientActionButton({
    required this.label,
    required this.enabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: kGradientStopsStrong)
              : null,
          color: enabled ? null : kBorderStrong,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: kAccentPurple.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
