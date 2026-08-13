import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';

/// Persistent Home / Portraits / Profile glass dock (prototype `.home-tabs`).
class MainTabShell extends StatelessWidget {
  const MainTabShell({super.key, required this.child});

  final Widget child;

  static const tabPaths = {'/home', '/library', '/profile'};

  static int indexFor(String path) {
    if (path.startsWith('/library')) return 1;
    if (path.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = indexFor(path);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 14,
          right: 14,
          bottom: bottom + 4,
          child: _GlassTabDock(
            index: index,
            onSelect: (i) {
              switch (i) {
                case 0:
                  context.go('/home');
                case 1:
                  context.go('/library');
                case 2:
                  context.go('/profile');
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Bottom inset for tab roots so content clears the floating dock.
double mainTabContentBottomInset(BuildContext context) {
  return 88 + MediaQuery.viewPaddingOf(context).bottom;
}

/// Shows transient feedback above the floating tab dock instead of beneath it.
void showMainTabSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          mainTabContentBottomInset(context),
        ),
        content: Text(message),
      ),
    );
}

class _GlassTabDock extends StatelessWidget {
  const _GlassTabDock({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.72),
                const Color(0xAAF5E8FF),
                const Color(0x99FCE8F3),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x4D211A37).withValues(alpha: 0.24),
                blurRadius: 28,
                offset: const Offset(0, 10),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              children: [
                Expanded(
                  child: _TabItem(
                    label: 'Home',
                    svg: _homeSvg,
                    active: index == 0,
                    onTap: () => onSelect(0),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    label: 'Portraits',
                    svg: _portraitsSvg,
                    active: index == 1,
                    onTap: () => onSelect(1),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    label: 'Profile',
                    svg: _profileSvg,
                    active: index == 2,
                    onTap: () => onSelect(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.svg,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String svg;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        active
            ? PortraitorTokens.onboardingPrimaryDeep
            : PortraitorTokens.onboardingMutedLight;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color:
                  active
                      ? PortraitorTokens.onboardingPrimary.withValues(
                        alpha: 0.16,
                      )
                      : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  child: SvgPicture.string(svg, width: 20, height: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: PortraitorTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.02,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _homeSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m4 11 8-6 8 6M6 10v9h12v-9" stroke="#7C5CFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''';
const _portraitsSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="4" y="5" width="16" height="13" rx="3" stroke="#B4AEC4" stroke-width="2"/><path d="M8 10h8M8 13h5" stroke="#B4AEC4" stroke-width="2" stroke-linecap="round"/></svg>''';
const _profileSvg =
    '''<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="8" r="3.4" stroke="#B4AEC4" stroke-width="2"/><path d="M5.5 20c.7-3.7 3.2-5.6 6.5-5.6s5.8 1.9 6.5 5.6" stroke="#B4AEC4" stroke-width="2" stroke-linecap="round"/></svg>''';
