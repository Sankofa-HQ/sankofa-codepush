// REAL-BODY patch (test #1): proves NON-TRIVIAL logic — dart:core calls (loop,
// int arithmetic, List<String>, .add, .join, string interpolation) — runs LIVE
// through the interpreter during the Flutter render, not just a constant return.
//
// The transplant SOURCES stay TOP-LEVEL (no class -> no implicit Object. ctor),
// but the body now exercises real dart:core. Those callables resolve at runtime
// against the full Flutter app's AOT snapshot (a MaterialApp retains List/+/
// string-interp/join). The result `sum=55` (1²+2²+3²+4²+5²) can ONLY appear if
// the loop+arithmetic actually executed — a constant patch cannot fake it.
//
// Mapped onto Panel.label / Panel2.label by _sankofaManifest. A top-level body
// ignores the receiver, so the instance-method arg (`this`) is harmless.
// No list / no multi-part interpolation (those synthesize _GrowableList, which a
// non-dynamic-interface app tree-shakes). Uses only loop + int arithmetic +
// int.toString + String.+ — all heavily used by Flutter, so retained. sum=55.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String _patchedLabel() {
  int sum = 0;
  for (int i = 1; i <= 5; i++) {
    sum += i * i;
  }
  return 'PATCH-UI-FIXED computed sum=' +
      sum.toString() +
      ' next=' +
      (sum + 1).toString();
}

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String _patchedLabel2() {
  int f = 1;
  for (int i = 1; i <= 5; i++) {
    f *= i;
  }
  return 'PATCH-UI-FIXED-2 fact5=' + f.toString();
}

// Manifest = comma-separated "target=source" pairs (a STRING -> no _GrowableList).
@pragma('vm:entry-point')
String _sankofaManifest() => 'Panel.label=_patchedLabel,Panel2.label=_patchedLabel2';

// Retain the sources + manifest by referencing them.
@pragma('dyn-module:entry-point')
Object? _sankofaEntry() {
  _patchedLabel();
  _patchedLabel2();
  _sankofaManifest();
  return null;
}
