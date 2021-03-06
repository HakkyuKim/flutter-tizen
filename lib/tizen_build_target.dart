// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:file/file.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/depfile.dart';
import 'package:flutter_tools/src/build_system/targets/assets.dart';
import 'package:flutter_tools/src/build_system/targets/icon_tree_shaker.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart';
import 'package:flutter_tools/src/build_system/source.dart';
import 'package:flutter_tools/src/build_system/targets/android.dart';
import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import 'tizen_artifacts.dart';
import 'tizen_builder.dart';
import 'tizen_plugins.dart';
import 'tizen_project.dart';
import 'tizen_sdk.dart';
import 'tizen_tpk.dart';

/// Prepares the pre-built flutter bundle.
///
/// Source: [AndroidAssetBundle] in `android.dart`
abstract class TizenAssetBundle extends Target {
  const TizenAssetBundle();

  @override
  String get name => 'tizen_asset_bundle';

  @override
  List<Source> get inputs => const <Source>[
        Source.pattern('{BUILD_DIR}/app.dill'),
        ...IconTreeShaker.inputs,
      ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => <String>[
        'flutter_assets.d',
      ];

  @override
  List<Target> get dependencies => const <Target>[
        KernelSnapshot(),
      ];

  @override
  Future<void> build(Environment environment) async {
    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, name);
    }
    final BuildMode buildMode =
        getBuildModeForName(environment.defines[kBuildMode]);
    final Directory outputDirectory = environment.outputDir
        .childDirectory('flutter_assets')
          ..createSync(recursive: true);

    // Only copy the prebuilt runtimes and kernel blob in debug mode.
    if (buildMode == BuildMode.debug) {
      final String vmSnapshotData = environment.artifacts
          .getArtifactPath(Artifact.vmSnapshotData, mode: BuildMode.debug);
      final String isolateSnapshotData = environment.artifacts
          .getArtifactPath(Artifact.isolateSnapshotData, mode: BuildMode.debug);
      environment.buildDir
          .childFile('app.dill')
          .copySync(outputDirectory.childFile('kernel_blob.bin').path);
      environment.fileSystem
          .file(vmSnapshotData)
          .copySync(outputDirectory.childFile('vm_snapshot_data').path);
      environment.fileSystem
          .file(isolateSnapshotData)
          .copySync(outputDirectory.childFile('isolate_snapshot_data').path);
    }
    final Depfile assetDepfile = await copyAssets(
      environment,
      outputDirectory,
      targetPlatform: null, // corresponds to flutter-tester
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      assetDepfile,
      environment.buildDir.childFile('flutter_assets.d'),
    );
  }
}

/// Source: [DebugAndroidApplication] in `android.dart`
class DebugTizenApplication extends TizenAssetBundle {
  DebugTizenApplication(this.buildInfo);

  final TizenBuildInfo buildInfo;

  @override
  String get name => 'debug_tizen_application';

  @override
  List<Source> get inputs => <Source>[
        ...super.inputs,
        const Source.artifact(Artifact.vmSnapshotData, mode: BuildMode.debug),
        const Source.artifact(Artifact.isolateSnapshotData,
            mode: BuildMode.debug),
      ];

  @override
  List<Source> get outputs => <Source>[
        ...super.outputs,
        const Source.pattern('{OUTPUT_DIR}/flutter_assets/vm_snapshot_data'),
        const Source.pattern(
            '{OUTPUT_DIR}/flutter_assets/isolate_snapshot_data'),
        const Source.pattern('{OUTPUT_DIR}/flutter_assets/kernel_blob.bin'),
      ];

  @override
  List<Target> get dependencies => <Target>[
        ...super.dependencies,
        TizenPlugins(buildInfo),
      ];
}

/// See: [ReleaseAndroidApplication] in `android.dart`
class ReleaseTizenApplication extends TizenAssetBundle {
  ReleaseTizenApplication(this.buildInfo);

  final TizenBuildInfo buildInfo;

  @override
  String get name => 'release_tizen_application';

  @override
  List<Target> get dependencies => <Target>[
        ...super.dependencies,
        TizenAotElf(),
        TizenPlugins(buildInfo),
      ];
}

