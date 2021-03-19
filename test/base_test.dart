import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/base/bot_detector.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:flutter_tools/src/dart/pub.dart';

import 'package:process/process.dart';

Future<void> main() async {
  const LocalFileSystem fileSystem = LocalFileSystem();
  final MemoryFileSystem memoryFileSystem = MemoryFileSystem();
  const Platform platform = LocalPlatform();
  const ProcessManager processManager = LocalProcessManager();
  final Logger logger = BufferLogger.test();
  const BotDetector botDetector = BotDetectorAlwaysNo();
  Cache.flutterRoot = platform.environment['FLUTTER_ROOT'];

  print(fileSystem.path.style);

  final Directory directory =
      fileSystem.currentDirectory.childDirectory('basic');
  directory.childFile('pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name : example  
''');

  final Pub pub = Pub(
      botDetector: botDetector,
      usage: Usage.test(),
      logger: logger,
      processManager: processManager,
      platform: platform,
      fileSystem: fileSystem);

  // context

  print(directory.path);
  await pub.get(context: PubContext.pubGet, directory: directory.path);

  // the root directory /
  print(memoryFileSystem.currentDirectory);

  print(memoryFileSystem.systemTempDirectory);

  print(platform.isLinux);
  print(platform.operatingSystem);
}

class BotDetectorAlwaysNo implements BotDetector {
  const BotDetectorAlwaysNo();

  @override
  Future<bool> get isRunningOnBot async => false;
}