import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'hello_message_channel.dart';

abstract class HelloPlatform extends PlatformInterface{
  HelloPlatform() : super(token: _token);

  static final Object _token = Object();

  static HelloPlatform _instance = HelloMessageChannel();

  static HelloPlatform get instance => _instance;

  static set instance(HelloPlatform instance){
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // make hello string
  Future<String> makeHelloString(){
    throw UnimplementedError('makeHelloString() has not been implemented.');
  }
}