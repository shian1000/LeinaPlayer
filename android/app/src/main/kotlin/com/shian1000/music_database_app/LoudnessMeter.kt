package com.shian1000.music_database_app

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.tan

/**
 * A file's integrated loudness (EBU R128 / ITU-R BS.1770: K-weighting, 400 ms blocks every
 * 100 ms, gated at −70 LUFS and 10 LU below the ungated mean), sample peak and length — for
 * "Wyrównywanie głośności" (`lib/src/playback/loudness_measurer.dart`). Decodes with the
 * phone's own MediaCodec, so it reads whatever the player plays (mp3, m4a, webm/opus, flac).
 */
object LoudnessMeter {
    class Result(val lufs: Double?, val peakDb: Double?, val durationMs: Long)

    fun measure(path: String): Result {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("no audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            try {
                codec.configure(format, null, null, 0)
                codec.start()
                return decode(extractor, codec, format)
            } finally {
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun decode(extractor: MediaExtractor, codec: MediaCodec, input: MediaFormat): Result {
        var meter: Meter? = null
        var float = false
        // Read in bulk, not a call per sample.
        var shorts = ShortArray(0)
        var floats = FloatArray(0)
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var waitUs = 0L
        while (true) {
            // Feed every free input buffer and take every ready output without waiting; only
            // when no output is ready, wait for the decoder.
            while (!inputDone) {
                val index = codec.dequeueInputBuffer(0)
                if (index < 0) break
                val size = extractor.readSampleData(codec.getInputBuffer(index)!!, 0)
                if (size < 0) {
                    codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    inputDone = true
                } else {
                    codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                    extractor.advance()
                }
            }
            val out = codec.dequeueOutputBuffer(info, waitUs)
            waitUs = if (out == MediaCodec.INFO_TRY_AGAIN_LATER) TIMEOUT_US else 0L
            when {
                out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val f = codec.outputFormat
                    float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    meter = Meter(
                        f.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                        f.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                    )
                }
                out >= 0 -> {
                    val m = meter ?: Meter(
                        input.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                        input.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                    ).also { meter = it }
                    val buffer = codec.getOutputBuffer(out)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val ordered = buffer.order(ByteOrder.nativeOrder())
                    val count = if (float) info.size / 4 else info.size / 2
                    if (floats.size < count) floats = FloatArray(count)
                    if (float) {
                        ordered.asFloatBuffer().get(floats, 0, count)
                    } else {
                        if (shorts.size < count) shorts = ShortArray(count)
                        ordered.asShortBuffer().get(shorts, 0, count)
                        for (i in 0 until count) floats[i] = shorts[i] / 32768f
                    }
                    m.add(floats, count)
                    codec.releaseOutputBuffer(out, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        }
        val m = meter ?: throw IllegalStateException("no audio decoded")
        return m.result()
    }

    private const val TIMEOUT_US = 10_000L

    /** BS.1770's two K-weighting stages and block gating, fed interleaved samples. */
    private class Meter(private val rate: Int, private val channels: Int) {
        private val pre = Biquad.shelf(rate)
        private val rlb = Biquad.highPass(rate)

        // Only the front channels count; an LFE or surround would need weights of its own.
        private val weighted = minOf(channels, 2)

        // Each filter's x1, x2, y1, y2 per channel; copied into locals for each run of samples,
        // as array and field access in the inner loop made it several times slower.
        private val state = DoubleArray(8 * weighted)
        private val subBlock = rate / 10
        private val subBlocks = ArrayList<Double>()
        private var sum = 0.0
        private var inSubBlock = 0
        private var frames = 0L
        private var peak = 0.0

        /** [count] interleaved samples of [samples]; always whole frames. */
        fun add(samples: FloatArray, count: Int) {
            var p = peak
            for (i in 0 until count) {
                val a = samples[i]
                if (a > p) p = a.toDouble() else if (-a > p) p = -a.toDouble()
            }
            peak = p
            val total = count / channels
            var done = 0
            while (done < total) {
                val n = minOf(total - done, subBlock - inSubBlock)
                for (c in 0 until weighted) {
                    sum += filtered(samples, done * channels + c, n, 8 * c)
                }
                done += n
                frames += n
                inSubBlock += n
                if (inSubBlock == subBlock) {
                    subBlocks.add(sum / subBlock)
                    sum = 0.0
                    inSubBlock = 0
                }
            }
        }

        /** The K-weighted energy of [n] samples of one channel, from [from], [channels] apart. */
        private fun filtered(samples: FloatArray, from: Int, n: Int, at: Int): Double {
            val s = state
            var px1 = s[at]; var px2 = s[at + 1]; var py1 = s[at + 2]; var py2 = s[at + 3]
            var rx1 = s[at + 4]; var rx2 = s[at + 5]; var ry1 = s[at + 6]; var ry2 = s[at + 7]
            val pb0 = pre.b0; val pb1 = pre.b1; val pb2 = pre.b2; val pa1 = pre.a1; val pa2 = pre.a2
            val rb0 = rlb.b0; val rb1 = rlb.b1; val rb2 = rlb.b2; val ra1 = rlb.a1; val ra2 = rlb.a2
            var energy = 0.0
            var i = from
            repeat(n) {
                val x = samples[i].toDouble()
                val y = pb0 * x + pb1 * px1 + pb2 * px2 - pa1 * py1 - pa2 * py2
                px2 = px1; px1 = x; py2 = py1; py1 = y
                val k = rb0 * y + rb1 * rx1 + rb2 * rx2 - ra1 * ry1 - ra2 * ry2
                rx2 = rx1; rx1 = y; ry2 = ry1; ry1 = k
                energy += k * k
                i += channels
            }
            s[at] = px1; s[at + 1] = px2; s[at + 2] = py1; s[at + 3] = py2
            s[at + 4] = rx1; s[at + 5] = rx2; s[at + 6] = ry1; s[at + 7] = ry2
            return energy
        }

        fun result(): Result {
            val blocks = (0..subBlocks.size - 4).map { i ->
                (subBlocks[i] + subBlocks[i + 1] + subBlocks[i + 2] + subBlocks[i + 3]) / 4
            }
            val loud = blocks.filter { loudness(it) > -70.0 }
            val lufs = if (loud.isEmpty()) {
                null
            } else {
                val gate = loudness(loud.average()) - 10.0
                loud.filter { loudness(it) > gate }.takeIf { it.isNotEmpty() }
                    ?.let { loudness(it.average()) }
            }
            return Result(
                lufs,
                if (peak > 0) 20 * log10(peak) else null,
                frames * 1000 / rate,
            )
        }

        private fun loudness(power: Double) = -0.691 + 10 * log10(power)
    }

    private class Biquad(
        val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double,
    ) {
        companion object {
            // BS.1770's filters re-derived for any sample rate, as libebur128 does.
            fun shelf(rate: Int): Biquad {
                val k = tan(PI * 1681.974450955533 / rate)
                val q = 0.7071752369554196
                val vh = 10.0.pow(3.999843853973347 / 20)
                val vb = vh.pow(0.4996667741545416)
                val a0 = 1 + k / q + k * k
                return Biquad(
                    (vh + vb * k / q + k * k) / a0,
                    2 * (k * k - vh) / a0,
                    (vh - vb * k / q + k * k) / a0,
                    2 * (k * k - 1) / a0,
                    (1 - k / q + k * k) / a0,
                )
            }

            fun highPass(rate: Int): Biquad {
                val k = tan(PI * 38.13547087602444 / rate)
                val q = 0.5003270373238773
                val a0 = 1 + k / q + k * k
                return Biquad(1.0, -2.0, 1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
            }
        }
    }
}
