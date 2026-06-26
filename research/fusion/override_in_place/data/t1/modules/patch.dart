// The downloaded patch, compiled to bytecode.
//   patched()           — new body for toplevel compute().
//   WidgetPatch.build() — new body for the VIRTUAL Widget.build() (instance
//                         method; bytecode signature has a receiver matching
//                         the target. Body ignores `this`).
// A dynamic module may declare only ONE dyn-module:entry-point, so a single
// entry references both to retain + compile them to bytecode.
// Import the base app so a re-shipped bytecode function can construct base
// Widget instances and drive a VIRTUAL call through the interpreter.
import 'dev-dart-app:/data/t1/main.dart';

String patched() => 'PATCH-CRASH-FIXED';

// Virtual-cascade probe: a re-shipped renderNew whose body does a virtual
// w.build() on a base Widget. In the interpreter, w.build() is resolved on the
// receiver's class at call time, so it lands on the transplanted (bytecode)
// Widget.build with NO dispatch-table update — proving the cascade model covers
// VIRTUAL interior calls too (only the unchanged-base->changed ENTRY edge needs
// switchable+IC handling).
String renderNewViaPatched() {
  final List<Widget> ws = [Widget(), Widget2()];
  return 'render-> ' + ws[0].build();
}

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
String entry() =>
    patched() + WidgetPatch().build() + callerViaPatched() +
    renderNewViaPatched();
