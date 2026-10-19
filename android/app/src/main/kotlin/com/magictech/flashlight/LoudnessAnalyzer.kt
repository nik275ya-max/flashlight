package com.magictech.flashlight

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.sqrt

object LoudnessAnalyzer {
    private const val TAG = "LoudnessAnalyzer"
    private const val ANALYSIS_DURATION_US: Long = 60_000_000L

    fun analyze(path: String): Double? {
        return try {
            computeRmsDb(path)
        } catch (e: Exception) {
            Log.w(TAG, "analyze failed for $path", e)
            null
        }
    }

    private fun computeRmsDb(path: String): Double? {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (e: Exception) {
            extractor.release()
            return null
        }

        val audioTrack = selectAudioTrack(extractor)
        if (audioTrack < 0) {
            extractor.release()
            return null
        }
        extractor.selectTrack(audioTrack)
        val format = extractor.getTrackFormat(audioTrack)
        val mime = format.getString(MediaFormat.KEY_MIME)
        if (mime == null) {
            extractor.release()
            return null
        }

        val codec = try {
            val c = MediaCodec.createDecoderByType(mime)
            c.configure(format, null, null, 0)
            c.start()
            c
        } catch (e: Exception) {
            extractor.release()
            return null
        }

        try {
            val info = MediaCodec.BufferInfo()
            var sumSq = 0.0
            var sampleCount = 0L
            var sawInputEos = false
            var sawOutputEos = false

            while (!sawOutputEos) {
                if (!sawInputEos) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)
                        if (inBuf != null) {
                            inBuf.clear()
                            val sampleSize = extractor.readSampleData(inBuf, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(
                                    inIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                sawInputEos = true
                            } else {
                                val pts = extractor.getSampleTime()
                                if (pts > ANALYSIS_DURATION_US) {
                                    // Hit the duration cap: signal EOS so the
                                    // decoder drains and the loop can exit.
                                    codec.queueInputBuffer(
                                        inIndex, 0, 0, 0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                    )
                                    sawInputEos = true
                                } else {
                                    codec.queueInputBuffer(inIndex, 0, sampleSize, pts, 0)
                                    extractor.advance()
                                }
                            }
                        } else {
                            sawInputEos = true
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val outBuf = codec.getOutputBuffer(outIndex)
                    if (outBuf != null && info.size > 0) {
                        val pair = sumOfSquares(outBuf, info.size)
                        sumSq += pair.first
                        sampleCount += pair.second
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEos = true
                    }
                }
            }

            if (sampleCount == 0L) return null
            val rms = sqrt(sumSq / sampleCount)
            val normalized = (rms / 32768.0).coerceAtLeast(1e-7)
            return 20.0 * log10(normalized)
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            extractor.release()
        }
    }

    private fun selectAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val m = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (m.startsWith("audio/")) return i
        }
        return -1
    }

    private fun sumOfSquares(buf: ByteBuffer, size: Int): Pair<Double, Long> {
        val saved = buf.position()
        val end = saved + size
        buf.order(ByteOrder.LITTLE_ENDIAN)
        var sum = 0.0
        var count = 0L
        var i = saved
        while (i + 1 < end) {
            val sample = buf.getShort(i).toInt()
            sum += sample.toDouble() * sample.toDouble()
            count++
            i += 2
        }
        return Pair(sum, count)
    }
}
