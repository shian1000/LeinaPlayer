package com.shian1000.music_database_app

import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * "Wyrównywanie głośności": Android's DynamicsProcessing on each player's audio session, as one
 * steady gain for the whole song (worked out in Dart, `recordings.dart`; 0 dB for a song not
 * measured yet). No compressor: it squashed songs with a wide dynamic range, which the user
 * heard as the music ducking (2026-11-03). The limiter is only a safety net — the gain is
 * already held back so the song's peak stays under it. On the `music_database_app/volume_leveling` channel
 * (`lib/src/playback/volume_leveling.dart`).
 */
class VolumeLevelingBridge(val messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    init {
        MethodChannel(messenger, "music_database_app/volume_leveling").setMethodCallHandler(this)
    }

    /** By audio session id; kept with the engine, so they go on while the app is in the background. */
    private val effects = mutableMapOf<Int, AudioEffect>()

    /** One file at a time, at background priority, so music and the screen go first. */
    private val measuring = Executors.newSingleThreadExecutor { task ->
        Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            task.run()
        }, "LoudnessMeter")
    }
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supported())
            "apply" -> {
                val session = call.argument<Int>("session")!!
                val gainDb = call.argument<Double>("gainDb")!!.toFloat()
                if (!supported()) {
                    result.error("unsupported", "DynamicsProcessing not available", null)
                    return
                }
                try {
                    apply(session, gainDb)
                    result.success(null)
                } catch (e: Exception) {
                    release(session)
                    result.error("failed", e.toString(), null)
                }
            }
            "measure" -> {
                val path = call.argument<String>("path")!!
                measuring.execute {
                    try {
                        val r = LoudnessMeter.measure(path)
                        val answer = mapOf(
                            "lufs" to r.lufs,
                            "peakDb" to r.peakDb,
                            "durationMs" to r.durationMs,
                        )
                        main.post { result.success(answer) }
                    } catch (e: Exception) {
                        main.post { result.error("failed", e.toString(), null) }
                    }
                }
            }
            "release" -> {
                release(call.argument<Int>("session")!!)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun supported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            AudioEffect.queryEffects().orEmpty().any {
                it.type == AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING
            }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun apply(session: Int, gainDb: Float) {
        val effect = effects[session] as DynamicsProcessing? ?: DynamicsProcessing(
            0,
            session,
            DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNELS,
                false, 0,
                false, 0,
                false, 0,
                true,
            ).build(),
        ).also {
            it.setLimiterAllChannelsTo(
                DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1f, 0f),
            )
            effects[session] = it
        }
        effect.setInputGainAllChannelsTo(gainDb)
        effect.enabled = true
    }

    private fun release(session: Int) {
        effects.remove(session)?.release()
    }

    private companion object {
        const val CHANNELS = 2
    }
}
