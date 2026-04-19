package cn.com.omnimind.bot.sync

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File
import java.io.FileInputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

object DataSyncCrypto {
    private const val PAIRING_VERSION = 2
    private const val LEGACY_ENCRYPTED_PAIRING_VERSION = 1
    private const val PBKDF2_ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256
    private const val GCM_TAG_LENGTH_BITS = 128

    fun sha256Hex(text: String): String {
        return sha256Hex(text.toByteArray(StandardCharsets.UTF_8))
    }

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun hmacSha256Hex(secret: String, content: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(content.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    fun signRequest(
        secret: String,
        method: String,
        path: String,
        timestamp: String,
        nonce: String,
        bodyHash: String
    ): String {
        val signingText = listOf(
            method.uppercase(),
            path,
            timestamp,
            nonce,
            bodyHash
        ).joinToString("\n")
        return hmacSha256Hex(secret, signingText)
    }

    fun encodePairingPayload(json: String, namespace: String): DataSyncPairingPayload {
        val createdAt = System.currentTimeMillis()
        val payload = JsonObject().apply {
            addProperty("v", PAIRING_VERSION)
            addProperty("namespace", namespace)
            addProperty("createdAt", createdAt)
            add("payload", JsonParser.parseString(json))
        }
        return DataSyncPairingPayload(
            encodedPayload = dataSyncGson.toJson(payload),
            namespace = namespace,
            createdAt = createdAt
        )
    }

    fun decodePairingPayload(encodedPayload: String): String {
        val payload = dataSyncGson.fromJson(encodedPayload, JsonObject::class.java)
        val version = payload.get("v")?.asInt
        if (version == LEGACY_ENCRYPTED_PAIRING_VERSION) {
            error("This pairing payload was exported by an older version. Please re-export it from the source device.")
        }
        if (version != null && version != PAIRING_VERSION) {
            error("Unsupported pairing payload version")
        }
        val rawPayload = payload.get("payload")
        if (rawPayload != null) {
            return rawPayload.toString()
        }
        return encodedPayload
    }

    @Deprecated("Pairing payloads are no longer encrypted")
    fun encryptPairingPayload(json: String, passphrase: String, namespace: String): DataSyncPairingPayload {
        val random = SecureRandom()
        val salt = ByteArray(16).also(random::nextBytes)
        val iv = ByteArray(12).also(random::nextBytes)
        val key = deriveKey(passphrase, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
        val encrypted = cipher.doFinal(json.toByteArray(StandardCharsets.UTF_8))
        val payload = JsonObject().apply {
            addProperty("v", PAIRING_VERSION)
            addProperty("namespace", namespace)
            addProperty("createdAt", System.currentTimeMillis())
            addProperty("salt", salt.toBase64())
            addProperty("iv", iv.toBase64())
            addProperty("cipherText", encrypted.toBase64())
        }
        return DataSyncPairingPayload(
            encodedPayload = dataSyncGson.toJson(payload),
            namespace = namespace
        )
    }

    @Deprecated("Pairing payloads are no longer encrypted")
    fun decryptPairingPayload(encodedPayload: String, passphrase: String): String {
        val payload = dataSyncGson.fromJson(encodedPayload, JsonObject::class.java)
        require(payload.get("v")?.asInt == LEGACY_ENCRYPTED_PAIRING_VERSION) { "Unsupported pairing payload version" }
        val salt = payload.get("salt")?.asString?.fromBase64()
            ?: error("Missing pairing payload salt")
        val iv = payload.get("iv")?.asString?.fromBase64()
            ?: error("Missing pairing payload iv")
        val cipherText = payload.get("cipherText")?.asString?.fromBase64()
            ?: error("Missing pairing payload cipherText")
        val key = deriveKey(passphrase, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
        return String(cipher.doFinal(cipherText), StandardCharsets.UTF_8)
    }

    private fun deriveKey(passphrase: String, salt: ByteArray): SecretKeySpec {
        require(passphrase.isNotBlank()) { "Pairing passphrase cannot be empty" }
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, PBKDF2_ITERATIONS, KEY_LENGTH_BITS)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val secret = factory.generateSecret(spec).encoded
        return SecretKeySpec(secret, "AES")
    }
}

private fun ByteArray.toBase64(): String {
    return Base64.getEncoder().withoutPadding().encodeToString(this)
}

private fun String.fromBase64(): ByteArray {
    return Base64.getDecoder().decode(this)
}
