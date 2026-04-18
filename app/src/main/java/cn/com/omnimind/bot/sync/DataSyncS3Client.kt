package cn.com.omnimind.bot.sync

import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody

class DataSyncS3Client {
    companion object {
        private const val SERVICE = "s3"
        private val EMPTY_SHA256 = DataSyncCrypto.sha256Hex(ByteArray(0))
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    fun testConnection(config: DataSyncConfig) {
        val query = linkedMapOf(
            "list-type" to "2",
            "max-keys" to "1",
            "prefix" to "namespaces/${config.namespace}/"
        )
        execute(
            config = config,
            method = "GET",
            objectKey = "",
            payloadHash = EMPTY_SHA256,
            query = query
        ).use { response ->
            check(response.isSuccessful) {
                "S3 test failed with code ${response.code}"
            }
        }
    }

    fun objectExists(config: DataSyncConfig, objectKey: String): Boolean {
        execute(
            config = config,
            method = "HEAD",
            objectKey = objectKey,
            payloadHash = EMPTY_SHA256
        ).use { response ->
            return when (response.code) {
                200 -> true
                404 -> false
                else -> error("S3 HEAD failed with code ${response.code}")
            }
        }
    }

    fun uploadObject(config: DataSyncConfig, objectKey: String, file: File, contentHash: String) {
        val mediaType = guessContentType(file.name).toMediaType()
        execute(
            config = config,
            method = "PUT",
            objectKey = objectKey,
            payloadHash = contentHash,
            contentType = mediaType.toString(),
            requestBody = file.asRequestBody(mediaType)
        ).use { response ->
            check(response.isSuccessful) {
                "S3 upload failed with code ${response.code}"
            }
        }
    }

    fun downloadObject(config: DataSyncConfig, objectKey: String, destination: File) {
        execute(
            config = config,
            method = "GET",
            objectKey = objectKey,
            payloadHash = EMPTY_SHA256
        ).use { response ->
            check(response.isSuccessful) {
                "S3 download failed with code ${response.code}"
            }
            destination.parentFile?.mkdirs()
            FileOutputStream(destination).use { output ->
                response.body?.byteStream()?.copyTo(output)
            }
        }
    }

    private fun execute(
        config: DataSyncConfig,
        method: String,
        objectKey: String,
        payloadHash: String,
        query: Map<String, String> = emptyMap(),
        contentType: String? = null,
        requestBody: okhttp3.RequestBody? = null
    ): okhttp3.Response {
        val endpoint = resolveEndpoint(config, objectKey, query)
        val now = Date()
        val amzDate = utcDateTime(now)
        val dateStamp = utcDate(now)
        val headers = linkedMapOf(
            "host" to endpoint.hostHeader,
            "x-amz-content-sha256" to payloadHash,
            "x-amz-date" to amzDate
        )
        if (contentType != null) {
            headers["content-type"] = contentType
        }
        if (config.sessionToken.isNotBlank()) {
            headers["x-amz-security-token"] = config.sessionToken
        }
        val canonicalHeaders = headers.entries
            .sortedBy { it.key }
            .joinToString("") { "${it.key}:${it.value.trim()}\n" }
        val signedHeaders = headers.keys.sorted().joinToString(";")
        val canonicalRequest = listOf(
            method.uppercase(Locale.US),
            endpoint.canonicalUri,
            endpoint.canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ).joinToString("\n")
        val credentialScope = "$dateStamp/${config.region}/$SERVICE/aws4_request"
        val stringToSign = listOf(
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            DataSyncCrypto.sha256Hex(canonicalRequest)
        ).joinToString("\n")
        val signature = signAws4(
            secretKey = config.secretKey,
            dateStamp = dateStamp,
            region = config.region,
            stringToSign = stringToSign
        )
        val authorization = buildString {
            append("AWS4-HMAC-SHA256 ")
            append("Credential=${config.accessKey}/$credentialScope, ")
            append("SignedHeaders=$signedHeaders, ")
            append("Signature=$signature")
        }
        val builder = Request.Builder()
            .url(endpoint.url)
            .method(method, if (method == "GET" || method == "HEAD") null else requestBody)
            .addHeader("Authorization", authorization)
        headers.forEach { (key, value) ->
            builder.addHeader(key, value)
        }
        return client.newCall(builder.build()).execute()
    }

    private fun resolveEndpoint(
        config: DataSyncConfig,
        objectKey: String,
        query: Map<String, String>
    ): ResolvedS3Endpoint {
        val endpoint = URI(config.s3Endpoint)
        val scheme = endpoint.scheme ?: "https"
        val defaultPort = when (scheme) {
            "http" -> 80
            else -> 443
        }
        val host = endpoint.host ?: error("Invalid S3 endpoint host")
        val port = endpoint.port.takeIf { it > 0 && it != defaultPort }?.let { ":$it" }.orEmpty()
        val basePath = endpoint.rawPath?.trimEnd('/').orEmpty()
        val encodedObjectKey = objectKey
            .trim('/')
            .split('/')
            .filter { it.isNotBlank() }
            .joinToString("/") { awsEncode(it) }
        val canonicalUri = buildString {
            append(if (basePath.isBlank()) "" else basePath)
            if (config.forcePathStyle) {
                append("/")
                append(awsEncode(config.bucket))
            }
            if (encodedObjectKey.isNotBlank()) {
                append("/")
                append(encodedObjectKey)
            } else if (isEmpty()) {
                append("/")
            }
        }
        val hostHeader = if (config.forcePathStyle) {
            "$host$port"
        } else {
            "${config.bucket}.$host$port"
        }
        val canonicalQuery = query.entries
            .sortedBy { it.key }
            .joinToString("&") { "${awsEncode(it.key)}=${awsEncode(it.value)}" }
        val url = buildString {
            append(scheme)
            append("://")
            append(hostHeader)
            append(canonicalUri.ifBlank { "/" })
            if (canonicalQuery.isNotBlank()) {
                append("?")
                append(canonicalQuery)
            }
        }
        return ResolvedS3Endpoint(
            url = url,
            hostHeader = hostHeader,
            canonicalUri = canonicalUri.ifBlank { "/" },
            canonicalQuery = canonicalQuery
        )
    }

    private fun signAws4(
        secretKey: String,
        dateStamp: String,
        region: String,
        stringToSign: String
    ): String {
        val kDate = hmac("AWS4$secretKey", dateStamp)
        val kRegion = hmac(kDate, region)
        val kService = hmac(kRegion, SERVICE)
        val kSigning = hmac(kService, "aws4_request")
        return hmacHex(kSigning, stringToSign)
    }

    private fun hmac(key: String, data: String): ByteArray {
        return javax.crypto.Mac.getInstance("HmacSHA256").run {
            init(javax.crypto.spec.SecretKeySpec(key.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
            doFinal(data.toByteArray(StandardCharsets.UTF_8))
        }
    }

    private fun hmac(key: ByteArray, data: String): ByteArray {
        return javax.crypto.Mac.getInstance("HmacSHA256").run {
            init(javax.crypto.spec.SecretKeySpec(key, "HmacSHA256"))
            doFinal(data.toByteArray(StandardCharsets.UTF_8))
        }
    }

    private fun hmacHex(key: ByteArray, data: String): String {
        return hmac(key, data).joinToString("") { "%02x".format(it) }
    }

    private fun utcDateTime(date: Date): String {
        return SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(date)
    }

    private fun utcDate(date: Date): String {
        return SimpleDateFormat("yyyyMMdd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(date)
    }

    private fun awsEncode(raw: String): String {
        return buildString {
            raw.toByteArray(StandardCharsets.UTF_8).forEach { byte ->
                val char = byte.toInt().toChar()
                if (char.isLetterOrDigit() || char == '-' || char == '_' || char == '.' || char == '~') {
                    append(char)
                } else {
                    append("%")
                    append("%02X".format(byte.toInt() and 0xff))
                }
            }
        }
    }

    private fun guessContentType(name: String): String {
        return java.net.URLConnection.guessContentTypeFromName(name) ?: "application/octet-stream"
    }

    private data class ResolvedS3Endpoint(
        val url: String,
        val hostHeader: String,
        val canonicalUri: String,
        val canonicalQuery: String
    )
}
