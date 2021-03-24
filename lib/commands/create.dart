// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/flutter_project_metadata.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/template.dart';
import 'package:flutter_tools/src/base/process.dart';

import '../tizen_plugins.dart';

class TizenCreateCommand extends CreateCommand {
  TizenCreateCommand() : super() {
    argParser.addOption(
      'tizen-language',
      defaultsTo: 'csharp',
      allowed: <String>['cpp', 'csharp'],
    );
  }

  @override
  void printUsage() {
    super.printUsage();
    // TODO(swift-kim): I couldn't find a proper way to override the --platforms
    // option without copying the entire class. This message is a workaround.
    print(
      'You don\'t have to specify "tizen" as a target platform with '
      '"--platforms" option. It is automatically added by default.',
    );
  }

  /// See:
  /// - [CreateCommand.runCommand] in `create.dart`
  /// - [CreateCommand._getProjectType] in `create.dart` (generatePlugin)
  Future<FlutterCommandResult> runInternal() async {
    final FlutterCommandResult result = await super.runCommand();
    if (result != FlutterCommandResult.success() || argResults.rest.isEmpty) {
      return result;
    }

    final bool generatePlugin = argResults['template'] != null
        ? stringArg('template') == FlutterProjectType.plugin.name
        : determineTemplateType() == FlutterProjectType.plugin;
    if (generatePlugin) {
      // Assume that pubspec.yaml uses the multi-platforms plugin format if the
      // file already exists.

      final File pubspecFile = projectDir.childFile('pubspec.yaml');
      final FlutterManifest flutterManifest = FlutterManifest.createFromPath(
        pubspecFile.path,
        fileSystem: globals.fs,
        logger: globals.logger,
      );

      final String pubspec =
          projectDir.childFile('pubspec.yaml').readAsStringSync();
      final Map<String, dynamic> templateContext = createTemplateContext(
        organization: '',
        projectName: projectName,
        flutterRoot: '',
      );
      final String tizenPluginPubspecString =
          await updateManifestForTizenPlugin(
        pubspec: pubspec,
        flutterManifest: flutterManifest,
        projectName: projectName,
        pluginClassName: templateContext['pluginClass'] as String,
      );

      pubspecFile.writeAsStringSync(tizenPluginPubspecString);
    }

    // Actually [super.runCommand] runs [ensureReadyForPlatformSpecificTooling]
    // based on the target project type. The following code doesn't check the
    // project type for simplicity. Revisit if this makes any problem.
    if (boolArg('pub')) {
      final FlutterProject project = FlutterProject.fromDirectory(projectDir);
      await injectTizenPlugins(project);
      if (project.hasExampleApp) {
        await injectTizenPlugins(project.example);
      }
    }
    return result;
  }

  /// See: [Template.render] in `template.dart`
  @override
  Future<FlutterCommandResult> runCommand() async {
    // The template directory that the flutter tools search for available
    // templates cannot be overriden because the implementation is private.
    // So we have to copy Tizen templates into the directory manually.
    final Directory tizenTemplates = globals.fs
        .directory(Cache.flutterRoot)
        .parent
        .childDirectory('templates');
    if (!tizenTemplates.existsSync()) {
      throwToolExit('Could not locate Tizen templates.');
    }
    final File tizenTemplateManifest =
        tizenTemplates.childFile('template_manifest.json');

    final Directory templates = globals.fs
        .directory(Cache.flutterRoot)
        .childDirectory('packages')
        .childDirectory('flutter_tools')
        .childDirectory('templates');
    final File templateManifest = templates.childFile('template_manifest.json');
    final File backupTemplateManifest =
        templates.childFile('template_manifest.json.bak');

    // This is required due to: https://github.com/flutter/flutter/pull/59706
    // TODO(swift-kim): Find any better workaround. One option is to override
    // renderTemplate() but it may result in additional complexity.
    if (templateManifest.existsSync() && !backupTemplateManifest.existsSync()) {
      templateManifest.renameSync(backupTemplateManifest.path);
      tizenTemplateManifest.copySync(templateManifest.path);
    }

    final String language = stringArg('tizen-language');
    if (language == 'cpp') {
      globals.printStatus(
        'Warning: The Tizen language option is experimental. Use it for testing purposes only.',
        color: TerminalColor.yellow,
      );
    }
    // The dart plugin template is not supported at the moment.
    const String pluginType = 'cpp';
    final List<Directory> created = <Directory>[];
    try {
      for (final Directory projectType
          in tizenTemplates.listSync().whereType<Directory>()) {
        final Directory source = projectType.childDirectory(
            projectType.basename == 'plugin' ? pluginType : language);
        if (!source.existsSync()) {
          continue;
        }
        final Directory dest = templates
            .childDirectory(projectType.basename)
            .childDirectory('tizen.tmpl');
        if (dest.existsSync()) {
          dest.deleteSync(recursive: true);
        }
        globals.fsUtils.copyDirectorySync(source, dest);
        created.add(dest);
      }
      return await runInternal();
    } finally {
      for (final Directory template in created) {
        template.deleteSync(recursive: true);
      }
    }
  }
}

