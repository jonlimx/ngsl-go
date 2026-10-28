package com.jonlimx.ngsl_go

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/** Bundled Kokoro clips first; dynamic material is synthesized once and cached. */
class SpeechChannel(private val context: Context, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.jonlimx.ngsl_go/speech")
    private val main = Handler(Looper.getMainLooper())
    private var ready = false
    private var result: MethodChannel.Result? = null
    private var generation = 0
    private var player: MediaPlayer? = null
    private var speed = 1f
    private val cache = File(context.filesDir, "story_audio").apply { mkdirs() }
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs)
        .setOnAudioFocusChangeListener { if (it == AudioManager.AUDIOFOCUS_LOSS || it == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stop() }.build()
    private val tts = TextToSpeech(context) { status -> ready = status == TextToSpeech.SUCCESS }

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { main.post {
                val parts = id?.split('|') ?: return@post
                if (parts.size != 2 || parts[0] != generation.toString()) return@post
                val pending = File(cache, parts[1] + ".pending.wav")
                val file = File(cache, parts[1] + ".wav")
                if (pending.length() <= 44 || !pending.renameTo(file)) fail("朗读音频生成失败，请重试。")
                else playFile(file)
            } }
            @Deprecated("Deprecated in Java")
            override fun onError(id: String?) { main.post { if (id?.substringBefore('|') == generation.toString()) fail("朗读生成失败，请检查平板的英语语音包。") } }
            override fun onError(id: String?, errorCode: Int) { onError(id) }
        })
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "stop" -> { stop(); reply.success(null) }
                "installVoices" -> {
                    try { context.startActivity(Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); reply.success(null) }
                    catch (_: Exception) { reply.error("NO_ENGINE", "请在系统设置中安装英语文字转语音服务。", null) }
                }
                "play" -> {
                    stop(); result = reply
                    speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.7f, 1.2f)
                    val asset = call.argument<String>("asset")
                    if (!asset.isNullOrBlank() && Regex("^assets/audio/[a-zA-Z0-9_-]+\\.mp3$").matches(asset)) playAsset(asset)
                    else {
                        val text = call.argument<String>("text")?.trim() ?: ""
                        val accent = call.argument<String>("accent") ?: "uk"
                        if (text.isEmpty() || text.length > 15000) fail("这段文字暂时无法朗读。")
                        else if (!ready) fail("英语语音引擎正在准备，请稍后重试；若一直不可用，请安装系统英语语音包。")
                        else synthesize(text, accent)
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }
    private fun synthesize(text: String, accent: String) {
        val country = if (accent == "us") "US" else "GB"
        val voice = tts.voices?.filter { it.locale.language == "en" && it.locale.country == country && !it.isNetworkConnectionRequired }?.maxByOrNull { it.quality }
        if (voice == null) { fail("平板尚未安装${if (accent == "us") "美音" else "英音"}离线语音包，请在设置中安装英语语音。" ); return }
        tts.voice = voice
        tts.setSpeechRate(1f)
        val hash = MessageDigest.getInstance("SHA-256").digest((voice.name + "|" + text).toByteArray()).take(16).joinToString("") { "%02x".format(it) }
        val file = File(cache, "$hash.wav")
        if (file.length() > 44) { playFile(file); return }
        // Bound the cache; fixed bundled vocabulary clips are never removed.
        val cached = cache.listFiles()?.filter { it.extension == "wav" }?.sortedBy { it.lastModified() } ?: emptyList()
        var total = cached.sumOf { it.length() }
        for (old in cached) { if (total <= 150L * 1024 * 1024) break; total -= old.length(); old.delete() }
        val id = "$generation|$hash"
        val code = tts.synthesizeToFile(text, null, File(cache, "$hash.pending.wav"), id)
        if (code != TextToSpeech.SUCCESS) fail("这段文字暂时无法朗读，请重试。")
    }
    private fun prepare(next: MediaPlayer) {
        player = next
        next.setAudioAttributes(attrs)
        next.setOnPreparedListener {
            if (player !== next) return@setOnPreparedListener
            try {
                if (audioManager.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { fail("当前声音被其他应用占用，请稍后重试。"); return@setOnPreparedListener }
                next.playbackParams = PlaybackParams().setSpeed(speed)
                next.start(); result?.success(null); result = null
            } catch (_: Exception) { fail("朗读暂时无法播放，请重试。") }
        }
        next.setOnCompletionListener { if (player === next) release() }
        next.setOnErrorListener { _, _, _ -> if (player === next) fail("朗读中断，请重试。"); true }
    }
    private fun playAsset(name: String) {
        try {
            val next = MediaPlayer(); prepare(next)
            context.assets.openFd(FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(name)).use { next.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            next.prepareAsync()
        } catch (_: Exception) { fail("配套朗读暂时无法播放，请重试。") }
    }
    private fun playFile(file: File) {
        try { val next = MediaPlayer(); prepare(next); next.setDataSource(file.absolutePath); next.prepareAsync() }
        catch (_: Exception) { file.delete(); fail("朗读暂时无法播放，请重试。") }
    }
    private fun fail(message: String) { result?.error("SPEECH", message, null); result = null; release() }
    private fun release() { val old = player; player = null; old?.release(); audioManager.abandonAudioFocusRequest(focus) }
    fun stop() { ++generation; tts.stop(); result?.success(null); result = null; release() }
    fun dispose() { stop(); tts.shutdown(); channel.setMethodCallHandler(null) }
}
