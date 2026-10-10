package com.webappypie.filezen

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Vault cryptographic primitives built only on standard JCA algorithms
 * (AES-256-GCM and PBKDF2-HMAC-SHA256). No Android dependencies, so they are
 * unit-testable on the host JVM.
 *
 * Blob layout produced by [encrypt]: nonce (12 bytes) || ciphertext || GCM tag (16 bytes).
 */
object VaultCrypto {
    const val KEY_BYTES = 32
    const val NONCE_BYTES = 12
    const val TAG_BITS = 128
    private const val TAG_BYTES = TAG_BITS / 8
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    private val random = SecureRandom()

    /** Encrypts [plaintext] with a fresh random 96-bit nonce; [aad] is authenticated but not encrypted. */
    fun encrypt(key: ByteArray, plaintext: ByteArray, aad: ByteArray): ByteArray {
        require(key.size == KEY_BYTES) { "AES-256 key must be $KEY_BYTES bytes" }
        val nonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        cipher.updateAAD(aad)
        return nonce + cipher.doFinal(plaintext)
    }

    /**
     * Decrypts a blob produced by [encrypt]. Throws [javax.crypto.AEADBadTagException]
     * when the key, AAD or ciphertext does not authenticate.
     */
    fun decrypt(key: ByteArray, blob: ByteArray, aad: ByteArray): ByteArray {
        require(key.size == KEY_BYTES) { "AES-256 key must be $KEY_BYTES bytes" }
        require(blob.size >= NONCE_BYTES + TAG_BYTES) { "Ciphertext blob too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(TAG_BITS, blob.copyOfRange(0, NONCE_BYTES)),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(blob, NONCE_BYTES, blob.size - NONCE_BYTES)
    }

    /**
     * PBKDF2-HMAC-SHA256 (RFC 8018). Implemented over [Mac] because the
     * "PBKDF2WithHmacSHA256" SecretKeyFactory is unavailable below API 26 and minSdk is 24.
     */
    fun pbkdf2HmacSha256(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray {
        require(password.isNotEmpty()) { "Password must not be empty" }
        require(iterations > 0) { "Iterations must be positive" }
        require(length > 0) { "Length must be positive" }

        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(password, "HmacSHA256"))
        val hashLen = mac.macLength
        val blocks = (length + hashLen - 1) / hashLen
        val out = ByteArray(length)

        for (block in 1..blocks) {
            mac.update(salt)
            mac.update(
                byteArrayOf(
                    (block ushr 24).toByte(),
                    (block ushr 16).toByte(),
                    (block ushr 8).toByte(),
                    block.toByte(),
                ),
            )
            var u = mac.doFinal()
            val t = u.copyOf()
            for (i in 1 until iterations) {
                u = mac.doFinal(u)
                for (j in t.indices) t[j] = (t[j].toInt() xor u[j].toInt()).toByte()
            }
            val offset = (block - 1) * hashLen
            System.arraycopy(t, 0, out, offset, minOf(hashLen, length - offset))
        }
        return out
    }
}
