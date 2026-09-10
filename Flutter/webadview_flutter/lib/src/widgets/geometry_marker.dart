import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Holds the render box of a [GeometryMarker] so the scope can read its
/// global rect once per frame without a `GlobalKey`.
class BoxHandle {
  RenderBox? box;
}

/// Transparent proxy box that publishes itself into a [BoxHandle] while
/// attached. Layout and painting are untouched.
class GeometryMarker extends SingleChildRenderObjectWidget {
  const GeometryMarker({super.key, required this.handle, super.child});

  final BoxHandle handle;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderGeometryMarker(handle);

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderGeometryMarker renderObject) {
    renderObject.handle = handle;
  }
}

class RenderGeometryMarker extends RenderProxyBox {
  RenderGeometryMarker(this._handle);

  BoxHandle _handle;

  set handle(BoxHandle value) {
    if (identical(value, _handle)) return;
    if (identical(_handle.box, this)) _handle.box = null;
    _handle = value;
    if (attached) _handle.box = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _handle.box = this;
  }

  @override
  void detach() {
    if (identical(_handle.box, this)) _handle.box = null;
    super.detach();
  }
}
