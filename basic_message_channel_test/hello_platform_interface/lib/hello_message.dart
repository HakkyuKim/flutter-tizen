import 'package:flutter/services.dart';

const String _channelName = 'basicGetHelloMessage';

class HelloApi {
  Future<String> makeHelloString() async {
    const BasicMessageChannel<Object?> channel =
        BasicMessageChannel<Object?>(_channelName, StandardMessageCodec());
    final Map<Object?, Object?>? replyMap = await channel.send(null) as Map<Object?, Object?>?;
    if (replyMap == null) {
      throw PlatformException(code: 'return_null');
    } else if (replyMap['error'] != null) {
      throw PlatformException(code: 'error');
    } else if(replyMap['result'] is! String){
      throw PlatformException(code: "type_cast");
    }
    return replyMap['result'] as String;
  }
}
