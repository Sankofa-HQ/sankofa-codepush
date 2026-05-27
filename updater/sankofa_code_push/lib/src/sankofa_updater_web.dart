import 'package:sankofa_code_push/src/sankofa_updater.dart';

/// {@template sankofa_updater_web}
/// The Sankofa web updater.
/// {@endtemplate}
class SankofaUpdaterImpl implements SankofaUpdater {
  /// {@macro sankofa_updater_web}
  SankofaUpdaterImpl() {
    logSankofaEngineUnavailableMessage();
  }

  @override
  bool get isAvailable => false;

  @override
  Future<Patch?> readCurrentPatch() async => null;

  @override
  Future<Patch?> readNextPatch() async => null;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async =>
      UpdateStatus.unavailable;

  @override
  Future<void> update({UpdateTrack? track}) async {}
}
