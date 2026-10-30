package com.jonlimx.ngsl_go

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Playback and checked model extraction only. Synthesis uses in-app Kokoro. */
class SpeechChannel(private val context: Context, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.jonlimx.ngsl_go/speech")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val kokoro = KokoroAssets(context)
    private var result: MethodChannel.Result? = null
    private var generation = 0
    private var disposed = false
    private var player: MediaPlayer? = null
    private var speed = 1f
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs)
        .setOnAudioFocusChangeListener {
            if (it == AudioManager.AUDIOFOCUS_LOSS || it == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) interrupt()
        }.build()

    init {
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "stop" -> { stop(); reply.success(null) }
                "beginSpeech" -> { stop(); reply.success(generation) }
                "voiceStatus" -> reply.success(kokoro.status())
                "refreshVoices" -> reply.success(null)
                "prepareKokoro" -> executor.execute {
                    try {
                        val paths = kokoro.prepare()
                        main.post { reply.success(paths) }
                    } catch (error: Exception) {
                        main.post { reply.error("KOKORO_ASSETS", "Kokoro 离线语音准备失败，请检查剩余存储空间；如安装包缺少模型，请重新运行安装脚本。", error.message) }
                    }
                }
                "play" -> {
                    stop(); result = reply
                    speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.7f, 1.2f)
                    val asset = call.argument<String>("asset")
                    if (!asset.isNullOrBlank() && Regex("^assets/audio/[a-zA-Z0-9_-]+\\.mp3$").matches(asset)) playAsset(asset)
                    else fail("此内容需要先通过应用内 Kokoro 生成音频。")
                }
                "playFile" -> {
                    val token = call.argument<Number>("token")?.toInt()
                    if (token != generation || disposed) { reply.success(null); return@setMethodCallHandler }
                    result = reply
                    speed = (call.argument<Number>("speed")?.toFloat() ?: 1f).coerceIn(0.7f, 1.2f)
                    try {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        check(file.parentFile == kokoro.audio.canonicalFile &&
                            Regex("^[a-f0-9]{64}\\.wav$").matches(file.name) && file.length() > 44)
                        playFile(file)
                    } catch (_: Exception) { fail("Kokoro 朗读文件暂时不可用，请重试。") }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun prepare(next: MediaPlayer) {
        player = next
        next.setAudioAttributes(attrs)
        next.setOnPreparedListener {
            if (player !== next || disposed) return@setOnPreparedListener
            try {
                if (audioManager.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    fail("当前声音被其他应用占用，请稍后重试。"); return@setOnPreparedListener
                }
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
            context.assets.openFd(FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(name)).use {
                next.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            next.prepareAsync()
        } catch (_: Exception) { fail("配套朗读暂时无法播放，请重试。") }
    }
    private fun playFile(file: File) {
        try { val next = MediaPlayer(); prepare(next); next.setDataSource(file.absolutePath); next.prepareAsync() }
        catch (_: Exception) { file.delete(); fail("朗读暂时无法播放，请重试。") }
    }
    private fun fail(message: String) { result?.error("SPEECH", message, null); result = null; release() }
    private fun release() { val old = player; player = null; old?.release(); audioManager.abandonAudioFocusRequest(focus) }
    fun stop() { ++generation; result?.success(null); result = null; release() }
    fun interrupt() { stop(); channel.invokeMethod("interrupted", null) }
    fun onResume() { /* Kokoro has no system engine or external voice settings. */ }
    fun dispose() { disposed = true; stop(); executor.shutdown(); channel.setMethodCallHandler(null) }
}
