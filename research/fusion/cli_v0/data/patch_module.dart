// The downloaded patch module = the changed-set functions (compute, caller) with
// their FIXED bodies, compiled to bytecode. Compiled --prefix-library-uris so it
// loads additively; the boot-time apply then AttachBytecode each onto the base
// same-named function (driven by changed_manifest.json).
@pragma('vm:entry-point') @pragma('vm:never-inline')
String compute() => 'FIXED';
@pragma('vm:entry-point') @pragma('vm:never-inline')
String caller() => 'caller-> ' + compute();
@pragma('dyn-module:entry-point')
String entry() => compute() + caller();
