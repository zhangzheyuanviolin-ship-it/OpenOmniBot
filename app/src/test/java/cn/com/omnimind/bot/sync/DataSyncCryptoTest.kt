package cn.com.omnimind.bot.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class DataSyncCryptoTest {

    @Test
    fun signRequest_isDeterministic() {
        val signature = DataSyncCrypto.signRequest(
            secret = "secret-key",
            method = "POST",
            path = "/functions/v1/sync-push",
            timestamp = "1710000000000",
            nonce = "nonce-1",
            bodyHash = "abc123"
        )

        assertEquals(
            "a554a5a6a8df448e5b18b8e6f0227c2aef3a4a568ce266fc5b2c013076927a80",
            signature
        )
    }

    @Test
    fun pairingPayload_roundTripsWithSamePassphrase() {
        val encrypted = DataSyncCrypto.encryptPairingPayload(
            json = """{"namespace":"demo","syncSecret":"123"}""",
            passphrase = "onetimer",
            namespace = "demo"
        )

        val decrypted = DataSyncCrypto.decryptPairingPayload(
            encrypted.encodedPayload,
            "onetimer"
        )

        assertEquals("""{"namespace":"demo","syncSecret":"123"}""", decrypted)
        assertNotEquals("", encrypted.encodedPayload)
    }

    @Test
    fun objectKey_usesNamespaceAndHash() {
        assertEquals(
            "namespaces/demo/objects/abcdef",
            objectKeyForHash("demo", "abcdef")
        )
    }
}
