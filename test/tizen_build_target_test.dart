// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
import 'dart:io';

import 'package:flutter_tizen/tizen_project.dart';
import 'package:flutter_tizen/tizen_sdk.dart';
import 'package:flutter_tizen/tizen_tpk.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'package:mockito/mockito.dart';

import '../flutter/packages/flutter_tools/test/src/android_common.dart';
import '../flutter/packages/flutter_tools/test/src/common.dart';
import '../flutter/packages/flutter_tools/test/src/context.dart';

import 'common.dart';
import 'fakes.dart';

// To run the tests, you must set two environment variables on the running system
// For example, in Linux,
// FLUTTER_ROOT: path to the flutter-tizen/flutter direcotry
// TIZEN_SDK: path to the tizen-studio directory
void main() {
  Cache.disableLocking();

  Directory tempDir;
  FakeFlutterBuildSystem fakeFlutterBuildSystem;
  MockTizenSdk mockTizenSdk;

  setUp(() {
    tempDir = globals.fs.systemTempDirectory
        .createTempSync('flutter_tizen_packages_build_cache.');

    fakeFlutterBuildSystem = FakeFlutterBuildSystem(
      fileSystem: globals.fs,
      platform: globals.platform,
      logger: BufferLogger.test(),
    );
  });

  tearDown(() {
    tryToDelete(tempDir);
  });

  testUsingTizenContext(
    'fake targets work',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      final Directory tizenDirectory =
          tempDir.childDirectory('flutter_project').childDirectory('tizen');
      expect(tizenDirectory.existsSync(), isTrue);

      await runPackagesCommand(flutterProject, 'get');
      await runBuildTpkCommand(flutterProject,
          arguments: <String>['--release']);

      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(
          fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun, true);
      expect(fakeFlutterBuildSystem.get<FakeTizenPlugins>().didBuildRun, true);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  testUsingTizenContext(
    'does not rebuild if nothing has changed',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      final Directory tizenDirectory =
          tempDir.childDirectory('flutter_project').childDirectory('tizen');
      expect(tizenDirectory.existsSync(), isTrue);

      await runPackagesCommand(flutterProject, 'get');
      await runBuildTpkCommand(flutterProject);

      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(
          fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun, true);

      // target should not be rebuilt if nothing has changed
      await runBuildTpkCommand(flutterProject);
      expect(fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun,
          false);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  testUsingTizenContext(
    'removing tpk rebuilds',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      await runPackagesCommand(flutterProject, 'get');
      await runBuildTpkCommand(flutterProject);

      // erase tpk
      final TizenProject tizenProject =
          TizenProject.fromFlutter(FlutterProject.fromPath(flutterProject));
      tizenProject.editableDirectory.parent
          .childDirectory('build')
          .childDirectory('tizen')
          .childFile(tizenProject.outputTpkName)
          .deleteSync(recursive: true);

      // target should be rebuilt
      await runBuildTpkCommand(flutterProject);
      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  testUsingTizenContext(
    'alterting build modes rebuilds',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      await runPackagesCommand(flutterProject, 'get');
      // calculate debug and release tpk file size
      final FakeTizenProject tizenProject =
          FakeTizenProject.fromFlutter(FlutterProject.fromPath(flutterProject));

      await runBuildTpkCommand(flutterProject,
          arguments: <String>['--release']);
      final int releaseTpkSize = tizenProject.tpkSize;

      await runBuildTpkCommand(flutterProject, arguments: <String>['--debug']);
      final int debugTpkSize = tizenProject.tpkSize;

      // no rebuild
      await runBuildTpkCommand(flutterProject, arguments: <String>['--debug']);
      expect(
          fakeFlutterBuildSystem.get<FakeDebugDotnetTpk>().didBuildRun, false);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);
      expect(tizenProject.tpkSize, debugTpkSize);

      // target should be rebuilt
      await runBuildTpkCommand(flutterProject,
          arguments: <String>['--release']);
      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(
          fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun, true);
      expect(tizenProject.tpkSize, releaseTpkSize);

      // should not rebuild
      await runBuildTpkCommand(flutterProject,
          arguments: <String>['--release']);
      expect(fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun,
          false);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);
      expect(tizenProject.tpkSize, releaseTpkSize);

      // rebuild
      await runBuildTpkCommand(flutterProject, arguments: <String>['--debug']);
      expect(
          fakeFlutterBuildSystem.get<FakeDebugDotnetTpk>().didBuildRun, true);
      expect(
          fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun, true);
      expect(tizenProject.tpkSize, debugTpkSize);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  testUsingTizenContext(
    'changing security profile rebuilds',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      mockTizenSdk = MockTizenSdk();
      when(mockTizenSdk.tizenCli).thenReturn(
        getTizenSdkDir()
            .childDirectory('tools')
            .childDirectory('ide')
            .childDirectory('bin')
            .childFile(globals.platform.isWindows ? 'tizen.bat' : 'tizen'),
      );

      final File profile1Author =
          tempDir.childDirectory('profile1').childFile('author.p12')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile1_author');
      final File profile1AuthorPwd =
          tempDir.childDirectory('profile1').childFile('author.pwd')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile1_author_pwd');
      final File profile1Distributor =
          tempDir.childDirectory('profile1').childFile('distributor.p12')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile1_distributor');
      final File profile1DistributorPwd =
          tempDir.childDirectory('profile1').childFile('distributor.pwd')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile1_distributor_pwd');

      final File profile2Author =
          tempDir.childDirectory('profile2').childFile('author.p12')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile2_author');
      final File profile2AuthorPwd =
          tempDir.childDirectory('profile2').childFile('author.pwd')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile2_author_pwd');
      final File profile2Distributor =
          tempDir.childDirectory('profile2').childFile('distributor.p12')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile2_distributor');
      final File profile2DistributorPwd =
          tempDir.childDirectory('profile2').childFile('distributor.pwd')
            ..createSync(recursive: true)
            ..writeAsStringSync('profile2_distributor_pwd');

      final File certificatesXml = tempDir.childFile('profiles.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
<?xml version="1.0 encoding="UTF-8" standalone="no"?>
<profiles active="profile1" version="3.1">
<profile name="profile1">
<profileitem ca="" distributor="0" key="${profile1Author.path}" password="${profile1AuthorPwd.path}"/>
<profileitem ca="" distributor="1" key="${profile1Distributor.path}" password="${profile1DistributorPwd.path}"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
<profile name="profile2">
<profileitem ca="tizen-developer-ca.cer" distributor="0" key="${profile2Author.path}" password="${profile2AuthorPwd.path}"/>
<profileitem ca="tizen-distributor-ca.cer" distributor="1" key="${profile2Distributor.path}" password="${profile2DistributorPwd.path}"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
</profiles>
''');

      when(mockTizenSdk.securityProfiles)
          .thenReturn(SecurityProfiles.parseFromXml(certificatesXml));
      when(mockTizenSdk.securityProfilesFile).thenReturn(certificatesXml);

      await runPackagesCommand(flutterProject, 'get');
      await runBuildTpkCommand(flutterProject);

      await runBuildTpkCommand(flutterProject);

      expect(fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun,
          false);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);

      // change active profile to profile2
      certificatesXml.writeAsStringSync('''
<?xml version="1.0 encoding="UTF-8" standalone="no"?>
<profiles active="profile2" version="3.1">
<profile name="profile1">
<profileitem ca="" distributor="0" key="${profile1Author.path}" password="${profile1AuthorPwd.path}"/>
<profileitem ca="" distributor="1" key="${profile1Distributor.path}" password="${profile1DistributorPwd.path}"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
<profile name="profile2">
<profileitem ca="tizen-developer-ca.cer" distributor="0" key="${profile2Author.path}" password="${profile2AuthorPwd.path}"/>
<profileitem ca="tizen-distributor-ca.cer" distributor="1" key="${profile2Distributor.path}" password="${profile2DistributorPwd.path}"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
</profiles>
''');

      await runBuildTpkCommand(flutterProject);

      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun,
          false);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
      TizenSdk: () => mockTizenSdk,
    },
  );

  testUsingTizenContext(
    'chaning app source rebuilds',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      await runPackagesCommand(flutterProject, 'get');
      await runBuildTpkCommand(flutterProject);

      // change app source
      FlutterProject.fromPath(flutterProject)
          .directory
          .childDirectory('lib')
          .childFile('main.dart')
          .writeAsStringSync('''
void main(){
  print('changed main');
}    
''');

      await runBuildTpkCommand(flutterProject);

      expect(
          fakeFlutterBuildSystem.get<FakeReleaseDotnetTpk>().didBuildRun, true);
      expect(
          fakeFlutterBuildSystem.get<FakeTizenAssetBundle>().didBuildRun, true);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );

  // Plugins are always rebuilt because [TizenPlugins] depend on .flutter-plugins.dependencies
  // which contains a timestamp that is always rewritten before build.
  // (TODO: HakkyuKim) Actually build plugin
  testUsingTizenContext(
    'TizenPlugins always rebuild',
    () async {
      final String flutterProject = await createTizenProject(
        tempDir,
        arguments: <String>['--no-pub'],
      );

      await runPackagesCommand(flutterProject, 'get');

      await runBuildTpkCommand(flutterProject);
      expect(fakeFlutterBuildSystem.get<FakeTizenPlugins>().didBuildRun, true);
      await runBuildTpkCommand(flutterProject);
      expect(fakeFlutterBuildSystem.get<FakeTizenPlugins>().didBuildRun, true);
    },
    overrides: <Type, Generator>{
      BuildSystem: () => fakeFlutterBuildSystem,
      FlutterProjectFactory: () => FakeFlutterProjectFactory(tempDir),
    },
  );
}

class MockTizenSdk extends Mock implements TizenSdk {}
