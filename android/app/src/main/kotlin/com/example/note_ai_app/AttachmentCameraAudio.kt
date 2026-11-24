package com.example.note_ai_app

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

/** Bounded AMR -> AAC-LC conversion. H264 frames are never decoded or changed. */
internal object AttachmentCameraAudio {
    fun transcode(source: File, track: Int, format: MediaFormat, output: File, guard: () -> Unit) {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        try {
            val decoding = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!).also {decoder = it}
            val encoding = MediaCodec.createEncoderByType("audio/mp4a-latm").also {encoder = it}
            val writing = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also {muxer = it}
            extractor.setDataSource(source.path); extractor.selectTrack(track)
            decoding.configure(format, null, null, 0); decoding.start()
            val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            require(rate in setOf(8000, 16000) && channels == 1)
            val aac = MediaFormat.createAudioFormat("audio/mp4a-latm", rate, channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 32000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }
            encoding.configure(aac, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); encoding.start()
            Pump(extractor, decoding, encoding, writing, output, rate, channels, guard).run()
        } finally {
            runCatching {decoder?.stop()}; runCatching {decoder?.release()}
            runCatching {encoder?.stop()}; runCatching {encoder?.release()}
            runCatching {muxer?.release()}; extractor.release()
        }
    }

    private class Pump(val source: MediaExtractor, val decoder: MediaCodec, val encoder: MediaCodec,
        val muxer: MediaMuxer, val output: File, val rate: Int, val channels: Int, val guard: () -> Unit) {
        private var sourceEnded = false
        private var decoderEnded = false
        private var encoderEnded = false
        private var decoded = -1
        private var audioTrack = -1
        private val decodedInfo = MediaCodec.BufferInfo()
        private val encodedInfo = MediaCodec.BufferInfo()

        fun run() {
            try {
                while (!encoderEnded) {
                    guard(); require(output.length() <= AttachmentCameraVideos.MAX_BYTES)
                    feedDecoder(); feedEncoder(); drainEncoder()
                }
                check(audioTrack >= 0); muxer.stop(); audioTrack = -1
            } finally {if (audioTrack >= 0) runCatching {muxer.stop()}}
        }

        private fun feedDecoder() {
            if (sourceEnded) return
            val index = decoder.dequeueInputBuffer(0)
            if (index < 0) return
            val buffer = decoder.getInputBuffer(index)!!; buffer.clear()
            val size = source.readSampleData(buffer, 0)
            if (size < 0) {
                decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                sourceEnded = true
            } else {
                decoder.queueInputBuffer(index, 0, size, source.sampleTime, 0)
                source.advance()
            }
        }

        private fun feedEncoder() {
            if (decoderEnded) return
            if (decoded < 0) decoded = decoder.dequeueOutputBuffer(decodedInfo, 0)
            if (decoded == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val pcm = decoder.outputFormat
                check(pcm.getInteger(MediaFormat.KEY_SAMPLE_RATE) == rate && pcm.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == channels)
                if (pcm.containsKey(MediaFormat.KEY_PCM_ENCODING)) check(pcm.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT)
            }
            if (decoded < 0) return
            val index = encoder.dequeueInputBuffer(0)
            if (index < 0) return
            val input = encoder.getInputBuffer(index)!!; input.clear()
            if (decodedInfo.size > 0) {
                val pcm = decoder.getOutputBuffer(decoded)!!
                pcm.position(decodedInfo.offset); pcm.limit(decodedInfo.offset + decodedInfo.size)
                require(pcm.remaining() <= input.remaining()); input.put(pcm)
            }
            decoderEnded = decodedInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            encoder.queueInputBuffer(index, 0, decodedInfo.size, decodedInfo.presentationTimeUs,
                if (decoderEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
            decoder.releaseOutputBuffer(decoded, false); decoded = -1
        }

        private fun drainEncoder() {
            val index = encoder.dequeueOutputBuffer(encodedInfo, 10_000)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                check(audioTrack < 0); audioTrack = muxer.addTrack(encoder.outputFormat); muxer.start()
            } else if (index >= 0) {
                try {
                    if (encodedInfo.size > 0 && encodedInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        check(audioTrack >= 0)
                        val buffer = encoder.getOutputBuffer(index)!!
                        buffer.position(encodedInfo.offset); buffer.limit(encodedInfo.offset + encodedInfo.size)
                        muxer.writeSampleData(audioTrack, buffer, encodedInfo)
                    }
                    encoderEnded = encodedInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                } finally {encoder.releaseOutputBuffer(index, false)}
            }
        }
    }
}
