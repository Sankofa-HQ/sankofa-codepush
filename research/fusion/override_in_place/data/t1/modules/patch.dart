// The downloaded patch, compiled to bytecode.
//   patched()           — new body for toplevel compute().
//   WidgetPatch.build() — new body for the VIRTUAL Widget.build() (instance
//                         method; bytecode signature has a receiver matching
//                         the target. Body ignores `this`).
// A dynamic module may declare only ONE dyn-module:entry-point, so a single
// entry references both to retain + compile them to bytecode.
String patched() => 'PATCH-CRASH-FIXED';

class WidgetPatch {
  String build() => 'PATCH-UI-FIXED';
}

@pragma('dyn-module:entry-point')
String entry() => patched() + WidgetPatch().build();
