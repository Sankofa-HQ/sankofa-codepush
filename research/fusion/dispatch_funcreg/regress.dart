// Sankofa dispatch-funcreg REGRESSION test.
// Two subclasses override speak() -> `a.speak()` in callSpeak() is polymorphic,
// so the AOT compiler emits a real DispatchTableCall (not a devirtualized direct
// call). Running this on the new engine validates that the interleaved
// [entry, function] dispatch table + the stride-2 / R8-loading EmitDispatchTableCall
// still route a normal (native) virtual call correctly. Expect: woof / meow / moo.
abstract class Animal {
  String speak();
}

class Dog extends Animal {
  @pragma('vm:never-inline')
  String speak() => 'woof';
}

class Cat extends Animal {
  @pragma('vm:never-inline')
  String speak() => 'meow';
}

class Cow extends Animal {
  @pragma('vm:never-inline')
  String speak() => 'moo';
}

@pragma('vm:never-inline')
String callSpeak(Animal a) => a.speak();

void main() {
  final animals = <Animal>[Dog(), Cat(), Cow()];
  final out = StringBuffer();
  for (final a in animals) {
    out.write(callSpeak(a));
    out.write('\n');
  }
  print('SANKOFA_DISPATCH_REGRESS_OK\n$out');
}
