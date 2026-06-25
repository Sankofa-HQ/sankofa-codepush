// Base app. Three patch-target shapes to measure how override-in-place
// reroutes:
//   1. compute()          — toplevel, patched directly (fresh Dart_Invoke).
//   2. caller()           — base AOT static call to compute (baked call site).
//   3. Widget.build()     — VIRTUAL method (two subclasses => AOT cannot
//                           devirtualize), reached via renderNew() -> a virtual
//                           dispatch. This mirrors a Flutter build() patch.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String compute() => 'BASE';

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String caller() => 'caller-> ' + compute();

class Widget {
  @pragma('vm:entry-point')
  @pragma('vm:never-inline')
  String build() => 'BASE-UI';
}

class Widget2 extends Widget {
  @pragma('vm:entry-point')
  @pragma('vm:never-inline')
  String build() => 'BASE-UI-2';
}

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String render(Widget w) => 'render-> ' + w.build();

// Keep both subclasses live + force a virtual (not devirtualized) call.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String renderNew() {
  final List<Widget> ws = [Widget(), Widget2()];
  return render(ws[0]);
}

void main() {
  print('compute()=' + compute());
  print('caller()=' + caller());
  print('renderNew()=' + renderNew());
}
