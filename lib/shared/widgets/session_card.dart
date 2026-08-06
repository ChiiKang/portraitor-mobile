import 'package:flutter/material.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/models/portrait_session.dart';

/// Preview / compact session card matching Open Design `.session-card`.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.compact = false,
    this.onDelete,
  });

  final PortraitSession session;
  final VoidCallback onTap;
  final bool compact;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x12211A37)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59211A37),
                blurRadius: 22,
                offset: Offset(0, 8),
                spreadRadius: -14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(14, compact ? 12 : 14, 14, compact ? 12 : 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _BundleChip(label: session.bundle),
                        const Spacer(),
                        Text(
                          session.whenLabel,
                          style: PortraitorTokens.bodySm.copyWith(
                            fontSize: 12,
                            color: PortraitorTokens.onboardingMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: PortraitorTokens.inkDim,
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Row(
                      children: [
                        _AvatarStack(people: session.people),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            session.namesLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PortraitorTokens.titleSm.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.24,
                              color: PortraitorTokens.onboardingInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!compact &&
                        session.overview != null &&
                        session.overview!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        session.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PortraitorTokens.bodySm.copyWith(
                          fontSize: 13,
                          height: 1.45,
                          color: PortraitorTokens.onboardingInkSoft,
                        ),
                      ),
                    ],
                    if (!compact && session.metaLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        session.metaLabel!,
                        style: PortraitorTokens.bodySm.copyWith(
                          fontSize: 12,
                          color: PortraitorTokens.onboardingMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const Divider(height: 1, color: Color(0x0F211A37)),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: PortraitorTokens.error,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BundleChip extends StatelessWidget {
  const _BundleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PortraitorTokens.onboardingPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: PortraitorTokens.labelSm.copyWith(
          fontFamily: PortraitorTokens.fontBody,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
          color: PortraitorTokens.onboardingPrimaryDeep,
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.people});

  final List<SessionPerson> people;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    return SizedBox(
      width: 32.0 + (shown.length - 1) * 24.0,
      height: 32,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 24.0,
              child: _SessionAvatar(person: shown[i]),
            ),
        ],
      ),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.person});

  final SessionPerson person;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(person.color);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        person.initial,
        style: const TextStyle(
          fontFamily: PortraitorTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  List<Color> _colorsFor(SessionAvColor c) {
    return switch (c) {
      SessionAvColor.james => const [Color(0xFF7C5CFF), Color(0xFFA855F7)],
      SessionAvColor.emma => const [Color(0xFFEC4899), Color(0xFFF97316)],
      SessionAvColor.mom => const [Color(0xFF6D52FF), Color(0xFFA855F7)],
      SessionAvColor.sarah => const [Color(0xFF9B86E8), Color(0xFFEC4899)],
      SessionAvColor.defaultPurple => const [
        Color(0xFF7C5CFF),
        Color(0xFFA855F7),
      ],
    };
  }
}
