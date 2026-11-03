package com.shian1000.music_database_app

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import de.sciss.jump3r.mp3.BitStream
import de.sciss.jump3r.mp3.GainAnalysis
import de.sciss.jump3r.mp3.ID3Tag
import de.sciss.jump3r.mp3.Lame
import de.sciss.jump3r.mp3.LameGlobalFlags
import de.sciss.jump3r.mp3.Parse
import de.sciss.jump3r.mp3.Presets
import de.sciss.jump3r.mp3.Quantize
import de.sciss.jump3r.mp3.QuantizePVT
import de.sciss.jump3r.mp3.Reservoir
import de.sciss.jump3r.mp3.Takehiro
import de.sciss.jump3r.mp3.VBRTag
import de.sciss.jump3r.mp3.Version
import de.sciss.jump3r.mpg.Common
import de.sciss.jump3r.mpg.Interface
import de.sciss.jump3r.mpg.MPGLib
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.ByteOrder

/**
 * A downloaded song re-encoded as MP3 ("Pobieraj jako MP3", `lib/src/data/mp3_conversion.dart`):
 * decoded with the phone's own MediaCodec (whatever the player plays — webm/opus, m4a, flac…),
 * encoded with jump3r (LAME in Java, LGPL — no native build) at a constant bitrate, with an
 * ID3v2.3 tag of music.db's names, year, genre and the album cover, so other music apps list it
 * properly.
 */
object Mp3Encoder {
    class Tags(
        val title: String?,
        val artist: String?,
        val album: String?,
        val year: String?,
        val genre: String?,
        val cover: ByteArray?,
    )

