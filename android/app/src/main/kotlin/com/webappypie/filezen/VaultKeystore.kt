package com.webappypie.filezen

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore wrapping keys for the vault master key.
 *
 *  - [Slot.DEVICE]: hardware-backed AES-256-GCM key, no user authentication. Binds the
 *    wrapped master key to this device so the PIN cannot be brute-forced offline from a
 *    copied app-data directory.
 *  - [Slot.BIOMETRIC]: AES-256-GCM key that the Keystore only releases for a short window
 *    after a successful biometric / device-credential authentication. The Keystore, not the
 *    Flutter layer, enforces that authentication happened.
 */
object VaultKeystore {
    enum class Slot(val alias: String, val requiresUserAuth: Boolean) {
        DEVICE("filezen_vault_device_key_v1", false),
        BIOMETRIC("filezen_vault_biometric_key_v1", true),
    }

    private const val PROVIDER = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val AUTH_VALIDITY_SECONDS = 15

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    private fun existingKey(slot: Slot): SecretKey? =
        keyStore().getKey(slot.alias, null) as? SecretKey

    private fun createKey(slot: Slot): SecretKey {
        val builder = KeyGenParameterSpec.Builder(
            slot.alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)

        if (slot.requiresUserAuth) {
            builder.setUserAuthenticationRequired(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setUserAuthenticationParameters(
                    AUTH_VALIDITY_SECONDS,
                    KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                )
            } else {
                @Suppress("DEPRECATION")
                builder.setUserAuthenticationValidityDurationSeconds(AUTH_VALIDITY_SECONDS)
            }
            builder.setInvalidatedByBiometricEnrollment(true)
        }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(builder.build())
        return generator.generateKey()
    }

    /** Returns iv (12 bytes) || ciphertext || tag. */
    fun wrap(slot: Slot, plaintext: ByteArray): ByteArray {
        val key = existingKey(slot) ?: createKey(slot)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(plaintext)
        return cipher.iv + ciphertext
    }

    fun unwrap(slot: Slot, blob: ByteArray): ByteArray {
        require(blob.size > IV_BYTES) { "Wrapped key blob too short" }
        val key = existingKey(slot) ?: throw KeyMissingException(slot.alias)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(TAG_BITS, blob.copyOfRange(0, IV_BYTES)),
        )
        return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
    }

    fun delete(slot: Slot) {
        val store = keyStore()
        if (store.containsAlias(slot.alias)) store.deleteEntry(slot.alias)
    }

    class KeyMissingException(alias: String) : Exception("Keystore key $alias is missing")
}
