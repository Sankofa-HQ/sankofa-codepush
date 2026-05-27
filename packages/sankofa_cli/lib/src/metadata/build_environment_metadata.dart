import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sankofa_cli/src/config/config.dart';

part 'build_environment_metadata.g.dart';

/// {@template build_environment_metadata}
/// Information about the environment used to build a release or patch.
///
/// Collection of this information is done to help Sankofa users debug any
/// later failures in their builds.
///
/// We do not collect Personally Identifying Information (e.g. no paths,
/// argument lists, etc.) in accordance with our privacy policy:
/// https://sankofa.dev/privacy/
/// {@endtemplate}
@JsonSerializable()
class BuildEnvironmentMetadata extends Equatable {
  /// {@macro build_environment_metadata}
  const BuildEnvironmentMetadata({
    required this.flutterRevision,
    required this.sankofaVersion,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.sankofaYaml,
    required this.usesSankofaCodePushPackage,
    this.xcodeVersion,
  });

  /// coverage:ignore-start
  /// Creates a [BuildEnvironmentMetadata] with overridable default values for
  /// testing purposes.
  factory BuildEnvironmentMetadata.forTest({
    String flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
    String sankofaVersion = '4.5.6',
    String operatingSystem = 'macos',
    String operatingSystemVersion = '1.2.3',
    SankofaYaml sankofaYaml = const SankofaYaml(appId: '123'),
    bool usesSankofaCodePushPackage = false,
    String? xcodeVersion = '15.0',
  }) => BuildEnvironmentMetadata(
    flutterRevision: flutterRevision,
    sankofaVersion: sankofaVersion,
    operatingSystem: operatingSystem,
    operatingSystemVersion: operatingSystemVersion,
    sankofaYaml: sankofaYaml,
    usesSankofaCodePushPackage: usesSankofaCodePushPackage,
    xcodeVersion: xcodeVersion,
  );
  // coverage:ignore-end

  /// Converts a `Map<String, dynamic>` to a [BuildEnvironmentMetadata]
  factory BuildEnvironmentMetadata.fromJson(Map<String, dynamic> json) =>
      _$BuildEnvironmentMetadataFromJson(json);

  /// Converts a [BuildEnvironmentMetadata] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$BuildEnvironmentMetadataToJson(this);

  /// Creates a copy of this [BuildEnvironmentMetadata] with the given fields
  /// replaced by the new values.
  BuildEnvironmentMetadata copyWith({
    String? flutterRevision,
    String? sankofaVersion,
    String? operatingSystem,
    String? operatingSystemVersion,
    SankofaYaml? sankofaYaml,
    bool? usesSankofaCodePushPackage,
    String? xcodeVersion,
  }) => BuildEnvironmentMetadata(
    flutterRevision: flutterRevision ?? this.flutterRevision,
    sankofaVersion: sankofaVersion ?? this.sankofaVersion,
    operatingSystem: operatingSystem ?? this.operatingSystem,
    operatingSystemVersion:
        operatingSystemVersion ?? this.operatingSystemVersion,
    sankofaYaml: sankofaYaml ?? this.sankofaYaml,
    usesSankofaCodePushPackage:
        usesSankofaCodePushPackage ?? this.usesSankofaCodePushPackage,
    xcodeVersion: xcodeVersion ?? this.xcodeVersion,
  );

  /// The revision of Flutter used to run the command.
  ///
  /// Reason: often times we want to track things like link percentage
  /// which are tied to a flutter revision as opposed to a sankofa version.
  final String flutterRevision;

  /// The version of Sankofa used to run the command.
  ///
  /// Reason: each version of sankofa has new features and bug fixes. Users
  /// using an older version may be running into issues that have already been
  /// fixed.
  final String sankofaVersion;

  /// The operating system used to run the release command.
  ///
  /// Reason: issues may occur on some OSes and not others (especially Windows
  /// vs non-Windows).
  final String operatingSystem;

  /// The version of [operatingSystem].
  ///
  /// Reason: issues may occur on some OS versions and not others.
  final String operatingSystemVersion;

  /// The sankofa.yaml file for this project.
  final SankofaYaml sankofaYaml;

  /// Whether the project uses package:sankofa_code_push.
  ///
  /// Reason: this helps us understand which projects are using the Sankofa
  /// CodePush package and better support customers who encounter issues.
  final bool usesSankofaCodePushPackage;

  /// The version of Xcode used to build the patch. Only provided for iOS
  /// patches.
  ///
  /// Reason: Xcode behavior can change between versions. Ex: the
  /// `sankofa preview` mechanism changed entirely between Xcode 14 and 15.
  final String? xcodeVersion;

  @override
  List<Object?> get props => [
    flutterRevision,
    sankofaVersion,
    operatingSystem,
    operatingSystemVersion,
    sankofaYaml,
    usesSankofaCodePushPackage,
    xcodeVersion,
  ];
}
