// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'package:file/file.dart';
import 'package:meta/meta.dart';

import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';

import 'package:flutter_tizen/tizen_build_target.dart';
import 'package:flutter_tizen/tizen_project.dart';
import 'package:flutter_tizen/tizen_builder.dart';

mixin BuildObserver on Target {
  int buildCalls = 0;

  bool get didBuildRun => buildCalls > 0;

  @override
  Future<void> build(Environment environment) async {
    buildCalls += 1;
    await super.build(environment);
  }

  List<Target> fakeTargets = <Target>[];
}

class FakeReleaseDotnetTpk extends ReleaseDotnetTpk with BuildObserver {
  FakeReleaseDotnetTpk(FlutterProject project, TizenBuildInfo buildInfo)
      : super(project, buildInfo) {
    fakeTargets.add(FakeTizenAssetBundle(project));
    fakeTargets.add(FakeTizenPlugins(project, buildInfo));
  }

  @override
  String get name => 'fake_release_tpk';

  @override
  List<Target> get dependencies => <Target>[
        TizenAotElf(buildInfo.targetArchs),
        ...fakeTargets,
      ];
}

class FakeDebugDotnetTpk extends DebugDotnetTpk with BuildObserver {
  FakeDebugDotnetTpk(FlutterProject project, TizenBuildInfo buildInfo)
      : super(project, buildInfo) {
    fakeTargets.add(FakeTizenAssetBundle(project));
    fakeTargets.add(FakeTizenPlugins(project, buildInfo));
  }

  @override
  String get name => 'fake_debug_tpk';

  @override
  List<Target> get dependencies => <Target>[
        ...fakeTargets,
      ];
}

class FakeTizenAssetBundle extends TizenAssetBundle with BuildObserver {
  FakeTizenAssetBundle(FlutterProject project) : super(project);

  @override
  String get name => 'fake_tizen_assets';
}

class FakeTizenPlugins extends TizenPlugins with BuildObserver {
  FakeTizenPlugins(FlutterProject project, TizenBuildInfo buildInfo)
      : super(project, buildInfo);

  @override
  String get name => 'fake_tizen_plugins';
}

// Snatches targets from the [FlutterBuildSystem] and replace
// them with fake targets. Used for testing.
class FakeFlutterBuildSystem extends FlutterBuildSystem {
  FakeFlutterBuildSystem({
    @required FileSystem fileSystem,
    @required Platform platform,
    @required Logger logger,
  }) : super(
          fileSystem: fileSystem,
          platform: platform,
          logger: logger,
        );

  void _findTarget<T>(Target target, List<Target> targets) {
    if (target.runtimeType == T) {
      targets.add(target);
    }
    for (final Target dependentTarget in target.dependencies) {
      _findTarget<T>(dependentTarget, targets);
    }
  }

  Target _root;

  T get<T>() {
    if (_root == null) {
      throw Exception('Build was not run');
    }
    final List<Target> targets = <Target>[];
    _findTarget<T>(_root, targets);
    if (targets.length > 1) {
      throw Exception('There are more than one targets of type $T');
    }
    if (targets.isEmpty) {
      throw Exception('There is no target of type $T');
    }
    return targets.first as T;
  }

  @override
  Future<BuildResult> build(
      covariant TizenPackager target, Environment environment,
      {BuildSystemConfig buildSystemConfig = const BuildSystemConfig()}) async {
    BuildResult buildResult;

    if (target is DotnetTpk) {
      final DotnetTpk fakeDotnetTpk = (target is ReleaseDotnetTpk)
          ? FakeReleaseDotnetTpk(target.project, target.buildInfo)
          : FakeDebugDotnetTpk(target.project, target.buildInfo);

      _root = fakeDotnetTpk;

      buildResult = await super.build(
        fakeDotnetTpk,
        environment,
        buildSystemConfig: buildSystemConfig,
      );

      await fakeDotnetTpk.package(environment);
    } else {
      throw Exception(
          '${target.runtimeType} currently has no fake classes, and should not be used in testing.');
    }

    return buildResult;
  }
}

// This class is made for quick testing and is not affected by
// [Environment]. Use with caution.
class FakeTizenProject extends TizenProject {
  FakeTizenProject.fromFlutter(FlutterProject parent)
      : super.fromFlutter(parent);

  Directory get outputDir =>
      editableDirectory.parent.childDirectory('build').childDirectory('tizen');

  int get tpkSize =>
      outputDir.childFile(outputTpkName).readAsBytesSync().length;
}
