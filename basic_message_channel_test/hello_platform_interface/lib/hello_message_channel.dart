import 'hello_platform_interface.dart';
import 'hello_message.dart';

class HelloMessageChannel extends HelloPlatform {
  final HelloApi _api = HelloApi();

  @override
  Future<String> makeHelloString()async {
    return await _api.makeHelloString();
  }
}