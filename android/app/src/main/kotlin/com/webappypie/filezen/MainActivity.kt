package com.webappypie.filezen

import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.BadPaddingException

class MainActivity : FlutterFragmentActivity() {
    private val cryptoExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var deviceChannel: DeviceChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VAULT_CHANNEL)
            .setMethodCallHandler { call, result -> handleVaultCall(call, result) }

        val device = DeviceChannel(applicationContext)
        deviceChannel = device
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DeviceChannel.CHANNEL)
            .setMethodCallHandler { call, result ->
                device.handle(call, result) { runnable -> runOnUiThread(runnable) }
            }
    }

    override fun onDestroy() {
        cryptoExecutor.shutdown()
        deviceChannel?.shutdown()
        super.onDestroy()
    }

    private fun handleVaultCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "setSecure") {
            val secure = call.argument<Boolean>("secure") == true
            if (secure) {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE,
                )
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            result.success(null)
            return
        }

        // Crypto may process large buffers or run PBKDF2; keep it off the UI thread.
        cryptoExecutor.execute {
            try {
                val value = runVaultCrypto(call)
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                val code = errorCode(e)
                runOnUiThread { result.error(code, e.message ?: code, null) }
            }
        }
    }

    private fun runVaultCrypto(call: MethodCall): Any? {
        fun bytes(name: String): ByteArray =
            call.argument<ByteArray>(name) ?: throw IllegalArgumentException("Missing argument: $name")

        fun slot(): VaultKeystore.Slot = when (call.argument<String>("slot")) {
            "device" -> VaultKeystore.Slot.DEVICE
            "biometric" -> VaultKeystore.Slot.BIOMETRIC
            else -> throw IllegalArgumentException("Unknown keystore slot")
        }

        return when (call.method) {
            "gcmEncrypt" -> VaultCrypto.encrypt(bytes("key"), bytes("data"), bytes("aad"))
            "gcmDecrypt" -> VaultCrypto.decrypt(bytes("key"), bytes("data"), bytes("aad"))
            "pbkdf2" -> VaultCrypto.pbkdf2HmacSha256(
                bytes("password"),
                bytes("salt"),
                call.argument<Int>("iterations") ?: throw IllegalArgumentException("Missing iterations"),
                call.argument<Int>("length") ?: throw IllegalArgumentException("Missing length"),
            )
            "keystoreWrap" -> VaultKeystore.wrap(slot(), bytes("data"))
            "keystoreUnwrap" -> VaultKeystore.unwrap(slot(), bytes("data"))
            "keystoreDelete" -> {
                VaultKeystore.delete(slot())
                null
            }
            else -> throw UnsupportedOperationException(call.method)
        }
    }

    private fun errorCode(e: Exception): String = when (e) {
        is KeyPermanentlyInvalidatedException -> "KEY_INVALIDATED"
        is UserNotAuthenticatedException -> "AUTH_REQUIRED"
        is VaultKeystore.KeyMissingException -> "KEY_MISSING"
        is BadPaddingException -> "AUTH_FAILED" // includes AEADBadTagException
        is UnsupportedOperationException -> "UNSUPPORTED"
        is IllegalArgumentException -> "BAD_ARGUMENT"
        // Keystore refuses to create auth-bound keys when no secure lock screen is set.
        is IllegalStateException -> "NO_SECURE_LOCK"
        else -> "CRYPTO_ERROR"
    }

    private companion object {
        const val VAULT_CHANNEL = "com.webappypie.filezen/vault"
    }
}
