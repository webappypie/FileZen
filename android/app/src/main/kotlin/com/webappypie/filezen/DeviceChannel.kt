package com.webappypie.filezen

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Device facts FileZen cannot get from dart:io:
 *  - `storageStats`: real total/available bytes of the shared-storage volume (StatFs).
 *  - `deviceConditions`: battery / power-saver / thermal state, used to defer OCR.
 *  - `videoThumbnail`: one scaled video frame written as a small JPEG (never decodes the
 *    whole video; the platform extracts a single key frame).
 */
class DeviceChannel(private val context: Context) {
    // Bounded: at most two frame extractions at a time, off the UI thread.
    private val mediaExecutor: ExecutorService = Executors.newFixedThreadPool(2)

    fun shutdown() = mediaExecutor.shutdown()

    fun handle(call: MethodCall, result: MethodChannel.Result, post: (Runnable) -> Unit) {
        when (call.method) {
            "storageStats" -> {
                try {
                    val path = Environment.getExternalStorageDirectory().absolutePath
                    val stat = StatFs(path)
                    result.success(
                        mapOf(
                            "path" to path,
                            "totalBytes" to stat.totalBytes,
                            "availableBytes" to stat.availableBytes,
                        ),
                    )
                } catch (e: Exception) {
                    result.error("STORAGE_STATS_FAILED", e.message, null)
                }
            }
            "videoThumbnail" -> {
                val source = call.argument<String>("path")
                val outPath = call.argument<String>("outPath")
                val maxSize = call.argument<Int>("maxSize") ?: 256
                if (source == null || outPath == null) {
                    result.error("BAD_ARGUMENT", "path and outPath are required", null)
                    return
                }
                mediaExecutor.execute {
                    val written = try {
                        writeVideoThumbnail(source, outPath, maxSize)
                    } catch (e: Exception) {
                        false
                    }
                    post(Runnable { result.success(if (written) outPath else null) })
                }
            }
            "deviceConditions" -> {
                try {
                    val battery = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        power.currentThermalStatus
                    } else {
                        0
                    }
                    result.success(
                        mapOf(
                            "batteryPercent" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                            "charging" to battery.isCharging,
                            "powerSave" to power.isPowerSaveMode,
                            "thermalStatus" to thermal,
                        ),
                    )
                } catch (e: Exception) {
                    result.error("CONDITIONS_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun writeVideoThumbnail(source: String, outPath: String, maxSize: Int): Boolean {
        val bitmap = extractFrame(source, maxSize) ?: return false
        try {
            val out = File(outPath)
            out.parentFile?.mkdirs()
            val tmp = File("$outPath.tmp")
            FileOutputStream(tmp).use { stream ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)) return false
            }
            return tmp.renameTo(out)
        } finally {
            bitmap.recycle()
        }
    }

    private fun extractFrame(source: String, maxSize: Int): Bitmap? {
        val isContentUri = source.startsWith("content://")
        if (!isContentUri && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                ThumbnailUtils.createVideoThumbnail(File(source), Size(maxSize, maxSize), null)
            } catch (e: Exception) {
                retrieverFrame(source, false, maxSize)
            }
        }
        return retrieverFrame(source, isContentUri, maxSize)
    }

    private fun retrieverFrame(source: String, isContentUri: Boolean, maxSize: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        try {
            if (isContentUri) {
                retriever.setDataSource(context, Uri.parse(source))
            } else {
                retriever.setDataSource(source)
            }
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    -1,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    maxSize,
                    maxSize,
                )
            } else {
                retriever.frameAtTime
            } ?: return null
            return scaleDown(frame, maxSize)
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun scaleDown(frame: Bitmap, maxSize: Int): Bitmap {
        val longest = maxOf(frame.width, frame.height)
        if (longest <= maxSize) return frame
        val scale = maxSize.toFloat() / longest
        val scaled = Bitmap.createScaledBitmap(
            frame,
            (frame.width * scale).toInt().coerceAtLeast(1),
            (frame.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled != frame) frame.recycle()
        return scaled
    }

    companion object {
        const val CHANNEL = "com.webappypie.filezen/device"
    }
}
