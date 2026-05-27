// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'build_environment_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BuildEnvironmentMetadata _$BuildEnvironmentMetadataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'BuildEnvironmentMetadata',
  json,
  ($checkedConvert) {
    final val = BuildEnvironmentMetadata(
      flutterRevision: $checkedConvert('flutter_revision', (v) => v as String),
      sankofaVersion: $checkedConvert(
        'sankofa_version',
        (v) => v as String,
      ),
      operatingSystem: $checkedConvert('operating_system', (v) => v as String),
      operatingSystemVersion: $checkedConvert(
        'operating_system_version',
        (v) => v as String,
      ),
      sankofaYaml: $checkedConvert(
        'sankofa_yaml',
        (v) => SankofaYaml.fromJson(v as Map<String, dynamic>),
      ),
      usesSankofaCodePushPackage: $checkedConvert(
        'uses_sankofa_code_push_package',
        (v) => v as bool,
      ),
      xcodeVersion: $checkedConvert('xcode_version', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'flutterRevision': 'flutter_revision',
    'sankofaVersion': 'sankofa_version',
    'operatingSystem': 'operating_system',
    'operatingSystemVersion': 'operating_system_version',
    'sankofaYaml': 'sankofa_yaml',
    'usesSankofaCodePushPackage': 'uses_sankofa_code_push_package',
    'xcodeVersion': 'xcode_version',
  },
);

Map<String, dynamic> _$BuildEnvironmentMetadataToJson(
  BuildEnvironmentMetadata instance,
) => <String, dynamic>{
  'flutter_revision': instance.flutterRevision,
  'sankofa_version': instance.sankofaVersion,
  'operating_system': instance.operatingSystem,
  'operating_system_version': instance.operatingSystemVersion,
  'sankofa_yaml': instance.sankofaYaml.toJson(),
  'uses_sankofa_code_push_package': instance.usesSankofaCodePushPackage,
  'xcode_version': instance.xcodeVersion,
};
