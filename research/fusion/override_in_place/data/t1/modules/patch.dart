// The downloaded patch, compiled to bytecode.
//   patched()           — new body for toplevel compute().
//   WidgetPatch.build() — new body for the VIRTUAL Widget.build() (instance
//                         method; bytecode signature has a receiver matching
//                         the target. Body ignores `this`).
// A dynamic module may declare only ONE dyn-module:entry-point, so a single
// entry references both to retain + compile them to bytecode.
String patched() => 'PATCH-CRASH-FIXED';

// Cascade probe: a re-shipped caller whose NEW body calls patched() (the new
// compute). Transplanted onto base caller(), its call is interpreter-dispatched,
// so it reaches the new code with NO trampoline/DD — proving the "ship the
// changed fn + its caller cascade as bytecode" rerouting model (the MVP that
// makes trampolines/DD a size optimization, not a correctness blocker).
String callerViaPatched() => 'caller-> ' + patched();

class WidgetPatch {
  String build() => 'PATCH-UI-FIXED';
}

@pragma('dyn-module:entry-point')
String entry() => patched() + WidgetPatch().build() + callerViaPatched();
