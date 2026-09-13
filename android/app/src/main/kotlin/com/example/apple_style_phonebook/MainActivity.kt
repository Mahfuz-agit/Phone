package com.example.apple_style_phonebook

import android.media.MediaExtractor
import android.media.MediaMuxer
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/**
 * Hosts a MethodChannel that trims an m4a/AAC file at the container
 * level (MediaExtractor -> MediaMuxer), copying only the samples
 * between startMs and endMs. No re-encoding, no third-party FFmpeg
 * binary — ffmpeg_kit_flutter was retired in April 2025.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "phonebook/audio_trim"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "trim") {
                    try {
                        val sourcePath = call.argument<String>("sourcePath")!!
                        val outputPath = call.argument<String>("outputPath")!!
                        val startMs = call.argument<Int>("startMs")!!.toLong()
                        val endMs = call.argument<Int>("endMs")!!.toLong()

                        trimAudio(sourcePath, outputPath, startMs, endMs)
                        result.success(outputPath)
                    } catch (e: Exception) {
                        result.error("TRIM_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun trimAudio(sourcePath: String, outputPath: String, startMs: Long, endMs: Long) {
        val extractor = MediaExtractor()
        extractor.setDataSource(sourcePath)

        var audioTrackIndex = -1
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                break
            }
        }
        require(audioTrackIndex >= 0) { "No audio track found in $sourcePath" }

        extractor.selectTrack(audioTrackIndex)
        val format = extractor.getTrackFormat(audioTrackIndex)

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val outTrackIndex = muxer.addTrack(format)
        muxer.start()

        val startUs = startMs * 1000
        val endUs = endMs * 1000
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

        val bufferSize = 1 shl 20 // 1 MB, generous for voice AAC
        val buffer = ByteBuffer.allocate(bufferSize)
        val bufferInfo = android.media.MediaCodec.BufferInfo()

        while (true) {
            val sampleTimeUs = extractor.sampleTime
            if (sampleTimeUs < 0 || sampleTimeUs > endUs) break

            buffer.clear()
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break

            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            // Normalize timestamps so the trimmed file starts at 0.
            bufferInfo.presentationTimeUs = sampleTimeUs - startUs
            bufferInfo.flags = extractor.sampleFlags

            muxer.writeSampleData(outTrackIndex, buffer, bufferInfo)
            extractor.advance()
        }

        muxer.stop()
        muxer.release()
        extractor.release()
    }
}
