class Panel { @pragma('vm:entry-point') @pragma('vm:never-inline') String label() => 'PATCH-UI-FIXED'; }
class Panel2 extends Panel { @pragma('vm:entry-point') @pragma('vm:never-inline') String label() => 'BASE-UI-2'; }
@pragma('vm:entry-point') @pragma('vm:never-inline') String renderPanel(Panel p) => 'render-> ' + p.label();
@pragma('vm:entry-point') @pragma('vm:never-inline') String panelStatus() { final ps = <Panel>[Panel(), Panel2()]; return renderPanel(ps[0]); }
void main() { print(panelStatus()); }
