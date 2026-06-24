// The downloaded patch, compiled to bytecode. `patched()` is the NEW body we
// transplant onto base `compute()`. Returning a different string proves the
// interpreter ran the downloaded code (not the baked-in AOT 'BASE').
@pragma('dyn-module:entry-point')
String patched() => 'PATCH-CRASH-FIXED';
