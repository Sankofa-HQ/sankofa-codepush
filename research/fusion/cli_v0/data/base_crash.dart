@pragma('vm:entry-point') @pragma('vm:never-inline')
String risky(int n) => 'value=' + (100 ~/ n).toString();   // BUG: crashes when n==0
@pragma('vm:entry-point') @pragma('vm:never-inline')
String caller() => 'result -> ' + risky(0);                 // calls risky(0) => CRASH
void main() { print(caller()); }
