import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_build_trace/sankofa_build_trace.dart';

export 'package:sankofa_build_trace/sankofa_build_trace.dart'
    show currentProcessId, BuildTraceEvent, BuildTracer, PhaseTracker;

/// Perfetto row id for network (HTTP) spans within the sankofa_cli
/// process. Local tid; no cross-repo coordination.
const int _networkTid = 1;

/// Perfetto row id for sankofa_cli's own command-level phase spans
/// recorded via [SankofaTracer.span].
const int _sankofaTid = 2;

/// Sankofa-specific wrapper around [BuildTracer]. Owns the pid +
/// tid layout for sankofa_cli's rows (network + sankofa_cli), adds
/// [span]/[addNetworkEvent]/[mergeInto] helpers keyed off that layout,
/// and emits `process_name` / `thread_name` metadata when merging into
/// Flutter's trace file.
///
/// For generic helpers (trace/timeSubprocess/recordNetworkSpan etc.)
/// see [BuildTracer] directly — this class is the sankofa_cli-shaped
/// facade, not a wire-format reimplementation.
class SankofaTracer {
  /// The underlying [BuildTracer] that holds the raw events.
  final BuildTracer _tracer = BuildTracer();

  /// Real pid of the sankofa_cli process — captured at construction
  /// so every event emitted through this tracer is tagged with it.
  final int _pid = currentProcessId();

  /// Raw event buffer, for tests that need to inspect individual spans.
  List<Map<String, Object?>> get events => _tracer.events;

  /// Record a completed network span on the sankofa_cli row.
  void addNetworkEvent({
    required String name,
    required DateTime start,
    required Duration duration,
    Map<String, Object?>? args,
  }) {
    _tracer.addCompleteEvent(
      name: name,
      cat: 'network',
      pid: _pid,
      tid: _networkTid,
      start: start,
      end: start.add(duration),
      args: args,
    );
  }

  /// Run [body], time it, and record a span on the sankofa_cli row.
  /// Matches [BuildTracer.traceAsync] semantics but pre-fills pid/tid
  /// so commands don't have to know the layout.
  Future<T> span<T>({
    required String name,
    required String category,
    required Future<T> Function() body,
    Map<String, Object?>? args,
  }) => _tracer.traceAsync<T>(
    name: name,
    cat: category,
    pid: _pid,
    tid: _sankofaTid,
    body: body,
    args: args,
  );

  /// Emits a flow-start event at [at] with id = [id]. Sankofa
  /// convention uses the child process's real pid as the flow id so
  /// the child emits the matching `ph: "f"` with the same id without
  /// any plumbing.
  void addSpawnFlowStart({
    required int id,
    required DateTime at,
    int fromTid = _sankofaTid,
  }) {
    _tracer.addFlowStart(id: id, pid: _pid, tid: fromTid, at: at);
  }

  /// Append accumulated events to [traceFile] (a Chrome Trace Event
  /// Format JSON array, as written by Flutter). Also emits our
  /// process_name / thread_name metadata so Perfetto labels our rows.
  /// No-op if the file doesn't exist or isn't a JSON array.
  void mergeInto(File traceFile) {
    if (!traceFile.existsSync()) return;
    final List<Map<String, Object?>> existingEvents;
    try {
      final decoded = jsonDecode(traceFile.readAsStringSync());
      if (decoded is! List) return;
      existingEvents = decoded.whereType<Map<String, Object?>>().toList();
    } on FormatException {
      return;
    }
    _tracer
      ..addProcessNameMetadata(pid: _pid, name: 'sankofa_cli')
      ..addThreadNameMetadata(pid: _pid, tid: _networkTid, name: 'network')
      ..addThreadNameMetadata(
        pid: _pid,
        tid: _sankofaTid,
        name: 'sankofa_cli',
      )
      ..writeToFile(traceFile, existingEvents: existingEvents);
  }
}

/// A reference to a [SankofaTracer] instance. One instance per `sankofa`
/// invocation, seeded in `main()`.
final sankofaTracerRef = create<SankofaTracer>(SankofaTracer.new);

/// The [SankofaTracer] instance available in the current zone.
SankofaTracer get sankofaTracer => read(sankofaTracerRef);
