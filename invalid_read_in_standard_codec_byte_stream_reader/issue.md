Silencing error message for BasicMessageChannel.send(null)

Hi, I was developing a platfrom plugin using the plugin APIs in `shell/platform/common/` and noticed that the embedder prints the following error message when dart code(from platform interface package) calls `BasicMessageChannel.send(null)`.

```
Invalid read in StandardCodecByteStreamReader
```

For example, in the [wakelock](https://github.com/creativecreatorormaybenot/wakelock) plugin written by @creativecreatorormaybenot, platform interface sends a null message to toggle the platform's wakelock switch.

As I understand, other platforms(Android, iOS, and Linux) use their own plugin APIs implemented with their (app framework) native language. Hence, to reproduce the symptom, you should check it on Windows. I've written a simple test app [here]().

In Android, the error message is not shown because null value is checked:

```java
// in shell/platform/android/io/flutter/plugin/common/StandardMessageCodec.java
@Override
public Object decodeMessage(ByteBuffer message) {
  if (message == null) {
    return null;
  }
  message.order(ByteOrder.nativeOrder());
  final Object value = readValue(message);
  if (message.hasRemaining()) {
    throw new IllegalArgumentException("Message corrupted");
  }
  return value;
}
```

I'm thinking of a patch that matches the Android's implemention, something like this:

```cpp
// in shell/platform/common/client_wrapper/standard_codec.cc
std::unique_ptr<EncodableValue> StandardMessageCodec::DecodeMessageInternal(
    const uint8_t* binary_message,
    size_t message_size) const {
+  if (!binary_message) {
+    return std::make_unique<EncodableValue>();
+  }
  ByteBufferStreamReader stream(binary_message, message_size);
  return std::make_unique<EncodableValue>(serializer_->ReadValue(&stream));
}
```

I want to check if this change makes sense and hear opinions from maintainers before sending a PR. Thanks.