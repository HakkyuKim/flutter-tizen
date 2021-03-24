// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
import 'dart:io';

import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';

import 'package:yaml/yaml.dart';

import '../flutter/packages/flutter_tools/test/src/android_common.dart';
import '../flutter/packages/flutter_tools/test/src/common.dart';
import '../flutter/packages/flutter_tools/test/src/context.dart';

import 'common.dart';

// To run the tests, you must set two environment variables on the running system
// For example, in Linux,
// FLUTTER_ROOT: path to the flutter-tizen/flutter direcotry
// TIZEN_SDK: path to the tizen-studio directory
void main() {
  Cache.disableLocking();

  Directory tempDir;

  setUp(() {
    tempDir =
        globals.fs.systemTempDirectory.createTempSync('flutter_tizen_example');
  });

  tearDown(() {
    tryToDelete(tempDir);
  });

  testUsingTizenContext(
    'flutter-tizen create -t plugin automatically adds tizen platform in pubspec',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub', '-t', 'plugin'],
      );

      await runPackagesCommand(flutterProject, 'get');
      final File pubspecFile =
          tempDir.childDirectory('flutter_project').childFile('pubspec.yaml');

      final FlutterManifest manifest = FlutterManifest.createFromPath(
        pubspecFile.path,
        fileSystem: globals.fs,
        logger: globals.logger,
      );

      final Map<String, dynamic> supportedPlatforms =
          manifest.supportedPlatforms;
      expect(supportedPlatforms.containsKey('tizen'), true);

      final YamlMap yamlMap =
          loadYaml(pubspecFile.readAsStringSync()) as YamlMap;

      //flutter:
      //  plugin:
      //    platforms:
      //      tizen:
      //        pluginClass: FlutterProjectPlugin
      //        fileName: flutter_project_plugin.h
      expect(
          (yamlMap['flutter']['plugin']['platforms'] as YamlMap)
              .containsKey('tizen'),
          true);

      final YamlMap tizenMap =
          yamlMap['flutter']['plugin']['platforms']['tizen'] as YamlMap;
      expect(
          tizenMap.containsKey('pluginClass') &&
              tizenMap['pluginClass'] == 'FlutterProjectPlugin',
          true);
      expect(
          tizenMap.containsKey('fileName') &&
              tizenMap['fileName'] == 'flutter_project_plugin.h',
          true);
    },
    overrides: <Type, Generator>{
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  testUsingTizenContext(
    'flutter-tizen create --platforms=android,ios -t plugin adds tizen platform in pubspec',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>[
          '--no-pub',
          '--platforms=android,ios',
          '-t',
          'plugin'
        ],
      );

      await runPackagesCommand(flutterProject, 'get');
      final File pubspecFile =
          tempDir.childDirectory('flutter_project').childFile('pubspec.yaml');

      final FlutterManifest manifest = FlutterManifest.createFromPath(
        pubspecFile.path,
        fileSystem: globals.fs,
        logger: globals.logger,
      );

      final Map<String, dynamic> supportedPlatforms =
          manifest.supportedPlatforms;
      expect(supportedPlatforms.containsKey('android'), true);
      expect(supportedPlatforms.containsKey('ios'), true);
      expect(supportedPlatforms.containsKey('tizen'), true);
    },
    overrides: <Type, Generator>{
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );
}
