
import 'package:hello_platform_interface/hello_platform_interface.dart';

class Hello {
  Future<String> get helloString async =>
    await HelloPlatform.instance.makeHelloString();
}