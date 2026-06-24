// Base app. `compute()` is the function we will hot-patch with downloaded
// bytecode. never-inline so it stays a real, separately-dispatched function;
// entry-point so AOT tree-shaking retains it and it's lookup-able by name.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String compute() => 'BASE';

void main() {
  print('compute()=' + compute());
}
