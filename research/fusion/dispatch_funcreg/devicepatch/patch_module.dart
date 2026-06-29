// The downloaded patch (compiled to bytecode). The transplant SOURCES are
// TOP-LEVEL functions (no class -> no implicit Object. ctor) whose bodies are
// constant returns (no dart:core function calls). So the patch references ZERO
// base-SDK callable functions and loads against ANY base, even a slim AOT app
// that tree-shook Object./_GrowableList._literalN out.
//
// The boot hook maps each target (an app VIRTUAL method) to one of these
// sources: Panel.label <- _patchedLabel, Panel2.label <- _patchedLabel2. A
// const-return body ignores the receiver, so the arg-count difference
// (instance method has `this`) is harmless.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String _patchedLabel() => 'PATCH-UI-FIXED-V2-LIVE';

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String _patchedLabel2() => 'PATCH-UI-FIXED-2';

// Manifest = comma-separated "target=source" pairs (a STRING -> no _GrowableList).
@pragma('vm:entry-point')
String _sankofaManifest() => 'Panel.label=_patchedLabel,Panel2.label=_patchedLabel2';

// Retain the sources + manifest by calling them (all patch-internal, no SDK).
@pragma('dyn-module:entry-point')
Object? _sankofaEntry() {
  _patchedLabel();
  _patchedLabel2();
  _sankofaManifest();
  return null;
}
