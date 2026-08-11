import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/features/processing/application/pending_job_recovery_provider.dart';
import 'package:portraitor_mobile/features/processing/application/processing_provider.dart';
import 'package:portraitor_mobile/features/processing/presentation/pending_job_resume_sheet.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';
import 'package:portraitor_mobile/shared/models/portrait_session.dart';
import 'package:portraitor_mobile/shared/widgets/main_tab_shell.dart';
import 'package:portraitor_mobile/shared/widgets/session_card.dart';

/// Home tab — matches Open Design prototype (logo, Pass chip, hero, compact Recent).
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
    final sessions =
        portraits.portraits.isEmpty
            ? PortraitSession.demoSessions()
            : PortraitSession.fromPortraits(portraits.portraits);
    final bottomPad = mainTabContentBottomInset(context);

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
      backgroundColor: PortraitorTokens.onboardingSurface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: PortraitorTokens.tabPageGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPad),
            children: [
              _HomeHeader(onSettings: () => context.push('/settings')),
              const SizedBox(height: 14),
              _PassChip(onManage: () => context.go('/profile')),
              const SizedBox(height: 14),
              _NewPortraitCard(onStart: _openAddConversation),
              const SizedBox(height: 26),
              _RecentSection(
                sessions: sessions.take(2).toList(),
                isDemo: portraits.portraits.isEmpty,
                onSeeAll: () => context.go('/library'),
                onSession: (session) {
                  if (portraits.portraits.isEmpty ||
                      session.resultIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Demo session — generate a portrait to open a real result',
                        ),
                      ),
                    );
                    return;
                  }
                  context.push('/result/${session.resultIds.first}');
                },
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
        const _PortraitorBrand(),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Open settings',
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

class _PortraitorBrand extends StatelessWidget {
  const _PortraitorBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9475E1), Color(0xFFE8B4A6)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F46375F),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SizedBox(width: 28, height: 28),
        ),
        SizedBox(width: 9),
        Text(
          'Portraitor',
          style: TextStyle(
            fontFamily: PortraitorTokens.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            height: 1.1,
            color: PortraitorTokens.onboardingInk,
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
      label: 'Pass, 9 of 10 left. Manage pass.',
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
                'Pass · 9 of 10 left',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A6A1E),
                ),
              ),
              const Spacer(),
              const Text(
                'Manage →',
                style: TextStyle(
                  fontFamily: PortraitorTokens.fontBody,
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
                      fontFamily: PortraitorTokens.fontFamily,
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
                      fontFamily: PortraitorTokens.fontFamily,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Share a chat or upload an\nexport',
                    style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontFamily: PortraitorTokens.fontBody,
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
                                  fontFamily: PortraitorTokens.fontFamily,
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

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.sessions,
    required this.isDemo,
    required this.onSeeAll,
    required this.onSession,
  });

  final List<PortraitSession> sessions;
  final bool isDemo;
  final VoidCallback onSeeAll;
  final ValueChanged<PortraitSession> onSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent',
              style: TextStyle(
                fontFamily: PortraitorTokens.fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: PortraitorTokens.onboardingInk,
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
                  fontFamily: PortraitorTokens.fontBody,
                  color: PortraitorTokens.onboardingPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (isDemo)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Demo samples — your generations will appear here',
              style: PortraitorTokens.bodySm.copyWith(
                color: PortraitorTokens.onboardingMuted,
              ),
            ),
          ),
        const SizedBox(height: 4),
        for (var i = 0; i < sessions.length; i++) ...[
          SessionCard(
            session: sessions[i],
            compact: true,
            onTap: () => onSession(sessions[i]),
          ),
          if (i != sessions.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

const _passSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h11A2.5 2.5 0 0 1 20 8.5v7A2.5 2.5 0 0 1 17.5 18h-11A2.5 2.5 0 0 1 4 15.5v-7Z" stroke="#96712A" stroke-width="1.8"/><path d="M4 10h16" stroke="#96712A" stroke-width="1.8"/></svg>''';
