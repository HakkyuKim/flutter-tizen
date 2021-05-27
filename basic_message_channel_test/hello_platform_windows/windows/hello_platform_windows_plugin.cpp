#include "include/hello_platform_windows/hello_platform_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/basic_message_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_message_codec.h>

#include <map>
#include <memory>
#include <sstream>

namespace {

class HelloPlatformWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  HelloPlatformWindowsPlugin();

  virtual ~HelloPlatformWindowsPlugin();
};

// static
void HelloPlatformWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::BasicMessageChannel<flutter::EncodableValue>>(
          registrar->messenger(), "basicGetHelloMessage",
          &flutter::StandardMessageCodec::GetInstance());

  auto plugin = std::make_unique<HelloPlatformWindowsPlugin>();

    channel->SetMessageHandler(
      [plugin_pointer = plugin.get()](const auto &message, auto &reply) {
        flutter::EncodableMap wrapped = {
            {flutter::EncodableValue("result"),
             flutter::EncodableValue("hello from basic channel")},
        };
        reply(flutter::EncodableValue(wrapped));
      });

  registrar->AddPlugin(std::move(plugin));
}

HelloPlatformWindowsPlugin::HelloPlatformWindowsPlugin() {}

HelloPlatformWindowsPlugin::~HelloPlatformWindowsPlugin() {}

}  // namespace

void HelloPlatformWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  HelloPlatformWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
