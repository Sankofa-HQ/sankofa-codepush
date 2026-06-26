@pragma('vm:entry-point') @pragma('vm:never-inline')
String risky(int n) => n == 0 ? 'value=safe-default' : 'value=' + (100 ~/ n).toString();  // FIXED
@pragma('vm:entry-point') @pragma('vm:never-inline')
String caller() => 'result -> ' + risky(0);
void main() { print(caller()); }
