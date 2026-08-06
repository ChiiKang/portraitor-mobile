import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/pending_job_resume_sheet.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';

/// Screen 04 from the approved mobile handover.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pendingJobRecoveryProvider.notifier).refresh();
    });
  }

  void _openAddConversation() => context.push('/funnel/add');

  @override
  Widget build(BuildContext context) {
    final portraits = ref.watch(portraitsProvider);

    ref.listen(processingProvider, (previous, next) {
      if (previous?.status != ProcessingStatus.done &&
          next.status == ProcessingStatus.done) {
        ref.read(portraitsProvider.notifier).loadPortraits();
      }
    });
    ref.listen(pendingJobRecoveryProvider, (previous, next) {
      if (next.isLoading || next.hasShownSheet) return;
      final classification = next.nextToShow;
      if (classification == null) return;
      ref.read(pendingJobRecoveryProvider.notifier).markSheetShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          showPendingJobResumeSheet(context, classification: classification);
        }
      });
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFBFAFF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.25,
            colors: [Color(0xFFEDE7FF), Color(0xFFFBFAFF), Color(0xFFFCEFF5)],
            stops: [0, .42, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _HomeHeader(onSettings: () => context.push('/settings')),
                    const SizedBox(height: 14),
                    _PassChip(onManage: () => context.push('/profile')),
                    const SizedBox(height: 14),
                    _NewPortraitCard(onStart: _openAddConversation),
                    const SizedBox(height: 26),
                    _RecentPortraits(
                      portraits: portraits.portraits,
                      onSeeAll: () => context.push('/library'),
                      onPortrait:
                          (portrait) => context.push('/result/${portrait.id}'),
                    ),
                  ],
                ),
              ),
              _HomeTabBar(
                onHome: () => context.go('/home'),
                onPortraits: () => context.push('/library'),
                onProfile: () => context.push('/profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipOval(
          child: Image.asset(
            'assets/brand/portraitor-logo.png',
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF7C5CFF),
                  ),
                ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Portraitor',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF211A37),
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Open profile settings',
          child: InkResponse(
            onTap: onSettings,
            radius: 24,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x14211A37)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D211A37),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                    spreadRadius: -6,
                  ),
                ],
              ),
              alignment: const Alignment(0, -.14),
              child: const Text(
                '···',
                style: TextStyle(
                  color: Color(0xFF6B6480),
                  fontSize: 15,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PassChip extends StatelessWidget {
  const _PassChip({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pass, 7 of 10 left. Manage pass.',
      child: InkWell(
        onTap: onManage,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFBF5E9), Color(0xFFF6ECD6)],
            ),
            border: Border.all(color: const Color(0x52B8912F)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SvgPicture.string(_passSvg, width: 16, height: 16),
              const SizedBox(width: 8),
              const Text(
                'Pass · 7 of 10 left',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A6A1E),
                ),
              ),
              const Spacer(),
              const Text(
                'Manage →',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA17E26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPortraitCard extends StatelessWidget {
  const _NewPortraitCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.45,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'docs/handover_mobile_01-04/assets/04-home-card-bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-.18, -1),
                  end: Alignment(1, 1),
                  colors: [
                    Color(0xEB5B3CB4),
                    Color(0xC77C3CC8),
                    Color(0x73A855F7),
                    Color(0x47EC4899),
                  ],
                  stops: [0, .42, .66, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NEW PORTRAIT',
                    style: TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Analyze a new\nconversation',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Share a chat or upload an\nexport',
                    style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Start a new portrait',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onStart,
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF211A37),
                              width: 2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add,
                                size: 20,
                                color: Color(0xFF211A37),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Start',
                                style: TextStyle(
                                  color: Color(0xFF211A37),
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPortraits extends StatelessWidget {
  const _RecentPortraits({
    required this.portraits,
    required this.onSeeAll,
    required this.onPortrait,
  });

  final List<Portrait> portraits;
  final VoidCallback onSeeAll;
  final ValueChanged<Portrait> onPortrait;

  @override
  Widget build(BuildContext context) {
    final rows =
        portraits.isEmpty
            ? const <_PortraitPreview>[
              _PortraitPreview(
                'Sarah',
                'PARTNER',
                '2 days ago',
                'S',
                _sarahGradient,
              ),
              _PortraitPreview(
                'Mom',
                'FAMILY',
                '1 week ago',
                'M',
                _momGradient,
              ),
            ]
            : portraits
                .take(2)
                .map(
                  (portrait) => _PortraitPreview(
                    portrait.targetName.isEmpty
                        ? 'Portrait'
                        : portrait.targetName,
                    portrait.mode.toUpperCase(),
                    portrait.title,
                    portrait.targetName.isEmpty
                        ? 'P'
                        : portrait.targetName.characters.first.toUpperCase(),
                    _momGradient,
                    portrait: portrait,
                  ),
                )
                .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent portraits',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF211A37),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(44, 36),
              ),
              child: const Text(
                'See all',
                style: TextStyle(
                  color: Color(0xFF7C5CFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var index = 0; index < rows.length; index++) ...[
          _PortraitPreviewRow(
            preview: rows[index],
            onTap:
                rows[index].portrait == null
                    ? null
                    : () => onPortrait(rows[index].portrait!),
          ),
          if (index != rows.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _PortraitPreview {
  const _PortraitPreview(
    this.name,
    this.relationship,
    this.time,
    this.initial,
    this.gradient, {
    this.portrait,
  });

  final String name;
  final String relationship;
  final String time;
  final String initial;
  final LinearGradient gradient;
  final Portrait? portrait;
}

class _PortraitPreviewRow extends StatelessWidget {
  const _PortraitPreviewRow({required this.preview, required this.onTap});

  final _PortraitPreview preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '${preview.name}, ${preview.relationship}, ${preview.time}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0x0F211A37)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D211A37),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: preview.gradient,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    preview.initial,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              preview.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF211A37),
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1F7C5CFF),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              preview.relationship,
                              style: const TextStyle(
                                color: Color(0xFF6B4AF0),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .66,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        preview.time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8C86A0),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SvgPicture.string(_chevronSvg, width: 16, height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTabBar extends StatelessWidget {
  const _HomeTabBar({
    required this.onHome,
    required this.onPortraits,
    required this.onProfile,
  });

  final VoidCallback onHome;
  final VoidCallback onPortraits;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xD9FFFFFF),
            border: Border(top: BorderSide(color: Color(0x0A211A37))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 11, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _HomeTab(
                    label: 'Home',
                    icon: _homeSvg,
                    active: true,
                    onTap: onHome,
                  ),
                  _HomeTab(
                    label: 'Portraits',
                    icon: _portraitsSvg,
                    onTap: onPortraits,
                  ),
                  _HomeTab(
                    label: 'Profile',
                    icon: _profileSvg,
                    onTap: onProfile,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF7C5CFF) : const Color(0xFFB4AEC4);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                child: SvgPicture.string(icon, width: 21, height: 21),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _sarahGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF9B86E8), Color(0xFFEC4899)],
);
const _momGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6D52FF), Color(0xFFA855F7)],
);

const _passSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h11A2.5 2.5 0 0 1 20 8.5v7A2.5 2.5 0 0 1 17.5 18h-11A2.5 2.5 0 0 1 4 15.5v-7Z" stroke="#96712A" stroke-width="1.8"/><path d="M4 10h16" stroke="#96712A" stroke-width="1.8"/></svg>''';
const _chevronSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m9 6 6 6-6 6" stroke="#C4BED4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''';
const _homeSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m4 11 8-6 8 6M6 10v9h12v-9" stroke="#7C5CFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''';
const _portraitsSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="4" y="5" width="16" height="13" rx="3" stroke="#B4AEC4" stroke-width="2"/><path d="M8 10h8M8 13h5" stroke="#B4AEC4" stroke-width="2" stroke-linecap="round"/></svg>''';
const _profileSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="8" r="3.4" stroke="#B4AEC4" stroke-width="2"/><path d="M5.5 20c.7-3.7 3.2-5.6 6.5-5.6s5.8 1.9 6.5 5.6" stroke="#B4AEC4" stroke-width="2" stroke-linecap="round"/></svg>''';
