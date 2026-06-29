// Sankofa CodePush — on-device test app (DISPATCH-FUNCREG proof, boot-context).
//
// The dispatch-funcreg reroute (an UNCHANGED base-AOT virtual DISPATCH-TABLE
// call `renderPanel -> Panel.label()` rerouted to downloaded bytecode) is
// exercised by the ENGINE BOOT HOOK: after it transplants Panel.label and
// repoints the dispatch slot, it invokes sankofaVerify() (which calls
// renderPanel(Panel())) once, in the simple boot context, and writes the result
// to sankofa_boot_result.txt. The UI here only READS that result and displays it
// (no path_provider; reads via $HOME). So the render path never drives the
// interpreter — the reroute is proven by what the boot hook recorded.

import 'dart:io';

import 'package:flutter/material.dart';

// ── Dispatch-funcreg transplant target (a VIRTUAL method) ────────────────
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

// UNCHANGED base-AOT caller: a baked virtual dispatch-table call to label().
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String renderPanel(Panel pnl) => 'render-> ${pnl.label()}';

// The boot hook invokes this FRESH (Dart_Invoke) after transplant+repoint. It
// drives the rerouted virtual dispatch in the simple boot context -> the
// interpreted Panel.label runs and this returns 'render-> PATCH-UI-FIXED', which
// the hook records in verify=. Instantiating BOTH Panel and Panel2 keeps
// label() polymorphic so the compiler emits a real DispatchTableCall (not a
// devirtualized direct call) — which is what the boot-hook repoint reroutes.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String sankofaVerify() {
  final List<Panel> panels = [Panel(), Panel2()];
  return renderPanel(panels[0]);
}

// Read the engine's boot result (verify= field) from the updater dir via $HOME
// (iOS app container) — no path_provider, so no native-assets build hook.
String _readBootVerify() {
  try {
    // iOS data container holds both tmp/ and Documents/. systemTemp = <Data>/tmp,
    // so its parent is the container -> Documents/sankofa_updater. (No
    // path_provider, so no objective_c native-assets build hook.)
    final container = Directory.systemTemp.parent.path;
    final patches = Directory('$container/Documents/sankofa_updater/patches');
    if (!patches.existsSync()) return '';
    File? newest;
    DateTime newestT = DateTime.fromMillisecondsSinceEpoch(0);
    for (final d in patches.listSync().whereType<Directory>()) {
      final f = File('${d.path}/sankofa_boot_result.txt');
      if (f.existsSync() && f.statSync().modified.isAfter(newestT)) {
        newest = f;
        newestT = f.statSync().modified;
      }
    }
    if (newest == null) return '';
    final line = newest.readAsStringSync().trim();
    final m = RegExp(r'verify=(.*)$', dotAll: true).firstMatch(line);
    return (m != null ? m.group(1) : line)?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

void main() {
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sankofa CodePush — dispatch-funcreg',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4ABF)),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  String _verify = _readBootVerify();

  void _refresh() => setState(() => _verify = _readBootVerify());

  @override
  Widget build(BuildContext context) {
    final patched = _verify.contains('PATCH-UI-FIXED');
    final scheme = Theme.of(context).colorScheme;
    final display = _verify.isEmpty ? '(no boot result yet)' : _verify;
    return Scaffold(
      appBar: AppBar(title: const Text('Sankofa CodePush — dispatch-funcreg')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: patched
                      ? Colors.green.withValues(alpha: 0.14)
                      : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: patched ? Colors.green : scheme.error,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(patched ? Icons.verified : Icons.error_outline,
                            color:
                                patched ? Colors.green.shade700 : scheme.error,
                            size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            patched
                                ? 'VIRTUAL DISPATCH REROUTED'
                                : 'BASE BUILD — no patch',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: patched
                                  ? Colors.green.shade800
                                  : scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      patched
                          ? 'At boot, the engine transplanted Panel.label to '
                              'downloaded bytecode and repointed its dispatch '
                              'slot. The UNCHANGED base-AOT renderPanel() then '
                              'reached the interpreted body via the dispatch '
                              'table — no flag, no JIT:'
                          : 'renderPanel -> Panel.label() runs the base AOT '
                              'body. Stage a patch + relaunch.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'engine sankofaVerify() => $display\n'
                        '${patched ? "no rebuild · no JIT · Apple-compliant" : "(base AOT dispatch)"}',
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 12,
                          height: 1.5,
                          color:
                              patched ? Colors.green.shade900 : scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-read engine boot result'),
              ),
              const Spacer(),
              Text(
                'The patched Panel.label() runs via the Dart bytecode '
                'interpreter; the base-AOT renderPanel() reaches it through the '
                'dispatch table, repointed at boot to the InterpretCall '
                'trampoline. This screen reflects what the engine recorded.',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
