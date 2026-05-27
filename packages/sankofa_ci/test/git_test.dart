// Test fixtures contain 40-char SHA-style hex strings that trip cspell.
// cspell:disable

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sankofa_ci/src/git.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Git', () {
    setUpTempDir('sankofa_ci_git_');

    test('changedFiles throws ProcessException when git fails', () {
      // No git repo in tempDir → `git diff` exits non-zero.
      const git = Git();
      expect(
        () => git.changedFiles(
          base: 'origin/main',
          head: 'HEAD',
          workingDirectory: tempDir.path,
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test('changedFiles lists files changed between two refs', () {
      // initGitRepo makes the initial commit; add another so HEAD~1
      // resolves to the previous commit.
      initGitRepo(tempDir);
      File(p.join(tempDir.path, 'a.txt')).writeAsStringSync('hi');
      commitAll(tempDir, 'add a');
      File(p.join(tempDir.path, 'b.txt')).writeAsStringSync('there');
      commitAll(tempDir, 'add b');

      const git = Git();
      final files = git.changedFiles(
        base: 'HEAD~1',
        head: 'HEAD',
        workingDirectory: tempDir.path,
      );
      expect(files, contains('b.txt'));
    });

    test('submodulePaths returns [] outside a git repo', () {
      const git = Git();
      // tempDir is not a git repo here.
      expect(
        git.submodulePaths(workingDirectory: tempDir.path),
        isEmpty,
      );
    });

    test('isIgnored detects gitignored paths', () {
      File(p.join(tempDir.path, '.gitignore')).writeAsStringSync('ignored/\n');
      initGitRepo(tempDir);

      const git = Git();
      expect(
        git.isIgnored(
          path: 'ignored/file.txt',
          workingDirectory: tempDir.path,
        ),
        isTrue,
      );
      expect(
        git.isIgnored(
          path: 'lib/main.dart',
          workingDirectory: tempDir.path,
        ),
        isFalse,
      );
    });
  });

  group('parseSubmoduleStatus', () {
    test('returns empty list for empty output', () {
      expect(parseSubmoduleStatus(''), isEmpty);
    });

    test('parses a single initialized submodule', () {
      // Real `git submodule status` output: leading space (initialized),
      // SHA, path, parenthesized describe-output.
      const output =
          ' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sankofa (heads/main)';
      expect(parseSubmoduleStatus(output), equals(['sankofa']));
    });

    test('parses uninitialized submodule (- prefix, no describe)', () {
      const output = '-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa packages/foo';
      expect(parseSubmoduleStatus(output), equals(['packages/foo']));
    });

    test('parses out-of-date submodule (+ prefix)', () {
      const output =
          '+aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sankofa (heads/main)';
      expect(parseSubmoduleStatus(output), equals(['sankofa']));
    });

    test('parses merge-conflict submodule (U prefix)', () {
      const output = 'Uaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sankofa';
      expect(parseSubmoduleStatus(output), equals(['sankofa']));
    });

    test('handles paths with spaces', () {
      const output =
          ' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa my submodule (heads/main)';
      expect(parseSubmoduleStatus(output), equals(['my submodule']));
    });

    test('parses multiple submodules', () {
      const output = '''
 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sankofa (heads/main)
+bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb packages/foo (heads/main)
-cccccccccccccccccccccccccccccccccccccccc packages/bar''';
      expect(
        parseSubmoduleStatus(output),
        equals(['sankofa', 'packages/foo', 'packages/bar']),
      );
    });

    test('skips malformed lines silently', () {
      const output = '''
not a submodule line
 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sankofa (heads/main)
also not''';
      expect(parseSubmoduleStatus(output), equals(['sankofa']));
    });
  });
}