/// Compiles Tizen native plugins into a single shared object.
class TizenPlugins extends Target {
  TizenPlugins(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  @override
  String get name => 'tizen_plugins';

  @override
  List<Source> get inputs => const <Source>[
        Source.pattern('{FLUTTER_ROOT}/../lib/tizen_build_target.dart'),
        Source.pattern('{PROJECT_DIR}/.packages'),
      ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => <String>[
        'tizen_plugins.d',
      ];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<void> build(Environment environment) async {
    final List<File> inputs = <File>[];
    final List<File> outputs = <File>[];
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );

    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Create a dummy project in the build directory.
    final Directory rootDir = environment.buildDir
        .childDirectory('tizen_plugins')
          ..createSync(recursive: true);
    final String profile =
        TizenManifest.parseFromXml(tizenProject.manifestFile)?.profile;
    inputs.add(tizenProject.manifestFile);

    rootDir.childFile('project_def.prop').writeAsStringSync('''
APPNAME = flutter_plugins
type = sharedLib
profile = $profile

USER_CPP_DEFS = TIZEN_DEPRECATION DEPRECATION_WARNING FLUTTER_PLUGIN_IMPL
USER_CPPFLAGS_MISC = -c -fmessage-length=0
USER_LFLAGS = -Wl,-rpath='\$\$ORIGIN'
USER_LIB_DIRS = lib
''');

    // Check if there's anything to build.
    final List<TizenPlugin> nativePlugins =
        await findTizenPlugins(project, nativeOnly: true);
    if (nativePlugins.isEmpty) {
      rootDir.deleteSync(recursive: true);

      depfileService.writeToFile(
        Depfile(inputs, outputs),
        environment.buildDir.childFile('tizen_plugins.d'),
      );
      return;
    }

    // Prepare for build.
    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final Directory buildDir = rootDir.childDirectory(buildConfig);
    final Directory includeDir = rootDir.childDirectory('include')
      ..createSync(recursive: true);
    final Directory libDir = rootDir.childDirectory('lib')
      ..createSync(recursive: true);

    final List<String> userIncludes = <String>[];
    final List<String> userSources = <String>[];
    final List<String> userLibs = <String>[];

    for (final TizenPlugin plugin in nativePlugins) {
      inputs.add(plugin.projectFile);

      // TODO(swift-kim): Currently only checks for USER_INC_DIRS, USER_SRCS,
      // and USER_LIBS. More properties may be parsed in the future.
      userIncludes.addAll(plugin.getPropertyAsAbsolutePaths('USER_INC_DIRS'));
      userSources.addAll(plugin.getPropertyAsAbsolutePaths('USER_SRCS'));

      final Directory headerDir = plugin.directory.childDirectory('inc');
      if (headerDir.existsSync()) {
        headerDir
            .listSync(recursive: true)
            .whereType<File>()
            .forEach(inputs.add);
      }
      final Directory sourceDir = plugin.directory.childDirectory('src');
      if (sourceDir.existsSync()) {
        sourceDir
            .listSync(recursive: true)
            .whereType<File>()
            .forEach(inputs.add);
      }

      for (final String libName in plugin.getProperty('USER_LIBS').split(' ')) {
        final File libFile = plugin.directory
            .childDirectory('lib')
            .childDirectory(getTizenBuildArch(buildInfo.targetArch))
            .childFile('lib$libName.so');
        if (libFile.existsSync()) {
          userLibs.add(libName);
          libFile.copySync(libDir.childFile(libFile.basename).path);

          inputs.add(libFile);
          outputs.add(libDir.childFile(libFile.basename));
        }
      }

      // The plugin header is used when building native apps.
      final File header = headerDir.childFile(plugin.fileName);
      header.copySync(includeDir.childFile(header.basename).path);
      outputs.add(includeDir.childFile(header.basename));
    }

    final Directory engineDir =
        tizenArtifacts.getEngineDirectory(buildInfo.targetArch, buildMode);
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    inputs.add(embedder);

    final Directory commonDir = engineDir.parent.childDirectory('common');
    final Directory clientWrapperDir =
        commonDir.childDirectory('cpp_client_wrapper');
    final Directory publicDir = commonDir.childDirectory('public');
    clientWrapperDir
        .listSync(recursive: true)
        .whereType<File>()
        .forEach(inputs.add);
    publicDir.listSync(recursive: true).whereType<File>().forEach(inputs.add);

    userSources.add(clientWrapperDir.childFile('*.cc').path);

    final Map<String, String> variables = <String, String>{
      'PATH': getDefaultPathVariable(),
      'USER_SRCS': userSources.map(getUnixPath).join(' '),
    };
    final List<String> extraOptions = <String>[
      '-lflutter_tizen_${buildInfo.deviceProfile}',
      '-L"${getUnixPath(engineDir.path)}"',
      '-fvisibility=hidden',
      '-std=c++17',
      '-I"${getUnixPath(clientWrapperDir.childDirectory('include').path)}"',
      '-I"${getUnixPath(publicDir.path)}"',
      ...userIncludes.map(getUnixPath).map((String path) => '-I"$path"'),
      ...userLibs.map((String lib) => '-l$lib'),
      '-L"${getUnixPath(libDir.path)}"',
      '-D${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
    ];

    assert(tizenSdk != null);
    final Rootstrap rootstrap = tizenSdk.getFlutterRootstrap(
        profile: profile, arch: buildInfo.targetArch);
    inputs.add(rootstrap.manifestFile);

    // Run the native build.
    if (buildDir.existsSync()) {
      buildDir.deleteSync(recursive: true);
    }
    final RunResult result = await _processUtils.run(<String>[
      tizenSdk.tizenCli.path,
      'build-native',
      '-a',
      getTizenCliArch(buildInfo.targetArch),
      '-C',
      buildConfig,
      '-c',
      tizenSdk.defaultNativeCompiler,
      '-r',
      rootstrap.id,
      '-e',
      extraOptions.join(' '),
      '--',
      rootDir.path,
    ], environment: variables);
    if (result.exitCode != 0) {
      throwToolExit('Failed to build Flutter plugins:\n$result');
    }

    final File outputLib = buildDir.childFile('libflutter_plugins.so');
    if (!outputLib.existsSync()) {
      throwToolExit(
        'Build succeeded but the file ${outputLib.path} is not found:\n'
        '${result.stdout}',
      );
    }
    outputs.add(outputLib);

    depfileService.writeToFile(
      Depfile(inputs, outputs),
      environment.buildDir.childFile('tizen_plugins.d'),
    );
  }
}

class DotnetTpk {
  DotnetTpk(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Clean up the intermediate and output directories.
    final Directory ephemeralDir = tizenProject.ephemeralDirectory;
    if (ephemeralDir.existsSync()) {
      ephemeralDir.deleteSync(recursive: true);
    }
    final Directory resDir = ephemeralDir.childDirectory('res')
      ..createSync(recursive: true);
    final Directory libDir = ephemeralDir.childDirectory('lib')
      ..createSync(recursive: true);

    final Directory outputDir = environment.outputDir.childDirectory('tpk');
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
    outputDir.createSync(recursive: true);

    // Copy necessary files.
    final Directory flutterAssetsDir = resDir.childDirectory('flutter_assets');
    globals.fsUtils.copyDirectorySync(
      environment.outputDir.childDirectory('flutter_assets'),
      flutterAssetsDir,
    );

    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final Directory engineDir =
        tizenArtifacts.getEngineDirectory(buildInfo.targetArch, buildMode);
    final File engineBinary = engineDir.childFile('libflutter_engine.so');
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    final File icuData = engineDir.parent
        .childDirectory('common')
        .childDirectory('icu')
        .childFile('icudtl.dat');

    engineBinary.copySync(libDir.childFile(engineBinary.basename).path);
    // The embedder so name is statically defined in C# code and cannot be
    // provided at runtime, so the file name must be a constant.
    embedder.copySync(libDir.childFile('libflutter_tizen.so').path);
    icuData.copySync(resDir.childFile(icuData.basename).path);

    if (buildMode.isPrecompiled) {
      final File aotSharedLib = environment.buildDir.childFile('app.so');
      aotSharedLib.copySync(libDir.childFile('libapp.so').path);
    }

    final Directory pluginsDir =
        environment.buildDir.childDirectory('tizen_plugins');
    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final File pluginsLib = pluginsDir
        .childDirectory(buildConfig)
        .childFile('libflutter_plugins.so');
    if (pluginsLib.existsSync()) {
      pluginsLib.copySync(libDir.childFile(pluginsLib.basename).path);
    }
    final Directory pluginsUserLibDir = pluginsDir.childDirectory('lib');
    if (pluginsUserLibDir.existsSync()) {
      pluginsUserLibDir.listSync().whereType<File>().forEach(
          (File lib) => lib.copySync(libDir.childFile(lib.basename).path));
    }

    // TODO(swift-kim): This property is used by projects created before May
    // 2021. Keep the value up to date until majority of projects are migrated
    // to use ProjectReference.
    const String embeddingVersion = '1.8.0';
    final bool migrated = !tizenProject.projectFile
        .readAsStringSync()
        .contains(r'$(FlutterEmbeddingVersion)');
    if (!migrated) {
      final Function relative = environment.fileSystem.path.relative;
      environment.logger.printStatus(
        'The use of PackageReference in ${tizenProject.projectFile.basename} is deprecated. '
        'To migrate your project, run:\n'
        '  rm ${relative(tizenProject.projectFile.path)}\n'
        '  flutter-tizen create ${relative(project.directory.path)}',
        color: TerminalColor.yellow,
      );
      environment.logger.printStatus('');
    }

    // Run the .NET build.
    if (dotnetCli == null) {
      throwToolExit(
        'Unable to locate .NET CLI executable.\n'
        'Install the latest .NET SDK from: https://dotnet.microsoft.com/download',
      );
    }
    RunResult result = await _processUtils.run(<String>[
      dotnetCli.path,
      'build',
      '-c',
      'Release',
      '-o',
      '${outputDir.path}/', // The trailing '/' is needed.
      '/p:FlutterEmbeddingVersion=$embeddingVersion',
      tizenProject.editableDirectory.path,
    ]);
    if (result.exitCode != 0) {
      throwToolExit('Failed to build .NET application:\n$result');
    }

    final File outputTpk = outputDir.childFile(tizenProject.outputTpkName);
    if (!outputTpk.existsSync()) {
      throwToolExit(
          'Build succeeded but the expected TPK not found:\n${result.stdout}');
    }

    // build-task-tizen signs the output TPK with a dummy profile by default.
    // We need to re-generate the TPK by signing with a correct profile.
    String securityProfile = buildInfo.securityProfile;
    assert(tizenSdk != null);

    if (securityProfile != null) {
      if (tizenSdk.securityProfiles == null ||
          !tizenSdk.securityProfiles.names.contains(securityProfile)) {
        throwToolExit('The profile $securityProfile does not exist.');
      }
    }
    securityProfile ??= tizenSdk.securityProfiles?.active?.name;

    if (securityProfile != null) {
      environment.logger
          .printStatus('The $securityProfile profile is used for signing.');
      result = await _processUtils.run(<String>[
        tizenSdk.tizenCli.path,
        'package',
        '-t',
        'tpk',
        '-s',
        securityProfile,
        '--',
        outputTpk.path,
      ]);
      if (result.exitCode != 0) {
        throwToolExit('Failed to sign the TPK:\n$result');
      }
    } else {
      environment.logger.printStatus(
        'The tpk has been signed with a default certificate. You can create one using Certificate Manager.\n'
        'https://github.com/flutter-tizen/flutter-tizen/blob/master/doc/install-tizen-sdk.md#create-a-tizen-certificate',
        color: TerminalColor.yellow,
      );
    }
  }
}

/// Generates an AOT snapshot (app.so) of the Dart code.
///
/// Source: [AotElfRelease] in `common.dart`
class TizenAotElf extends AotElfBase {
  TizenAotElf();

