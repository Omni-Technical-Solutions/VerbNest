#ifndef FLUTTER_PLUGIN_VERBNEST_KEYSTORE_PLUGIN_H_
#define FLUTTER_PLUGIN_VERBNEST_KEYSTORE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

namespace verbnest_keystore {

// Channel com.omni.verbnest/keystore on Windows (FR-HTTP-013f phase K): the
// "MY" certificate store, SChannel for the TLS handshake. NOT BUILT OR TESTED
// YET.
class VerbnestKeystorePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  VerbnestKeystorePlugin() = default;
  ~VerbnestKeystorePlugin() override = default;
  VerbnestKeystorePlugin(const VerbnestKeystorePlugin&) = delete;
  VerbnestKeystorePlugin& operator=(const VerbnestKeystorePlugin&) = delete;

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace verbnest_keystore

#endif  // FLUTTER_PLUGIN_VERBNEST_KEYSTORE_PLUGIN_H_
