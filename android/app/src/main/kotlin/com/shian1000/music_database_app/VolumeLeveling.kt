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
import kotlin.math.max

/**
 * "Wyrównywanie głośności": Android's DynamicsProcessing on each player's audio session. A song
 * whose loudness is known gets a steady input gain (worked out in Dart, `recordings.dart`); any
 * other goes through a one-band compressor that brings loud and quiet songs closer. A limiter
 * after both keeps the gain from clipping. On the `music_database_app/volume_leveling` channel
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
                val strength = call.argument<Double>("strength")!!.toFloat()
                val gainDb = call.argument<Double>("gainDb")?.toFloat()
                if (!supported()) {
                    result.error("unsupported", "DynamicsProcessing not available", null)
                    return
                }
                try {
                    apply(session, strength, gainDb)
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
    private fun apply(session: Int, strength: Float, gainDb: Float?) {
        val effect = effects[session] as DynamicsProcessing? ?: DynamicsProcessing(
            0,
            session,
            DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNELS,
                false, 0,
                true, 1,
                false, 0,
                true,
            ).build(),
        ).also { effects[session] = it }
        // At full strength a master around -10 dB comes down ~15 dB and one around -22 dB only
        // ~6 dB, so a 12 dB gap shrinks to ~3 dB; the make-up gain then lifts both back up.
        val compress = if (gainDb == null) strength else 0f
        val threshold = -10f - 20f * compress
        val ratio = 1f + 3f * compress
        val makeUp = max(0f, (-10f - threshold) * (1f - 1f / ratio) - 4f)
        effect.setInputGainAllChannelsTo(gainDb ?: 0f)
        effect.setMbcBandAllChannelsTo(
            0,
            DynamicsProcessing.MbcBand(
                true, 20000f,
                // Slow enough to follow a song's loudness rather than each beat (no pumping).
                30f, 600f,
                ratio, threshold, 6f,
                -90f, 1f,
                0f, makeUp,
            ),
        )
        effect.setLimiterAllChannelsTo(
            DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1f, 0f),
        )
        effect.enabled = true
    }

    private fun release(session: Int) {
        effects.remove(session)?.release()
    }

    private companion object {
        const val CHANNELS = 2
    }
}
