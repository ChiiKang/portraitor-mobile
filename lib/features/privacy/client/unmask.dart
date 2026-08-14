/// Restores real values in model output.
///
/// Direct port of `unmaskText` in
/// `portraitor_v3/public/assets/modules/privacy-filter.js`.
///
/// The backend only ever sees masked text, so the portrait it returns is written
/// about `[PERSON1]`. Without this the result screen would read "PERSON1 shows up
/// as grounded and encouraging". The entity map never leaves the device, so this
/// is the only place real names can be restored.
library;

import '../pipeline/types.dart';

/// Matches an issued placeholder. Deliberately strict: uppercase letters then
/// digits, so `[person1]` and `[PERSON]` are left alone exactly as the JS does.
final RegExp _tokenRe = RegExp(r'\[[A-Z]+[0-9]+\]');

/// Replaces every known token in [text] with its real value.
///
/// Unknown tokens are left untouched rather than blanked, which matters because
/// a chat can legitimately contain something shaped like `[PERSON9]` that was
/// never issued, and because the model can invent one.
///
/// Uses a replacement callback rather than a pattern string: values can contain
/// `$` sequences, and a naive replace would expand `$&` or `$1` instead of
/// inserting them literally. The JS is safe for the same reason.
String unmaskText(String text, List<MaskEntity> entities) {
  final map = <String, String>{};
  for (final e in entities) {
    // JS guards on `e.token` being truthy, so an empty token is skipped there
    // and must be skipped here too.
    if (e.token.isEmpty) continue;
    map[e.token] = e.value;
  }

  return text.replaceAllMapped(_tokenRe, (m) => map[m[0]] ?? m[0]!);
}
