// Base app. `compute()` is the function we hot-patch with downloaded bytecode.
// `caller()` calls it the way real code does (a static call), so we can test
// whether a base AOT CALLER reroutes to the patched body — the real-world
// crash-fix case, not just a fresh Dart_Invoke of the patched function.
// never-inline keeps both as real, separately-dispatched functions; entry-point
// retains them and makes them lookup-able by name.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String compute() => 'BASE';

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String caller() => 'caller-> ' + compute();

void main() {
  print('compute()=' + compute());
  print('caller()=' + caller());
}