// original: the unmodified pubspec string fron pubspec.yaml file
// filtered: comments and blanklines removed
Future<String> updateManifestForTizenPlugin({
  @required String pubspec,
  @required FlutterManifest flutterManifest,
  @required String projectName,
  @required String pluginClassName,
}) async {
  // pubspec already contains tizen platform
  if (flutterManifest.supportedPlatforms.containsKey('tizen')) {
    return pubspec;
  }

  if (flutterManifest.validSupportedPlatforms == null) {
    pubspec = removePlaceholderComments(pubspec);
  }

  final Map<String, dynamic> yaml = decodeYaml(pubspec);

  // possible null case:
  //
  // flutter:
  //   plugin:
  //     platforms:
  yaml['flutter']['plugin']['platforms'] ??= <String, dynamic>{};

  yaml['flutter']['plugin']['platforms']['tizen'] = <String, dynamic>{
    'pluginClass': pluginClassName,
    'fileName': '${projectName}_plugin.h'
  };
  final String yamlString = await encodeYaml(yaml);

  final String tizenPluginPubspecString =
      await encodeCommentsAndBlankLines(yamlString, pubspec);
  return tizenPluginPubspecString;
}

const int _defaultYamlIndent = 2;

bool isCommentOrBlankLine(String line) {
  return isComment(line) || isBlank(line);
}

bool isBlank(String line) {
  return line.trim().isEmpty;
}

bool isComment(String line) {
  return line.trim().startsWith('#');
}

String removePlaceholderComments(String yaml) {
  final List<String> lines = yaml.trim().split('\n');
  int leftRange = -1;
  int rightRange = -1;
  final Context context = Context.create();
  for (int i = 0; i < lines.length; ++i) {
    final String line = lines[i];
    context.feed(line);
    if (context.isFinished) {
      ++i;
      leftRange = i;
      rightRange = i - 1;
      while (i < lines.length) {
        if (isComment(lines[i])) {
          final int indent = lines[i].indexOf('#');
          // defaultIndent * depth
          if (indent == _defaultYamlIndent * 2) {
            rightRange = i;
          } else {
            break;
          }
        } else if (!isBlank(lines[i])) {
          rightRange = i;
        }
        ++i;
      }
      break;
    }
  }
  final List<String> linesSubset =
      lines.sublist(0, leftRange) + lines.sublist(rightRange + 1);

  return linesSubset.map((String line) => line + '\n').join();
}

Future<String> encodeCommentsAndBlankLines(
  String filteredTizenPubspec,
  String pubspec,
) async {
  // parse blank lines and comments
  final List<IgnoredYamlLine> ignoredYamlLines =
      IgnoredYamlLine.filter(pubspec);

  // decoding a yaml string and encoding it back removes comments and blank lines
  final String filteredPubspec = await encodeYaml(decodeYaml(pubspec));

  String yamlString = '';
  final List<String> lines = filteredTizenPubspec.trim().split('\n');

  int firstDiffIndex = -1;
  int lastDiffIndex = -1;
  final List<String> originalLines = filteredPubspec.trim().split('\n');

  for (int i = 0; i < lines.length; ++i) {
    if (i == originalLines.length) {
      break;
    }
    if (lines[i] != originalLines[i]) {
      firstDiffIndex = i;
      lastDiffIndex = i + 1;
      while (i + 1 < originalLines.length &&
          lines[lastDiffIndex] != originalLines[i]) {
        lastDiffIndex++;
      }
      lastDiffIndex =
          lastDiffIndex == originalLines.length ? lines.length : lastDiffIndex;
      break;
    }
  }
  if (firstDiffIndex == -1) {
    firstDiffIndex = originalLines.length;
    lastDiffIndex = lines.length;
  }

  int acc = 0;
  int i = 0;
  for (int index = 0; index < lines.length; ++index) {
    if (index == firstDiffIndex) {
      while (index < lastDiffIndex) {
        yamlString += lines[index++] + '\n';
      }
    }
    while (
        i < ignoredYamlLines.length && acc == ignoredYamlLines[i].lineNumber) {
      yamlString += ignoredYamlLines[i].value + '\n';
      i++;
      acc++;
    }
    if (index < lines.length) {
      yamlString += lines[index] + '\n';
      acc++;
    }
  }
  return yamlString;
}

