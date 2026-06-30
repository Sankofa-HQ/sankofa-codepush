// Sankofa CodePush — LIVE RENDER-PATH dispatch-funcreg probe.
//
// Unlike the proven boot-context build (which records the reroute result at
// boot and the UI only READS it), THIS build drives the rerouted virtual
// dispatch-table call DURING the live Flutter render: build() calls
// panelStatus() -> renderPanel(Panel()) -> pnl.label(), where label() is a
// DispatchTableCall whose slot the boot hook repointed to the interpreter.
//
// This is the path that crashed the interpreter with `opcode=0` (Trap). The
// engine now carries an ENRICHED Trap diagnostic (fn name, has_bc, bytecode
// base/size, pc_off, in_range, depth), so the crash captured on the device
// console pinpoints whether the PC ran off the end of valid bytecode, landed in
// the wrong frame, or hit a real Trap inside valid bytecode.
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

// Polymorphic (Panel + Panel2 both live) so renderPanel's pnl.label() compiles
// to a real DispatchTableCall — the call the boot hook repoints to the
// interpreter. Called LIVE from build() below.
@pragma('vm:entry-point')
@pragma('vm:never-inline')
String panelStatus() {
  final List<Panel> panels = [Panel(), Panel2()];
  return renderPanel(panels[0]);
}

// Boot-recorded result (for comparison / fallback if the live call is fixed).
String _readBootVerify() {
  try {
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
      title: 'Sankofa CodePush — live render reroute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4ABF)),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    // ── THE LIVE RENDER-PATH REROUTE ──────────────────────────────────────
    // This runs DURING the framework render, deep in the build stack. The
    // dispatch-table call to Panel.label() routes through the repointed slot to
    // the interpreter. If the interpreter Traps, the engine's enriched FATAL
    // fires here and the app hard-crashes (captured on the device console).
    final String live = panelStatus();
    // ──────────────────────────────────────────────────────────────────────
    final boot = _readBootVerify();
    final patched = live.contains('PATCH-UI-FIXED');
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Live render reroute')),
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
                            color: patched
                                ? Colors.green.shade700
                                : scheme.error,
                            size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            patched
                                ? 'LIVE RENDER REROUTED'
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
                      'The dispatch-table call render-> Panel.label() ran '
                      'LIVE inside build(). If you can read this, the rerouted '
                      'interpreted body executed during the real render:',
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
                        'live panelStatus() => $live\n'
                        'boot-recorded       => ${boot.isEmpty ? "(none)" : boot}',
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 12,
                          height: 1.5,
                          color: patched
                              ? Colors.green.shade900
                              : scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
