package com.omni.verbnest.keystore;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * Channel com.omni.verbnest/keystore (see apps/verbnest_app/lib/src/state/
 * keystore_relay.dart): supported, identities, import, choose, open, close.
 */
public class VerbnestKeystorePlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private MethodChannel channel;
    private final ExecutorService work = Executors.newCachedThreadPool();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final KeystoreBridge bridge = new KeystoreBridge();
    private Activity activity;
    private android.content.Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.omni.verbnest/keystore");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        bridge.closeAll();
    }

    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding b) { activity = b.getActivity(); }
    @Override public void onDetachedFromActivityForConfigChanges() { activity = null; }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) { activity = b.getActivity(); }
    @Override public void onDetachedFromActivity() { activity = null; }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "supported":
                result.success(true);
                break;
            case "identities":
                run(result, () -> bridge.identities());
                break;
            case "import": {
                final byte[] bytes = call.argument("bytes");
                final String pass = call.argument("passphrase");
                run(result, () -> bridge.importPkcs12(bytes, pass == null ? "" : pass));
                break;
            }
            case "remove": {
                final String identity = call.argument("identity");
                run(result, () -> { bridge.remove(identity); return null; });
                break;
            }
            case "choose":
                if (activity == null) {
                    result.error("keystore", "No window to show the certificate chooser in.", null);
                } else {
                    bridge.choose(activity, (map, error) -> main.post(() -> {
                        if (error != null) result.error("keystore", error, null);
                        else result.success(map);
                    }), work);
                }
                break;
            case "open": {
                final String host = call.argument("host");
                final Integer port = call.argument("port");
                final String identity = call.argument("identity");
                final List<byte[]> cas = call.argument("cas");
                final String minVersion = call.argument("minVersion");
                final Boolean verify = call.argument("verify");
                final List<String> protocols = call.argument("protocols");
                work.execute(() -> {
                    try {
                        final Map<String, Object> map = bridge.open(
                            context, host, port == null ? 443 : port, identity,
                            cas == null ? new ArrayList<>() : cas, minVersion,
                            verify == null || verify,
                            protocols == null ? new ArrayList<>() : protocols);
                        main.post(() -> result.success(map));
                    } catch (final Failure e) {
                        main.post(() -> result.error("keystore", e.getMessage(), null));
                    } catch (final Exception e) {
                        main.post(() -> result.error("keystore", "" + e, null));
                    }
                });
                break;
            }
            case "close": {
                final String session = call.argument("session");
                bridge.close(session);
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    private interface Job { Object call() throws Exception; }

    private void run(final Result result, final Job job) {
        work.execute(() -> {
            try {
                final Object value = job.call();
                main.post(() -> result.success(value));
            } catch (final Failure e) {
                main.post(() -> result.error("keystore", e.getMessage(), null));
            } catch (final Exception e) {
                main.post(() -> result.error("keystore", "" + e, null));
            }
        });
    }

    /** A failure whose message is for the person. */
    static final class Failure extends Exception {
        Failure(String message) { super(message); }
    }
}
