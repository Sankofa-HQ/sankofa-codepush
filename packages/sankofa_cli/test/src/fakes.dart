import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sankofa_cli/src/patch_diff_checker.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:sankofa_code_push_client/sankofa_code_push_client.dart';

class FakeArgResults extends Fake implements ArgResults {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class FakeChannel extends Fake implements Channel {}

class FakeDiffStatus extends Fake implements DiffStatus {}

class FakeIOSink extends Fake implements IOSink {}

class FakeRelease extends Fake implements Release {}

class FakeReleaseArtifact extends Fake implements ReleaseArtifact {}

class FakeSankofaProcess extends Fake implements SankofaProcess {}
