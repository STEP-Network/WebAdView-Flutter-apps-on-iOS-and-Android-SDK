import 'package:flutter/rendering.dart';

import '../platform/webadview_platform.dart';

/// Axis-aligned bounds of [box] in the root Flutter view's coordinate space
/// (logical pixels). `null` when the box is not laid out or not attached
/// (sliver not built yet, route being dismissed) or the transform is
/// degenerate. Uses the full transform so `Transform` ancestors are
/// honoured.
Rect? globalRectOf(RenderBox? box) {
  if (box == null || !box.attached || !box.hasSize) return null;
  final rect = MatrixUtils.transformRect(
      box.getTransformTo(null), Offset.zero & box.size);
  return rect.isFinite ? rect : null;
}

/// Size of the root render view that [box] belongs to (logical pixels).
Size? rootViewSizeOf(RenderBox box) {
  final root = box.owner?.rootNode;
  if (root is RenderView) return root.size;
  return null;
}

/// One frame's geometry for a scope: the viewport and every registered ad.
class GeometrySnapshot {
  const GeometrySnapshot(this.viewport, this.ads);

  final Rect viewport;
  final Map<String, AdGeometry> ads;

  /// Equal within [tolerance] per edge and with the same ad set. Drops the
  /// sub-pixel noise of layout passes so idle frames send nothing.
  bool approxEquals(GeometrySnapshot? other, {double tolerance = 0.5}) {
    if (other == null) return false;
    if (!_rectClose(viewport, other.viewport, tolerance)) return false;
    if (ads.length != other.ads.length) return false;
    for (final entry in ads.entries) {
      final o = other.ads[entry.key];
      if (o == null) return false;
      if (!_rectClose(entry.value.frame, o.frame, tolerance)) return false;
      if (!_rectClose(entry.value.creative, o.creative, tolerance)) {
        return false;
      }
    }
    return true;
  }

  static bool _rectClose(Rect a, Rect b, double t) =>
      (a.left - b.left).abs() <= t &&
      (a.top - b.top).abs() <= t &&
      (a.width - b.width).abs() <= t &&
      (a.height - b.height).abs() <= t;
}
