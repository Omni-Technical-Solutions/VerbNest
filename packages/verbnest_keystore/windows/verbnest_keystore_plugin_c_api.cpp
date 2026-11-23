#include "include/verbnest_keystore/verbnest_keystore_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "verbnest_keystore_plugin.h"

void VerbnestKeystorePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  verbnest_keystore::VerbnestKeystorePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
