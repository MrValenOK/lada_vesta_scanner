//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_bluetooth_classic_serial/flutter_bluetooth_classic_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterBluetoothClassicPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterBluetoothClassicPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}