Future<String> encodeYaml(Map<String, dynamic> yaml) async {
  final ProcessUtils processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  final String flutterTizenPath = normalize(join(
    globals.fs.directory(Cache.flutterRoot).path,
    '../',
  ));
  final Directory scriptDir =
      globals.fs.directory(flutterTizenPath).childDirectory('script');

  scriptDir.childFile('temp.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(yaml));

  final String script = join(flutterTizenPath, 'script', 'json_to_yaml.py');
  try {
    final RunResult result = await processUtils.run(
        <String>['python3', script, scriptDir.childFile('temp.json').path],
        throwOnError: true);
    if (result.exitCode != 0) {
      throwToolExit('Failed to encode yaml string.');
    }
  } on ProcessException catch (ex) {
    throwToolExit('Failed to encode yaml string: $ex');
  }

  final String yamlString = scriptDir.childFile('temp.yaml').readAsStringSync();
  scriptDir.childFile('temp.json').deleteSync(recursive: true);
  scriptDir.childFile('temp.yaml').deleteSync(recursive: true);
  return yamlString;
}

Map<String, dynamic> decodeYaml(String yamlString) {
  final YamlMap yamlMap = loadYaml(yamlString) as YamlMap;
  final String jsonString = jsonEncode(yamlMap.value);
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

// Represents lines that are generally ignored by yaml decoders:
// comments and blank lines
class IgnoredYamlLine {
  IgnoredYamlLine._(this.lineNumber, this.value)
      : indent = value?.isNotEmpty ?? false ? value.indexOf('#') : 0;

  static List<IgnoredYamlLine> filter(String yaml) {
    final List<String> lines = yaml.trim().split('\n');
    final List<IgnoredYamlLine> ignoredYamlLines = <IgnoredYamlLine>[];
    for (int lineNum = 0; lineNum < lines.length; ++lineNum) {
      final String line = lines[lineNum];
      if (isBlank(line) || isComment(line)) {
        ignoredYamlLines.add(IgnoredYamlLine._(lineNum, line));
      }
    }
    return ignoredYamlLines;
  }

  final int lineNumber;
  final int indent;
  final String value;

  bool get isBlankLine => isBlank(value);
  bool get isCommentLine => isComment(value);
}

class Context {
  Context._(this._state);

  factory Context.create() {
    final InitialState initialState = InitialState();
    final Context context = Context._(initialState);
    initialState.context = context;
    return context;
  }

  _State _state;

  set state(_State state) {
    _state = state;
    state.context = this;
  }

  void feed(String line) {
    _state.feed(line);
  }

  bool get isFinished => _state.runtimeType == PlatformState;
}

abstract class _State {
  Context _context;
  set context(Context context) {
    _context = context;
  }

  void feed(String line);
}

class InitialState extends _State {
  @override
  void feed(String line) {
    if (line.startsWith('flutter')) {
      _context.state = FlutterState();
    }
  }
}

class FlutterState extends _State {
  @override
  void feed(String line) {
    if (isCommentOrBlankLine(line)) {
      return;
    }
    if (line.startsWith('${' ' * _defaultYamlIndent}plugin')) {
      _context.state = PluginState();
    } else {
      _context.state = InitialState();
    }
  }
}

class PluginState extends _State {
  @override
  void feed(String line) {
    if (isCommentOrBlankLine(line)) {
      return;
    }
    if (line.startsWith('${' ' * _defaultYamlIndent * 2}platforms')) {
      _context.state = PlatformState();
    } else {
      _context.state = InitialState();
    }
  }
}

class PlatformState extends _State {
  @override
  void feed(String line) {
    return;
  }
}
