// Minimal base mirror for building the dispatch-funcreg device patch. Declares
// the SAME Panel/label signatures as the Flutter app (sankofa_push_test) so the
// patch's bytecode transplants onto the app's Panel.label by name. The bytecode
// references only dart:core (a String literal), so it carries no Flutter dep.
class Panel {
  @pragma('vm:entry-point')
  @pragma('vm:never-inline')
  String label() => 'BASE-UI';
}

class Panel2 extends Panel {
  @pragma('vm:entry-point')
  @pragma('vm:never-inline')
  String label() => 'BASE-UI-2';
}

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String renderPanel(Panel pnl) => 'render-> ' + pnl.label();

@pragma('vm:entry-point')
@pragma('vm:never-inline')
String panelStatus() {
  final List<Panel> panels = [Panel(), Panel2()];
  return renderPanel(panels[0]);
}

void main() {
  print(panelStatus());
}
