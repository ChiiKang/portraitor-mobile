import 'package:flutter/widgets.dart';

/// Where the share sheet should appear to come from.
///
/// iPad presents the share sheet as a popover anchored to this rectangle, and
/// UIKit throws if it is missing or degenerate rather than falling back to
/// something sensible. `share_plus` forwards whatever it is given straight to
/// the platform, so a caller that omits it is not choosing a default: it is
/// choosing a crash on one form factor and an unanchored sheet on the other.
///
/// Pass the context of the widget the user actually tapped. The rectangle is
/// measured in the overlay's coordinate space, which is what UIKit expects.
/// When the tapped widget has no usable geometry - laid out at zero size, or
/// measured before the first frame - this falls back to a one-point rectangle
/// at the centre of the screen rather than returning null, because an anchor
/// in the wrong place still presents and no anchor at all does not.
Rect shareOriginFor(BuildContext context) {
  final sourceBox = context.findRenderObject();
  final overlayBox = Overlay.maybeOf(context)?.context.findRenderObject();
  if (sourceBox is RenderBox &&
      overlayBox is RenderBox &&
      sourceBox.hasSize &&
      overlayBox.hasSize &&
      sourceBox.size.width > 0 &&
      sourceBox.size.height > 0) {
    return sourceBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
        sourceBox.size;
  }

  final size = MediaQuery.sizeOf(context);
  return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
}
