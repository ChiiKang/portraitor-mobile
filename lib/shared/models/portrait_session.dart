import 'package:portraitor_mobile/core/storage/pending_job.dart';
import 'package:portraitor_mobile/features/results/application/portraits_provider.dart';

/// One generation session for Home Recent + Portraits tab (prototype session cards).
class PortraitSession {
  const PortraitSession({
    required this.id,
    required this.bundle,
    required this.whenLabel,
    required this.people,
    this.overview,
    this.rangeLabel,
    this.stripped,
    this.resultIds = const [],
    this.isUnfinished = false,
    this.sortAt,
  });

  final String id;
  final String bundle;
  final String whenLabel;
  final List<SessionPerson> people;
  final String? overview;
  final String? rangeLabel;
  final int? stripped;

  /// Conversation IDs to open (first person for Partner).
  final List<String> resultIds;

  /// A portrait that was paid for and never delivered.
  final bool isUnfinished;

  /// When this session started, for merging finished and unfinished entries
  /// into one chronological list. Null on demo samples, which are never merged.
  final DateTime? sortAt;

  String get namesLabel => people.map((p) => p.name).join(' · ');

  String? get metaLabel {
    final parts = <String>[];
    if (rangeLabel != null && rangeLabel!.isNotEmpty) parts.add(rangeLabel!);
    if (stripped != null && stripped! > 0) parts.add('$stripped stripped');
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  /// Demo sessions matching the Open Design prototype when the library is empty.
  static List<PortraitSession> demoSessions() => const [
        PortraitSession(
          id: 'session-james-emma',
          bundle: 'Partner',
          whenLabel: '2 days ago',
          rangeLabel: 'All messages',
          stripped: 43,
          people: [
            SessionPerson(
              name: 'James',
              initial: 'J',
              color: SessionAvColor.james,
            ),
            SessionPerson(
              name: 'Emma',
              initial: 'E',
              color: SessionAvColor.emma,
            ),
          ],
          overview:
              'A mature, supportive partnership with excellent emotional attunement — loving, supportive, and playfully warm.',
        ),
        PortraitSession(
          id: 'session-mom',
          bundle: 'Family',
          whenLabel: '1 week ago',
          rangeLabel: 'Jan–May 2024',
          people: [
            SessionPerson(name: 'Mom', initial: 'M', color: SessionAvColor.mom),
          ],
          overview:
              'Practical love wrapped in check-ins — she shows care by staying close to the details of your life.',
        ),
      ];

  /// Map stored single-target portraits into session cards (one person each).
  static List<PortraitSession> fromPortraits(List<Portrait> portraits) {
    return portraits.map((p) {
      final name = p.targetName.isEmpty ? 'Portrait' : p.targetName;
      final initial = name.isEmpty ? 'P' : name[0].toUpperCase();
      return PortraitSession(
        id: p.id,
        bundle: _bundleLabel(p.mode),
        whenLabel: _relativeWhen(p.createdAt),
        people: [
          SessionPerson(
            name: name,
            initial: initial,
            color: sessionAvColorFromName(name),
          ),
        ],
        overview: p.outputSummary,
        rangeLabel: null,
        resultIds: [p.id],
        sortAt: _parseWhen(p.createdAt),
      );
    }).toList();
  }

  /// Map an unfinished job into the same card the finished ones use, so the
  /// Portraits tab can list both in one chronological run.
  static PortraitSession fromPendingJob(PendingJob job) {
    final names = [
      for (final name in job.people)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    final fallback = job.targetName?.trim() ?? '';
    final resolved =
        names.isNotEmpty
            ? names
            : [fallback.isEmpty ? 'Portrait' : fallback];

    return PortraitSession(
      id: job.id,
      bundle: _bundleLabel(job.tier),
      whenLabel: _relativeWhen(job.createdAt.toIso8601String()),
      people: [
        for (final name in resolved)
          SessionPerson(
            name: name,
            initial: name.isEmpty ? 'P' : name[0].toUpperCase(),
            color: sessionAvColorFromName(name),
          ),
      ],
      isUnfinished: true,
      sortAt: job.createdAt,
    );
  }

  static String _bundleLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'partner':
      case 'couple':
        return 'Partner';
      case 'family':
        return 'Family';
      default:
        return 'You';
    }
  }

  static DateTime? _parseWhen(String iso) {
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  static String _relativeWhen(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) {
        return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      }
      if (diff.inDays < 14) return '1 week ago';
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return iso.isEmpty ? 'Recently' : iso;
    }
  }
}

class SessionPerson {
  const SessionPerson({
    required this.name,
    required this.initial,
    required this.color,
  });

  final String name;
  final String initial;
  final SessionAvColor color;
}

enum SessionAvColor { james, emma, mom, sarah, defaultPurple }

SessionAvColor sessionAvColorFromName(String name) {
  final n = name.toLowerCase();
  if (n.startsWith('j')) return SessionAvColor.james;
  if (n.startsWith('e')) return SessionAvColor.emma;
  if (n.startsWith('m')) return SessionAvColor.mom;
  if (n.startsWith('s')) return SessionAvColor.sarah;
  return SessionAvColor.defaultPurple;
}
