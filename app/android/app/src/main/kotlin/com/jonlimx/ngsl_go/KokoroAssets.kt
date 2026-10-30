package com.jonlimx.ngsl_go

import android.content.Context
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/** Only model/cache directories are changed here; learner data is never read. */
class KokoroAssets(private val context: Context) {
    val directory = File(context.filesDir, "kokoro")
    val audio = File(context.filesDir, "kokoro_audio")
    private fun asset(name: String) = FlutterInjector.instance().flutterLoader()
        .getLookupKeyForAsset("assets/tts/$name")
    private fun manifestText() = context.assets.open(asset("kokoro_manifest.json")).bufferedReader().use { it.readText() }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }

    fun status(): Map<String, Any> = try {
        val text = manifestText()
        val manifest = JSONObject(text)
        val ready = File(directory, "ready.sha256").takeIf { it.isFile }?.readText() == digest(text.toByteArray()) &&
            File(directory, "model.onnx").isFile && File(directory, "voices.bin").isFile
        mapOf("engine" to "Kokoro", "bundled" to true, "ready" to ready,
            "initializing" to false, "uk" to 1, "us" to 1, "english" to 2,
            "version" to manifest.getString("version"), "bytes" to manifest.getLong("totalBytes"))
    } catch (_: Exception) {
        mapOf("engine" to "Kokoro", "bundled" to false, "ready" to false, "initializing" to false)
    }

    @Synchronized fun prepare(): Map<String, String> {
        val text = manifestText()
        val manifest = JSONObject(text)
        val hash = digest(text.toByteArray())
        val files = manifest.getJSONArray("files")
        val expected = (0 until files.length()).associate {
            val item = files.getJSONObject(it)
            item.getString("path") to item
        }
        val alreadyReady = status()["ready"] == true && expected.all { (path, item) ->
            File(directory, path).let { it.isFile && it.length() == item.getLong("bytes") }
        }
        if (!alreadyReady) {
            val staging = File(context.filesDir, "kokoro_incoming")
            staging.deleteRecursively()
            check(staging.mkdirs()) { "无法创建离线语音目录，请检查存储空间。" }
            val seen = mutableSetOf<String>()
            try {
                ZipInputStream(context.assets.open(asset("kokoro.zip")).buffered()).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        val item = expected[entry.name] ?: error("语音资源包含未验证的文件。")
                        check(!entry.isDirectory && !entry.name.startsWith("/") &&
                            !entry.name.contains('\\') && !entry.name.split('/').contains("..") && seen.add(entry.name))
                        val target = File(staging, entry.name)
                        check(target.canonicalPath.startsWith(staging.canonicalPath + File.separator))
                        target.parentFile?.mkdirs()
                        val checksum = MessageDigest.getInstance("SHA-256")
                        var size = 0L
                        target.outputStream().buffered().use { output ->
                            val buffer = ByteArray(128 * 1024)
                            while (true) {
                                val count = zip.read(buffer)
                                if (count < 0) break
                                size += count
                                check(size <= item.getLong("bytes")) { "语音资源大小不符。" }
                                checksum.update(buffer, 0, count)
                                output.write(buffer, 0, count)
                            }
                        }
                        check(size == item.getLong("bytes") && checksum.digest().joinToString("") { "%02x".format(it) } == item.getString("sha256")) {
                            "语音资源校验失败，请重新构建安装包。"
                        }
                        zip.closeEntry()
                    }
                }
                check(seen == expected.keys) { "语音资源不完整，请重新构建安装包。" }
                File(staging, "ready.sha256").writeText(hash)
                val old = File(context.filesDir, "kokoro_previous")
                old.deleteRecursively()
                if (directory.exists()) check(directory.renameTo(old))
                if (!staging.renameTo(directory)) {
                    old.renameTo(directory)
                    error("语音资源保存失败，请检查存储空间。")
                }
                old.deleteRecursively()
            } finally {
                staging.deleteRecursively()
            }
        }
        audio.mkdirs()
        return mapOf("model" to directory.absolutePath, "audio" to audio.absolutePath,
            "version" to manifest.getString("version"))
    }
}
