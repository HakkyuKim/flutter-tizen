// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
import 'dart:io';

import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';
import 'package:flutter_tizen/commands/create.dart';

import '../flutter/packages/flutter_tools/test/src/common.dart';

import 'common.dart';

void main() {
  Cache.disableLocking();
  Platform platform;
  Directory tempDir;

  setUp(() {
    tempDir =
        globals.fs.systemTempDirectory.createTempSync('flutter_tizen_example');
    platform = const LocalPlatform();
    if (!platform.environment.containsKey('FLUTTER_ROOT')) {
      throw Exception(
          'Must set FLUTTER_ROOT environment variable explicitly before running test');
    }
    Cache.flutterRoot = platform.environment['FLUTTER_ROOT'];
  });

  group('primitive tests', () {
    final List<String> yamlCommentsPositives = <String>[
      '# comment',
      '  # comment',
      '#comment',
      '#####',
      '#',
    ];
    final List<String> yamlCommentsNegatives = <String>[
      'not a comment',
      'not a comment # the line needs to be a comment',
    ];
    final List<String> blankLinePositives = <String>[
      '   ',
      '',
    ];
    final List<String> blankLineNegatives = <String>[
      'not a blank line',
      '  not a blank line',
      'not a blank line   ',
    ];

    for (final String testCase in yamlCommentsPositives) {
      testWithoutContext('comment line positive', () async {
        expect(isComment(testCase), true);
      });
    }

    for (final String testCase in yamlCommentsNegatives) {
      testWithoutContext('comment line negative', () async {
        expect(isComment(testCase), false);
      });
    }

    for (final String testCase in blankLinePositives) {
      testWithoutContext('blank line positive', () async {
        expect(isBlank(testCase), true);
      });
    }

    for (final String testCase in blankLineNegatives) {
      testWithoutContext('blank line negative', () async {
        expect(isBlank(testCase), false);
      });
    }
  });

  testWithoutContext('remove placeholder comments simple', () async {
    const String pubspec = '''
name: sample_app

# comments preserved

flutter:
  # comments preserved
  plugin:
  # comments preserved
    platforms:
    # this is someplace holder to inform no platforms
      some_platform:
        plugin_class: some_plugin
    # comment again

    # comment again

  # comment at different depth

# comments preserved
''';

    const String expected = '''
name: sample_app

# comments preserved

flutter:
  # comments preserved
  plugin:
  # comments preserved
    platforms:

  # comment at different depth

# comments preserved
''';

    final String removed = removePlaceholderComments(pubspec);
    expect(removed, equals(expected));
  });

  testWithoutContext('remove placeholder comments no change', () async {
    const String pubspec = '''
name: sample_app

flutter:
  plugin:
    platforms:
''';

    const String expected = '''
name: sample_app

flutter:
  plugin:
    platforms:
''';

    final String removed = removePlaceholderComments(pubspec);
    expect(removed, equals(expected));
  });

  testWithoutContext(
      'remove placeholder comments different depth comment preserved',
      () async {
    const String pubspec = '''
name: sample_app

flutter:
  plugin:
    platforms:
      some_random_platform
    # comments
    # comments
    # comments
      
    # comments
    # comments
    # comments
  
  #comments
''';

    const String expected = '''
name: sample_app

flutter:
  plugin:
    platforms:
  
  #comments
''';

    final String removed = removePlaceholderComments(pubspec);
    expect(removed, equals(expected));
  });

  testWithoutContext(
      'remove placeholder comments space with differrent dept comment indicate different comment context',
      () async {
    const String pubspec = '''
name: sample_app

flutter:
  plugin:
    platforms:

      # comments preserved
''';

    const String expected = '''
name: sample_app

flutter:
  plugin:
    platforms:

      # comments preserved
''';

    final String removed = removePlaceholderComments(pubspec);
    expect(removed, equals(expected));
  });

  group('updating pubspec for tizen plugin', () {
    const String pluginClassName = 'PluginSamplePlugin';
    const String pluginSourceFileName = 'plugin_sample_plugin.h';
    const String projectName = 'plugin_sample';

    testUsingTizenContext(
      'writes tizen platform in manifest when --platforms option is omitted',
      () async {
        const String pubspec = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
    # erased comments
      some_platform:
        pluginClass: somePluginClass
''';
        const String expected = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      tizen:
        pluginClass: $pluginClassName
        fileName: $pluginSourceFileName
''';

        final FlutterManifest flutterManifest =
            FlutterManifest.createFromString(pubspec, logger: globals.logger);

        final String tizenPluginPubspec = await updateManifestForTizenPlugin(
          pubspec: pubspec,
          flutterManifest: flutterManifest,
          projectName: projectName,
          pluginClassName: pluginClassName,
        );
        expect(tizenPluginPubspec, equals(expected));
      },
    );

    testUsingTizenContext(
      'adds tizen platform in manifest',
      () async {
        const String pubspec = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      android:
        package: com.example
        pluginClass: TestPlugin
      ios:
        pluginClass: HelloPlugin
''';

        const String expected = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      android:
        package: com.example
        pluginClass: TestPlugin
      ios:
        pluginClass: HelloPlugin
      tizen:
        pluginClass: $pluginClassName
        fileName: $pluginSourceFileName
''';

        final FlutterManifest flutterManifest =
            FlutterManifest.createFromString(pubspec, logger: globals.logger);

        final String tizenPluginPubspec = await updateManifestForTizenPlugin(
          pubspec: pubspec,
          flutterManifest: flutterManifest,
          projectName: projectName,
          pluginClassName: pluginClassName,
        );
        expect(tizenPluginPubspec, equals(expected));
      },
    );

    testUsingTizenContext(
      'ignores writing tizen platform if already in manifest',
      () async {
        const String pubspec = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      tizen:
        pluginClass: $pluginClassName
        fileName: $pluginSourceFileName
''';

        const String expected = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  plugin:
    platforms:
      tizen:
        pluginClass: $pluginClassName
        fileName: $pluginSourceFileName
''';

        final FlutterManifest flutterManifest =
            FlutterManifest.createFromString(pubspec, logger: globals.logger);

        final String tizenPluginPubspec = await updateManifestForTizenPlugin(
          pubspec: pubspec,
          flutterManifest: flutterManifest,
          projectName: projectName,
          pluginClassName: pluginClassName,
        );
        expect(tizenPluginPubspec, equals(expected));
      },
    );

    testUsingTizenContext(
      'writes tizen platform while preserving comments',
      () async {
        const String pubspec = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
# also preserved
  plugin:
  # this is preserved

  # also also preserved
    platforms:
    # erased comments
      some_platform:
        pluginClass: somePluginClass

  # preserved comments

  # also preserved

# keep preserving
''';

        const String expected = '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
flutter:
# also preserved
  plugin:
  # this is preserved

  # also also preserved
    platforms:
      tizen:
        pluginClass: $pluginClassName
        fileName: $pluginSourceFileName

  # preserved comments

  # also preserved

# keep preserving
''';

        final FlutterManifest flutterManifest =
            FlutterManifest.createFromString(pubspec, logger: globals.logger);

        final String tizenPluginPubspec = await updateManifestForTizenPlugin(
          pubspec: pubspec,
          flutterManifest: flutterManifest,
          projectName: projectName,
          pluginClassName: pluginClassName,
        );
        expect(tizenPluginPubspec, equals(expected));
      },
    );
  });
}
