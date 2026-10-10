package com.webappypie.filezen

import javax.crypto.AEADBadTagException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class VaultCryptoTest {
    private fun hex(s: String): ByteArray =
        ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private val key = ByteArray(32) { it.toByte() }
    private val aad = "zenvault-test".toByteArray()

    @Test
    fun pbkdf2MatchesPublishedSha256Vectors() {
        val pw = "password".toByteArray()
        val salt = "salt".toByteArray()
        assertEquals(
            "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
            VaultCrypto.pbkdf2HmacSha256(pw, salt, 1, 32).toHex(),
        )
        assertEquals(
            "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43",
            VaultCrypto.pbkdf2HmacSha256(pw, salt, 2, 32).toHex(),
        )
        assertEquals(
            "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
            VaultCrypto.pbkdf2HmacSha256(pw, salt, 4096, 32).toHex(),
        )
    }

    @Test
    fun pbkdf2SupportsMultiBlockOutput() {
        // RFC 7914 section 11
        assertEquals(
            "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc" +
                "49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783",
            VaultCrypto.pbkdf2HmacSha256("passwd".toByteArray(), "salt".toByteArray(), 1, 64).toHex(),
        )
    }

    @Test
    fun gcmRoundTripPreservesPlaintext() {
        val plaintext = "confidential vault payload".toByteArray()
        val blob = VaultCrypto.encrypt(key, plaintext, aad)
        assertEquals(plaintext.size + 12 + 16, blob.size)
        assertArrayEquals(plaintext, VaultCrypto.decrypt(key, blob, aad))
    }

    @Test
    fun gcmHandlesEmptyPlaintext() {
        val blob = VaultCrypto.encrypt(key, ByteArray(0), aad)
        assertEquals(0, VaultCrypto.decrypt(key, blob, aad).size)
    }

    @Test
    fun gcmUsesFreshNonceForEveryEncryption() {
        val nonces = (1..200).map {
            VaultCrypto.encrypt(key, "same".toByteArray(), aad).copyOfRange(0, 12).toHex()
        }
        assertEquals(nonces.size, nonces.toSet().size)
    }

    @Test
    fun gcmRejectsTamperedCiphertext() {
        val blob = VaultCrypto.encrypt(key, "payload".toByteArray(), aad)
        blob[14] = (blob[14].toInt() xor 0x01).toByte()
        assertThrows(AEADBadTagException::class.java) { VaultCrypto.decrypt(key, blob, aad) }
    }

    @Test
    fun gcmRejectsTamperedTagAndNonce() {
        val blob = VaultCrypto.encrypt(key, "payload".toByteArray(), aad)

        val badTag = blob.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 0x80).toByte() }
        assertThrows(AEADBadTagException::class.java) { VaultCrypto.decrypt(key, badTag, aad) }

        val badNonce = blob.copyOf().also { it[0] = (it[0].toInt() xor 0x01).toByte() }
        assertThrows(AEADBadTagException::class.java) { VaultCrypto.decrypt(key, badNonce, aad) }
    }

    @Test
    fun gcmRejectsWrongKeyAndWrongAad() {
        val blob = VaultCrypto.encrypt(key, "payload".toByteArray(), aad)
        val otherKey = key.copyOf().also { it[0] = (it[0].toInt() xor 0x01).toByte() }
        assertThrows(AEADBadTagException::class.java) { VaultCrypto.decrypt(otherKey, blob, aad) }
        assertThrows(AEADBadTagException::class.java) {
            VaultCrypto.decrypt(key, blob, "other-context".toByteArray())
        }
    }

    @Test
    fun gcmRejectsTruncatedBlobAndBadKeyLength() {
        assertThrows(IllegalArgumentException::class.java) {
            VaultCrypto.decrypt(key, ByteArray(10), aad)
        }
        assertThrows(IllegalArgumentException::class.java) {
            VaultCrypto.encrypt(ByteArray(16), "x".toByteArray(), aad)
        }
    }

    @Test
    fun ciphertextDoesNotContainPlaintext() {
        val marker = "TOP-SECRET-MARKER-STRING".toByteArray()
        val blob = VaultCrypto.encrypt(key, marker, aad)
        assertFalse(String(blob, Charsets.ISO_8859_1).contains(String(marker, Charsets.ISO_8859_1)))
        assertArrayEquals(hex("00ff"), hex("00ff")) // sanity for helper
    }
}
