// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_tizen/tizen_sdk.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/dart/pub.dart';

import 'package:flutter_tizen/commands/build.dart';
import 'package:flutter_tizen/commands/clean.dart';
import 'package:flutter_tizen/commands/packages.dart';
import 'package:flutter_tizen/commands/create.dart';
import 'package:flutter_tizen/tizen_artifacts.dart';
import 'package:flutter_tizen/tizen_tpk.dart';
import 'package:meta/meta.dart';

import '../flutter/packages/flutter_tools/test/src/common.dart';
import '../flutter/packages/flutter_tools/test/src/context.dart';

/// Original source: [createproject] from `common.dart`
Future<String> createTizenProject(Directory temp,
    {List<String> arguments}) async {
  return await createTizenProjectWithName(
    temp,
    'flutter_project',
    arguments: arguments,
  );
}

Future<String> createTizenProjectWithName(
  Directory temp,
  String projectName, {
  List<String> arguments,
}) async {
  arguments ??= <String>['--no-pub'];
  final String projectPath = globals.fs.path.join(temp.path, projectName);
  final TizenCreateCommand command = TizenCreateCommand();
  final CommandRunner<void> runner = createTestCommandRunner(command);
  await runner.run(<String>['create', ...arguments, projectPath]);
  // Created `.packages` since it's not created when the flag `--no-pub` is passed.
  globals.fs.file(globals.fs.path.join(projectPath, '.packages')).createSync();
  return projectPath;
}

Future<TizenCleanCommand> runCleanCommand(String projectPath,
    {List<String> arguments}) async {
  final TizenCleanCommand command = TizenCleanCommand();
  final CommandRunner<void> runner = createTestCommandRunner(command);
  await runner.run(<String>[
    'clean',
    ...?arguments,
    projectPath,
  ]);
  return command;
}

/// Original source: [runCommandIn] from `packages_test.dart`
Future<TizenPackagesCommand> runPackagesCommand(String projectPath, String verb,
    {List<String> arguments}) async {
  final TizenPackagesCommand command = TizenPackagesCommand();
  final CommandRunner<void> runner = createTestCommandRunner(command);
  await runner.run(<String>[
    'packages',
    verb,
    ...?arguments,
    projectPath,
  ]);
  return command;
}

/// Original source: [runBuildApkCommand] from `build_apk_test.dart`
Future<TizenBuildCommand> runBuildTpkCommand(String projectPath,
    {List<String> arguments}) async {
  final TizenBuildCommand command = TizenBuildCommand();
  final CommandRunner<void> runner = createTestCommandRunner(command);
  await runner.run(<String>[
    'build',
    'tpk',
    ...?arguments,
    '--no-pub',
    globals.fs.path.join(projectPath, 'lib', 'main.dart'),
  ]);
  return command;
}

Directory getTizenSdkDir() {
  const Platform platform = LocalPlatform();
  if (!platform.environment.containsKey('TIZEN_SDK')) {
    throw Exception(
        'Must set TIZEN_SDK environment variable explicitly before running test');
  }
  return globals.fs.directory(platform.environment['TIZEN_SDK']);
}

/// Original source: [testUsingContext] from `build_apk_test.dart`
@isTest
void testUsingTizenContext(
  String description,
  dynamic testMethod(), {
  Map<Type, Generator> overrides = const <Type, Generator>{},
  bool skip,
}) {
  const Platform platform = LocalPlatform();
  if (!platform.environment.containsKey('FLUTTER_ROOT')) {
    throw Exception(
        'Must set FLUTTER_ROOT environment variable explicitly before running test');
  }

  final Map<Type, Generator> tizenOverrides = <Type, Generator>{
    TizenSdk: () => TizenSdk.locateSdk(),
    ApplicationPackageFactory: () => TpkFactory(),
    TizenArtifacts: () => TizenArtifacts(),
    // Allows finding flutter project
    FlutterProjectFactory: () => FlutterProjectFactory(
          fileSystem: globals.fs,
          logger: globals.logger,
        ),
    // Allows running pub in tests
    Pub: () => Pub(
          fileSystem: globals.fs,
          logger: globals.logger,
          processManager: globals.processManager,
          usage: globals.flutterUsage,
          botDetector: globals.botDetector,
          platform: globals.platform,
        ),
    // Allows finding dotnet cli
    OperatingSystemUtils: () => OperatingSystemUtils(
          fileSystem: globals.fs,
          logger: globals.logger,
          platform: globals.platform,
          processManager: globals.processManager,
        ),
  };
  tizenOverrides.addEntries(overrides.entries);

  testUsingContext(
    description,
    testMethod,
    overrides: tizenOverrides,
    skip: skip,
  );
}