  @override
  String get name => 'tizen_aot_elf';

  @override
  List<Source> get inputs => <Source>[
        const Source.pattern('{BUILD_DIR}/app.dill'),
        const Source.artifact(Artifact.engineDartBinary),
        const Source.artifact(Artifact.skyEnginePath),
        // Any type of gen_snapshot is applicable here because engine artifacts
        // are assumed to be updated at once, not one by one for each platform
        // or build mode.
        const Source.artifact(Artifact.genSnapshot, mode: BuildMode.release),
      ];

  @override
  List<Source> get outputs => const <Source>[
        Source.pattern('{BUILD_DIR}/app.so'),
      ];

  @override
  List<Target> get dependencies => const <Target>[
        KernelSnapshot(),
      ];
}

class NativeTpk {
  NativeTpk(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Clean up the intermediate and output directories.
    final Directory tizenDir = tizenProject.editableDirectory;
    final Directory resDir = tizenDir.childDirectory('res');
    if (resDir.existsSync()) {
      resDir.deleteSync(recursive: true);
    }
    resDir.createSync(recursive: true);
    final Directory libDir = tizenDir.childDirectory('lib');
    if (libDir.existsSync()) {
      libDir.deleteSync(recursive: true);
    }
    libDir.createSync(recursive: true);

    final Directory outputDir = environment.outputDir.childDirectory('tpk');
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
    outputDir.createSync(recursive: true);

    // Copy necessary files.
    final Directory flutterAssetsDir = resDir.childDirectory('flutter_assets');
    globals.fsUtils.copyDirectorySync(
      environment.outputDir.childDirectory('flutter_assets'),
      flutterAssetsDir,
    );

    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final Directory engineDir =
        tizenArtifacts.getEngineDirectory(buildInfo.targetArch, buildMode);
    final File engineBinary = engineDir.childFile('libflutter_engine.so');
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    final File icuData = engineDir.parent
        .childDirectory('common')
        .childDirectory('icu')
        .childFile('icudtl.dat');

    engineBinary.copySync(libDir.childFile(engineBinary.basename).path);
    embedder.copySync(libDir.childFile(embedder.basename).path);
    icuData.copySync(resDir.childFile(icuData.basename).path);

    if (buildMode.isPrecompiled) {
      final File aotSharedLib = environment.buildDir.childFile('app.so');
      aotSharedLib.copySync(libDir.childFile('libapp.so').path);
    }

    final Directory pluginsDir =
        environment.buildDir.childDirectory('tizen_plugins');
    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final File pluginsLib = pluginsDir
        .childDirectory(buildConfig)
        .childFile('libflutter_plugins.so');
    if (pluginsLib.existsSync()) {
      pluginsLib.copySync(libDir.childFile(pluginsLib.basename).path);
    }
    final Directory pluginsUserLibDir = pluginsDir.childDirectory('lib');
    if (pluginsUserLibDir.existsSync()) {
      pluginsUserLibDir.listSync().whereType<File>().forEach(
          (File lib) => lib.copySync(libDir.childFile(lib.basename).path));
    }

    // Prepare for build.
    final Directory buildDir = tizenDir.childDirectory(buildConfig);
    final Directory embeddingDir = environment.fileSystem
        .directory(Cache.flutterRoot)
        .parent
        .childDirectory('embedding')
        .childDirectory('cpp');

    final List<String> userIncludes = <String>[
      embeddingDir.childDirectory('include').path,
      pluginsDir.childDirectory('include').path,
    ];
    final List<String> userSources = <String>[
      embeddingDir.childFile('*.cc').path,
    ];

    final Directory commonDir = engineDir.parent.childDirectory('common');
    final Directory clientWrapperDir =
        commonDir.childDirectory('cpp_client_wrapper');
    final Directory publicDir = commonDir.childDirectory('public');

    userSources.add(clientWrapperDir.childFile('*.cc').path);

    final Map<String, String> variables = <String, String>{
      'PATH': getDefaultPathVariable(),
      'USER_SRCS': userSources.map(getUnixPath).join(' '),
    };
    final List<String> extraOptions = <String>[
      '-lflutter_tizen_${buildInfo.deviceProfile}',
      '-L"${getUnixPath(libDir.path)}"',
      '-std=c++17',
      '-I"${getUnixPath(clientWrapperDir.childDirectory('include').path)}"',
      '-I"${getUnixPath(publicDir.path)}"',
      ...userIncludes.map(getUnixPath).map((String path) => '-I"$path"'),
      if (pluginsLib.existsSync()) '-lflutter_plugins',
      '-D${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
      '-Wl,-unresolved-symbols=ignore-in-shared-libs',
    ];

    assert(tizenSdk != null);
    final String profile =
        TizenManifest.parseFromXml(tizenProject.manifestFile)?.profile;
    final Rootstrap rootstrap = tizenSdk.getFlutterRootstrap(
        profile: profile, arch: buildInfo.targetArch);

    // Run the native build.
    if (buildDir.existsSync()) {
      buildDir.deleteSync(recursive: true);
    }
    RunResult result = await _processUtils.run(<String>[
      tizenSdk.tizenCli.path,
      'build-native',
      '-a',
      getTizenCliArch(buildInfo.targetArch),
      '-C',
      buildConfig,
      '-c',
      tizenSdk.defaultNativeCompiler,
      '-r',
      rootstrap.id,
      '-e',
      extraOptions.join(' '),
      '--',
      tizenDir.path,
    ], environment: variables);
    if (result.exitCode != 0) {
      throwToolExit('Failed to build native application:\n$result');
    }

    // The output tpk is signed with an active profile unless otherwise
    // specified.
    String securityProfile = buildInfo.securityProfile;
    if (securityProfile != null) {
      if (tizenSdk.securityProfiles == null ||
          !tizenSdk.securityProfiles.names.contains(securityProfile)) {
        throwToolExit('The profile $securityProfile does not exist.');
      }
    }
    securityProfile ??= tizenSdk.securityProfiles?.active?.name;

    if (securityProfile != null) {
      environment.logger
          .printStatus('The $securityProfile profile is used for signing.');
    }
    result = await _processUtils.run(<String>[
      tizenSdk.tizenCli.path,
      'package',
      '-t',
      'tpk',
      if (securityProfile != null) ...<String>['-s', securityProfile],
      '--',
      buildDir.path,
    ]);
    if (result.exitCode != 0) {
      throwToolExit('Failed to generate TPK:\n$result');
    }

    final String tpkArch = buildInfo.targetArch
        .replaceFirst('arm64', 'aarch64')
        .replaceFirst('x86', 'i586');
    final File outputTpk = buildDir.childFile(
        tizenProject.outputTpkName.replaceFirst('.tpk', '-$tpkArch.tpk'));
    if (!outputTpk.existsSync()) {
      throwToolExit(
          'Build succeeded but the expected TPK not found:\n${result.stdout}');
    }

    // Copy and rename the output tpk.
    outputTpk.copySync(outputDir.childFile(tizenProject.outputTpkName).path);

    // Extract the contents of the tpk to support code size analysis.
    globals.os.unzip(outputTpk, outputDir.childDirectory('tpkroot'));
  }
}

/// Converts [targetArch] to an arch name that the Tizen CLI expects.
String getTizenCliArch(String targetArch) {
  switch (targetArch) {
    case 'arm64':
      return 'aarch64';
    default:
      return targetArch;
  }
}

/// Converts [targetArch] to an arch name that corresponds to the `BUILD_ARCH`
/// value used by the Tizen native builder.
String getTizenBuildArch(String targetArch) {
  switch (targetArch) {
    case 'arm':
      return 'armel';
    case 'arm64':
      return 'aarch64';
    case 'x86':
      return 'i586';
    default:
      return targetArch;
  }
}

/// On non-Windows, returns [path] unchanged.
///
/// On Windows, converts Windows-style [path] (e.g. 'C:\x\y') into Unix path
/// ('/c/x/y') and returns.
String getUnixPath(String path) {
  if (Platform.isWindows) {
    path = path.replaceAll(r'\', '/');
    if (path.startsWith(':', 1)) {
      path = '/${path[0].toLowerCase()}${path.substring(2)}';
    }
  }
  return path;
}

/// On non-Windows, returns the PATH environment variable.
///
/// On Windows, appends the msys2 executables directory to PATH and returns.
String getDefaultPathVariable() {
  final Map<String, String> variables = globals.platform.environment;
  String path = variables.containsKey('PATH') ? variables['PATH'] : '';
  if (Platform.isWindows) {
    assert(tizenSdk != null);
    final String msysUsrBin = tizenSdk.toolsDirectory
        .childDirectory('msys2')
        .childDirectory('usr')
        .childDirectory('bin')
        .path;
    path += ';$msysUsrBin';
  }
  return path;
}
