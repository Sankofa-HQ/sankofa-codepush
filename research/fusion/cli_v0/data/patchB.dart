@pragma('vm:entry-point') @pragma('vm:never-inline')
String compute() => 'BASE';
@pragma('vm:entry-point') @pragma('vm:never-inline')
String caller() => 'caller-> ' + compute();
@pragma('vm:entry-point') @pragma('vm:never-inline')
String helper() => 'helper-noop';   // unrelated fn, should NOT change
class Widget {
  @pragma('vm:entry-point') @pragma('vm:never-inline')
  String build() => 'FIXED-UI';
}
@pragma('vm:entry-point') @pragma('vm:never-inline')
String render(Widget w) => 'render-> ' + w.build();   // VIRTUAL call to build
void main() { print(compute()); print(caller()); print(render(Widget())); print(helper()); }
