import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:sankofa_cli/src/code_push_client_wrapper.dart';
import 'package:sankofa_cli/src/common_arguments.dart';
import 'package:sankofa_cli/src/config/config.dart';
import 'package:sankofa_cli/src/doctor.dart';
import 'package:sankofa_cli/src/executables/executables.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/native_config_editor.dart';
import 'package:sankofa_cli/src/platform/platform.dart';
import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';
import 'package:sankofa_cli/src/sankofa_documentation.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';
import 'package:sankofa_code_push_client/sankofa_code_push_client.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template init_command}
///
/// `sankofa init`
/// Initialize Sankofa.
/// {@endtemplate}
class InitCommand extends SankofaCommand {
  /// {@macro init_command}
  InitCommand() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Initialize the app even if a "sankofa.yaml" already exists.',
        negatable: false,
      )
      ..addOption(
        'display-name',
        help:
            'The app name shown in the Sankofa dashboard '
            '(defaults to the package name in pubspec.yaml). '
            'Must be between 1 and '
            '${CommonArguments.appDisplayNameMaxLength} characters.',
      )
      ..addOption('organization-id', help: 'The organization ID to use.');
  }

  @override
  String get description => 'Initialize Sankofa.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    try {
      await sankofaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    try {
      if (!sankofaEnv.hasPubspecYaml) {
        logger.err('''
Could not find a "pubspec.yaml".
Please make sure you are running "sankofa init" from within your Flutter project.
''');
        return ExitCode.noInput.code;
      }
    } on Exception catch (error) {
      logger.err('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    final organizationMemberships = await codePushClientWrapper
        .getOrganizationMemberships();
    if (organizationMemberships.isEmpty) {
      logger.err(
        '''You do not have any organizations. This should never happen. Please contact us on Discord or send us an email at contact@sankofa.dev.''',
      );
      return ExitCode.software.code;
    }

    final Organization organization;
    final orgIdArg = results['organization-id'] as String?;
    if (orgIdArg != null) {
      final orgId = int.tryParse(orgIdArg);
      if (orgId == null) {
        logger.err('Invalid organization ID: "$orgIdArg"');
        return ExitCode.usage.code;
      }

      final organizationMembership = organizationMemberships.firstWhereOrNull(
        (o) => o.organization.id == orgId,
      );
      if (organizationMembership == null) {
        logger.err('Organization with ID "$orgId" not found.');
        _logAvailableOrganizations(organizationMemberships);
        return ExitCode.usage.code;
      }
      organization = organizationMembership.organization;
    } else if (organizationMemberships.length > 1) {
      if (!sankofaEnv.canAcceptUserInput) {
        logger.err(
          'Multiple organizations found. '
          'Use --organization-id to specify one:',
        );
        _logAvailableOrganizations(organizationMemberships);
        return ExitCode.usage.code;
      }
      organization = logger.chooseOne(
        'Which organization should this app belong to?',
        choices: organizationMemberships.map((o) => o.organization).toList(),
        display: (o) => o.name,
        hint:
            'Pass --organization-id=<id> to select an organization without '
            'prompting.',
      );
    } else {
      organization = organizationMemberships.first.organization;
    }

    final force = results['force'] == true;

    Set<String>? androidFlavors;
    Set<String>? iosFlavors;
    Set<String>? macosFlavors;
    var productFlavors = <String>{};
    final projectRoot = sankofaEnv.getFlutterProjectRoot()!;
    final initializeGradleProgress = logger.progress('Initializing gradlew');
    final bool shouldStartGradleDaemon;
    try {
      shouldStartGradleDaemon = await _shouldStartGradleDaemon(
        projectRoot.path,
      );
    } on Exception {
      initializeGradleProgress.fail();
      logger.err('Unable to initialize gradlew.');
      return ExitCode.software.code;
    }
    initializeGradleProgress.complete();

    if (shouldStartGradleDaemon) {
      try {
        await gradlew.startDaemon(projectRoot.path);
      } on Exception {
        logger.err('Unable to start gradle daemon.');
        return ExitCode.software.code;
      }
    }

    final detectFlavorsProgress = logger.progress('Detecting product flavors');
    try {
      androidFlavors = await _maybeGetAndroidFlavors(projectRoot.path);
      iosFlavors = apple.flavors(platform: ApplePlatform.ios);
      macosFlavors = apple.flavors(platform: ApplePlatform.macos);
      productFlavors = <String>{
        if (androidFlavors != null) ...androidFlavors,
        if (iosFlavors != null) ...iosFlavors,
        if (macosFlavors != null) ...macosFlavors,
      };
      if (productFlavors.isEmpty) {
        detectFlavorsProgress.complete('No product flavors detected.');
      } else {
        detectFlavorsProgress.complete(
          '${productFlavors.length} product flavors detected:',
        );
        for (final flavor in productFlavors) {
          logger.info('  - $flavor');
        }
      }
    } on Exception catch (error) {
      detectFlavorsProgress.fail();
      logger.err('Unable to extract product flavors.\n$error');
      return ExitCode.software.code;
    }

    final sankofaYaml = sankofaEnv.getSankofaYaml();
    final existingFlavors = sankofaYaml?.flavors;
    Set<String> newFlavors;
    if (existingFlavors != null) {
      final existingFlavorNames = existingFlavors.keys.toSet();
      newFlavors = productFlavors.difference(existingFlavorNames);
    } else if (sankofaYaml != null) {
      // Existing sankofa.yaml without flavors — treat all detected flavors
      // as new so they can be added without resetting the base app_id.
      newFlavors = productFlavors;
    } else {
      newFlavors = {};
    }

    // New flavors not being empty means that there is already an existing app
    // and we just need to add the new flavor entries.
    // If the --force flag is present, we will completely reinit the app and
    // don't care about which flavors are new.
    if (!force && newFlavors.isNotEmpty) {
      logger.info('New flavors detected: ${newFlavors.join(', ')}');
      final updateSankofaYamlProgress = logger.progress(
        'Adding flavors to sankofa.yaml',
      );

      final AppMetadata existingApp;
      try {
        existingApp = await codePushClientWrapper.getApp(
          appId: sankofaYaml!.appId,
        );
      } on Exception catch (e) {
        updateSankofaYamlProgress.fail('Failed to get existing app info: $e');
        return ExitCode.software.code;
      }

      final deflavoredAppName = existingApp.displayName
          .replaceAll(RegExp(r'\(.*\)'), '')
          .trim();
      final flavorsToAppIds = sankofaYaml.flavors ?? {};
      for (final flavor in newFlavors) {
        final app = await codePushClientWrapper.createApp(
          appName: '$deflavoredAppName ($flavor)',
          organizationId: organization.id,
        );
        flavorsToAppIds[flavor] = app.id;
      }
      _addSankofaYamlToProject(
        projectRoot: projectRoot,
        appId: sankofaYaml.appId,
        flavors: flavorsToAppIds,
      );
      updateSankofaYamlProgress.complete('Flavors added to sankofa.yaml');
      return ExitCode.success.code;
    }

    if (!force && sankofaEnv.hasSankofaYaml) {
      logger
        ..err('A "sankofa.yaml" file already exists and seems up-to-date.')
        ..info(
          '''If you want to reinitialize Sankofa, please run ${lightCyan.wrap('sankofa init --force')}.''',
        );
      return ExitCode.software.code;
    }

    final String appId;
    Map<String, String>? flavors;
    try {
      final needsConfirmation = !force && sankofaEnv.canAcceptUserInput;
      final pubspecName = sankofaEnv.getPubspecYaml()!.name;
      var displayName = results['display-name'] as String?;
      displayName ??= needsConfirmation
          ? logger.prompt(
              '${lightGreen.wrap('?')} How should we refer to this app?',
              defaultValue: pubspecName,
              hint:
                  'Pass --display-name=<name> to set the app name without '
                  'prompting.',
            )
          : pubspecName;
      if (displayName.isEmpty ||
          displayName.length > CommonArguments.appDisplayNameMaxLength) {
        logger.err(
          'App display name must be between 1 and '
          '${CommonArguments.appDisplayNameMaxLength} characters.',
        );
        return ExitCode.usage.code;
      }
      final hasNoFlavors = productFlavors.isEmpty;
      final hasSomeFlavors =
          productFlavors.isNotEmpty &&
          ((androidFlavors?.isEmpty ?? false) ||
              (iosFlavors?.isEmpty ?? false));

      if (hasNoFlavors) {
        // No platforms have any flavors so we just create a single app
        // and assign it as the default.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
      } else if (hasSomeFlavors) {
        // Some platforms have flavors and some do not so we create an app
        // for the default (no flavor) and then create an app per flavor.
        final app = await codePushClientWrapper.createApp(
          appName: displayName,
          organizationId: organization.id,
        );
        appId = app.id;
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
      } else {
        // All platforms have flavors so we create an app per flavor
        // and assign the default to the first flavor.
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
            organizationId: organization.id,
          );
          values[flavor] = app.id;
        }
        flavors = values;
        appId = flavors.values.first;
      }
    } on Exception catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    final newSankofaYaml = _addSankofaYamlToProject(
      projectRoot: projectRoot,
      appId: appId,
      flavors: flavors,
    );

    if (!sankofaEnv.pubspecContainsSankofaYaml) {
      pubspecEditor.addSankofaYamlToPubspecAssets();
    }

    // Phase 0.75 native config — write the Sankofa app_id directly into the
    // host app's AndroidManifest meta-data and ios/Runner/Info.plist so the
    // Sankofa Flutter engine can pick it up at startup without depending on
    // the bundled YAML asset. Additive to the asset entry above (engine
    // prefers native, falls back to asset), so existing tooling stays valid.
    nativeConfigEditor
      ..syncAndroidManifestMetadata(config: newSankofaYaml)
      ..syncIosInfoPlist(config: newSankofaYaml);

    logger.info(
      '''

${lightGreen.wrap('🐦 Sankofa initialized successfully!')}

✅ A sankofa app has been created.
✅ A "sankofa.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "sankofa.yaml" as an asset.
✅ Native platform config wired into AndroidManifest.xml and ios/Runner/Info.plist.

Reference the following commands to get started:

📦 To create a new release use: "${lightCyan.wrap('sankofa release')}".
🚀 To push an update use: "${lightCyan.wrap('sankofa patch')}".
👀 To preview a release use: "${lightCyan.wrap('sankofa preview')}".

For more information about Sankofa, visit ${link(uri: Uri.parse('https://sankofa.dev'))}''',
    );

    await doctor.runValidators(
      doctor.initAndDoctorValidators,
      applyFixes: true,
    );

    return ExitCode.success.code;
  }

  Future<bool> _shouldStartGradleDaemon(String projectPath) async {
    try {
      final isAvailable = await gradlew.isDaemonAvailable(projectPath);
      return !isAvailable;
    } on MissingAndroidProjectException {
      return false;
    }
  }

  Future<Set<String>?> _maybeGetAndroidFlavors(String projectPath) async {
    try {
      return await gradlew.productFlavors(projectPath);
    } on MissingAndroidProjectException {
      return null;
    }
  }

  SankofaYaml _addSankofaYamlToProject({
    required String appId,
    required Directory projectRoot,
    Map<String, String>? flavors,
  }) {
    const content =
        '''
# This file is used to configure the Sankofa updater used by your app.
# Learn more at $docsUrl
# This file does not contain any sensitive information and should be checked into version control.

# Your app_id is the unique identifier assigned to your app.
# It is used to identify your app when requesting patches from Sankofa's servers.
# It is not a secret and can be shared publicly.
app_id:

# auto_update controls if Sankofa should automatically update in the background on launch.
# If auto_update: false, you will need to use package:sankofa_code_push to trigger updates.
# https://pub.dev/packages/sankofa_code_push
# Uncomment the following line to disable automatic updates.
# auto_update: false
''';

    final editor = YamlEditor(content)..update(['app_id'], appId);

    if (flavors != null) editor.update(['flavors'], flavors);

    sankofaEnv
        .getSankofaYamlFile(cwd: projectRoot)
        .writeAsStringSync(editor.toString());

    return SankofaYaml(appId: appId);
  }

  void _logAvailableOrganizations(
    List<OrganizationMembership> memberships,
  ) {
    logger.info('Available organizations:');
    for (final membership in memberships) {
      final org = membership.organization;
      logger.info('  ${org.name} (id: ${org.id})');
    }
  }
}