    fun convert(from: String, to: String, kbps: Int, tags: Tags) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(from)
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
                BufferedOutputStream(FileOutputStream(to)).use { out ->
                    out.write(id3v2(tags))
                    encode(extractor, codec, format, kbps, out)
                }
            } finally {
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun encode(
        extractor: MediaExtractor,
        codec: MediaCodec,
        input: MediaFormat,
        kbps: Int,
        out: OutputStream,
    ) {
        var encoder: Encoder? = null
        var pcm = AudioFormat.ENCODING_PCM_16BIT
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var waitUs = 0L
        while (true) {
            // As in LoudnessMeter: feed every free input buffer, wait only when no output is ready.
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
            val index = codec.dequeueOutputBuffer(info, waitUs)
            waitUs = if (index == MediaCodec.INFO_TRY_AGAIN_LATER) TIMEOUT_US else 0L
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val f = codec.outputFormat
                    if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        pcm = f.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    }
                    if (encoder == null) {
                        encoder = Encoder(
                            f.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                            f.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                            kbps,
                        )
                    }
                }
                index >= 0 -> {
                    val e = encoder ?: Encoder(
                        input.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                        input.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                        kbps,
                    ).also { encoder = it }
                    val buffer = codec.getOutputBuffer(index)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    e.add(buffer.order(ByteOrder.nativeOrder()), pcm, out)
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        }
        (encoder ?: throw IllegalStateException("no audio decoded")).finish(out)
    }

    private const val TIMEOUT_US = 10_000L

    /** LAME wired up as jump3r's own `LameEncoder` does it (that one needs javax.sound). */
    private class Encoder(rate: Int, private val inChannels: Int, kbps: Int) {
        private val lame = Lame()
        private val flags: LameGlobalFlags
        private val channels = minOf(inChannels, 2)
        private var left = IntArray(0)
        private var right = IntArray(0)
        private var mp3 = ByteArray(0)

        init {
            val ga = GainAnalysis()
            val bs = BitStream()
            val p = Presets()
            val qupvt = QuantizePVT()
            val qu = Quantize()
            val vbr = VBRTag()
            val ver = Version()
            val id3 = ID3Tag()
            val rv = Reservoir()
            val tak = Takehiro()
            val parse = Parse()
            val mpg = MPGLib()
            val intf = Interface()
            val common = Common()
            lame.setModules(ga, bs, p, qupvt, qu, vbr, ver, id3, mpg)
            bs.setModules(ga, mpg, ver, vbr)
            id3.setModules(bs, ver)
            p.setModules(lame)
            qu.setModules(bs, rv, qupvt, tak)
            qupvt.setModules(tak, rv, lame.enc.psy)
            rv.setModules(bs)
            tak.setModules(qupvt)
            vbr.setModules(lame, bs, ver)
            parse.setModules(ver, id3, p)
            mpg.setModules(intf, common)
            intf.setModules(vbr, common)
            flags = lame.lame_init()
            flags.num_channels = channels
            flags.in_samplerate = rate
            flags.brate = kbps
            // At 256 kbps a slower psychoacoustic search isn't heard, and jump3r is slow enough.
            flags.quality = 5
            // Streamed out, never rewritten: no Xing frame, and the ID3 tag is ours.
            flags.bWriteVbrTag = false
            flags.write_id3tag_automatic = false
            id3.id3tag_init(flags)
            val rc = lame.lame_init_params(flags)
            if (rc < 0) throw IllegalArgumentException("LAME refused $rate Hz, $inChannels ch ($rc)")
        }

        /** One decoded buffer of interleaved samples in [pcm] encoding. */
        fun add(buffer: java.nio.ByteBuffer, pcm: Int, out: OutputStream) {
            val bytes = when (pcm) {
                AudioFormat.ENCODING_PCM_FLOAT, AudioFormat.ENCODING_PCM_32BIT -> 4
                AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
                AudioFormat.ENCODING_PCM_8BIT -> 1
                else -> 2
            }
            val frames = buffer.remaining() / bytes / inChannels
            if (frames == 0) return
            if (left.size < frames) {
                left = IntArray(frames)
                right = IntArray(frames)
                mp3 = ByteArray(frames * 5 / 4 + 7200)
            }
            for (i in 0 until frames) {
                for (c in 0 until inChannels) {
                    val s = when (pcm) {
                        AudioFormat.ENCODING_PCM_FLOAT ->
                            (buffer.float.coerceIn(-1f, 1f) * Int.MAX_VALUE).toInt()
                        AudioFormat.ENCODING_PCM_32BIT -> buffer.int
                        AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                            val b0 = buffer.get().toInt() and 0xff
                            val b1 = buffer.get().toInt() and 0xff
                            val b2 = buffer.get().toInt()
                            (b0 shl 8) or (b1 shl 16) or (b2 shl 24)
                        }
                        AudioFormat.ENCODING_PCM_8BIT -> ((buffer.get().toInt() and 0xff) - 128) shl 24
                        else -> buffer.short.toInt() shl 16
                    }
                    // Only the front pair is kept of anything wider than stereo.
                    when (c) {
                        0 -> left[i] = s
                        1 -> right[i] = s
                    }
                }
            }
            val n = lame.lame_encode_buffer_int(
                flags, left, if (channels == 2) right else left, frames, mp3, 0, mp3.size,
            )
            if (n < 0) throw IllegalStateException("LAME failed ($n)")
            out.write(mp3, 0, n)
        }

        fun finish(out: OutputStream) {
            val tail = ByteArray(7200)
            val n = lame.lame_encode_flush(flags, tail, 0, tail.size)
            if (n > 0) out.write(tail, 0, n)
            lame.lame_close(flags)
        }
    }

    /** An ID3v2.3 tag with what's given (text in UTF-16, as v2.3 has no UTF-8). */
    private fun id3v2(tags: Tags): ByteArray {
        val frames = ByteArrayOutputStream()
        fun frame(id: String, data: ByteArray) {
            frames.write(id.toByteArray(Charsets.US_ASCII))
            frames.write(int32(data.size))
            frames.write(byteArrayOf(0, 0))
            frames.write(data)
        }
        for ((id, value) in listOf(
            "TIT2" to tags.title,
            "TPE1" to tags.artist,
            "TALB" to tags.album,
            "TYER" to tags.year,
            "TCON" to tags.genre,
        )) {
            if (value.isNullOrBlank()) continue
            frame(id, byteArrayOf(1, 0xff.toByte(), 0xfe.toByte()) + value.toByteArray(Charsets.UTF_16LE))
        }
        tags.cover?.let { image ->
            val png = image.size > 4 && image[0] == 0x89.toByte() && image[1] == 'P'.code.toByte()
            val mime = if (png) "image/png" else "image/jpeg"
            // Latin-1 text, the MIME type, picture type 3 (front cover), an empty description.
            frame("APIC", byteArrayOf(0) + mime.toByteArray(Charsets.US_ASCII) + byteArrayOf(0, 3, 0) + image)
        }
        val body = frames.toByteArray()
        if (body.isEmpty()) return body
        val size = body.size
        val header = byteArrayOf(
            'I'.code.toByte(), 'D'.code.toByte(), '3'.code.toByte(), 3, 0, 0,
            (size shr 21 and 0x7f).toByte(), (size shr 14 and 0x7f).toByte(),
            (size shr 7 and 0x7f).toByte(), (size and 0x7f).toByte(),
        )
        return header + body
    }

    private fun int32(v: Int) =
        byteArrayOf((v shr 24).toByte(), (v shr 16).toByte(), (v shr 8).toByte(), v.toByte())
}
