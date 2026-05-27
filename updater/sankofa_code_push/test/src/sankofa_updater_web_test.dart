import 'package:sankofa_code_push/src/sankofa_updater.dart';
import 'package:sankofa_code_push/src/sankofa_updater_web.dart';
import 'package:test/test.dart';

import '../override_print.dart';

void main() {
  group(SankofaUpdaterImpl, () {
    late SankofaUpdaterImpl sankofaUpdater;

    test(
      'logs unavailable error',
      overridePrint((logs) {
        sankofaUpdater = SankofaUpdaterImpl();
        expect(
          logs,
          contains(
            isA<String>().having(
              (s) => s,
              'message',
              contains(
                '''The Sankofa Updater is unavailable in the current environment.''',
              ),
            ),
          ),
        );
      }),
    );

    group('isAvailable', () {
      test(
        'returns false',
        overridePrint((_) {
          sankofaUpdater = SankofaUpdaterImpl();
          expect(sankofaUpdater.isAvailable, isFalse);
        }),
      );
    });

    group('readPatch', () {
      test(
        'returns null',
        overridePrint((_) async {
          await expectLater(
            sankofaUpdater.readCurrentPatch(),
            completion(isNull),
          );
          await expectLater(
            sankofaUpdater.readNextPatch(),
            completion(isNull),
          );
        }),
      );
    });

    group('checkForUpdate', () {
      test(
        'returns UpdateStatus.unavailable',
        overridePrint((_) async {
          await expectLater(
            sankofaUpdater.checkForUpdate(),
            completion(equals(UpdateStatus.unavailable)),
          );
        }),
      );
    });

    group('update', () {
      test(
        'does nothing',
        overridePrint((_) async {
          await expectLater(sankofaUpdater.update(), completes);
        }),
      );
    });
  });
}
