import 'dart:ffi' as ffi;
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:sankofa_code_push/src/generated/updater_bindings.g.dart';
import 'package:sankofa_code_push/src/sankofa_updater.dart';

/// {@template updater}
/// A wrapper around the generated [UpdaterBindings] that, when necessary,
/// translates ffi types into easier to use Dart types.
/// {@endtemplate}
class Updater {
  /// {@macro updater}
  const Updater();

  /// The ffi bindings to the Updater library.
  @visibleForTesting
  static UpdaterBindings bindings =
      UpdaterBindings(ffi.DynamicLibrary.process());

  /// The currently active patch number.
  int currentPatchNumber() => bindings.sankofa_current_boot_patch_number();

  /// The next patch number that will be loaded. Will be the same as
  /// currentPatchNumber if no new patch is available.
  int nextPatchNumber() => bindings.sankofa_next_boot_patch_number();

  /// Whether a new patch is available for download.
  bool checkForDownloadableUpdate({UpdateTrack? track}) =>
      bindings.sankofa_check_for_downloadable_update(
        track == null ? ffi.nullptr : track.name.toNativeUtf8().cast<Char>(),
      );

  /// Downloads the latest patch, if available and returns an [UpdateResult]
  /// to indicate whether the update was successful.
  Pointer<UpdateResult> update({UpdateTrack? track}) =>
      bindings.sankofa_update_with_result(
        track == null ? ffi.nullptr : track.name.toNativeUtf8().cast<Char>(),
      );

  /// Frees an update result allocated by the updater.
  void freeUpdateResult(Pointer<UpdateResult> ptr) =>
      bindings.sankofa_free_update_result(ptr);
}
