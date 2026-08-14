/// Translates the portrait's target name into the token the model will see.
///
/// Direct port of `maskTargetName` in
/// `portraitor_v3/public/assets/app.js`.
///
/// The chat sent for analysis has `[PERSON1]` where the target's name used to
/// be, so passing the real name as TARGET_NAME would ask the model to find
/// someone who does not appear in its input. Handing it the token instead keeps
/// the portrait pointed at the right person without ever revealing who that is.
library;

import '../pipeline/types.dart';

/// Returns the token standing in for [name], or [name] itself when there is no
/// substitution to make.
///
/// Falls back to the real name on purpose. When masking is off, or when the
/// detector never picked this person up, the chat still contains the real name,
/// so the real name is the correct thing to send.
///
/// Matching is trimmed and lowercased on both sides, and restricted to
/// `type == 'person'`. An email or URL entity whose value happens to equal the
/// name is not a match: the target is a human, not a string.
String maskTargetName(String name, List<MaskEntity> entities) {
  // JS guards with `!name`, so an empty name returns early rather than matching
  // an entity with an empty value.
  if (entities.isEmpty || name.isEmpty) return name;

  final lower = name.trim().toLowerCase();
  for (final e in entities) {
    if (e.type == 'person' && e.value.trim().toLowerCase() == lower) {
      // First match wins, so the earliest-issued token is the one used.
      return e.token;
    }
  }
  return name;
}
