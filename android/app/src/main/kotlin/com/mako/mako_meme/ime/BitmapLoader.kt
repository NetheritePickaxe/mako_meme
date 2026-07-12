package com.mako.mako_meme.ime

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import java.io.File
import java.util.concurrent.Executors

/**
 * 图片异步加载工具（单例）。
 *
 * - 仅使用 Android 原生 API（[BitmapFactory] + [LruCache]），不依赖任何第三方图片库。
 * - 内存缓存上限为进程可用内存的 1/8。
 * - 用固定 2 线程的线程池异步解码，解码时通过 [BitmapFactory.Options.inSampleSize] 降采样。
 * - ImageView 用 tag 记录当前请求的 path，列表滚动时若 path 不匹配则丢弃旧结果，避免错位。
 */
object BitmapLoader {

    private const val TAG_KEY_PATH = 0x7f0e0001

    /** 进程可用内存（KB）。 */
    private val maxMemoryKb: Int = (Runtime.getRuntime().maxMemory() / 1024).toInt()

    /** 缓存大小：最大可用内存的 1/8。 */
    private val cacheSizeKb: Int = maxMemoryKb / 8

    private val memoryCache: LruCache<String, Bitmap> = object : LruCache<String, Bitmap>(cacheSizeKb) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }

    /** 固定 2 线程的解码线程池。 */
    private val executor = Executors.newFixedThreadPool(2)

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 异步加载 [path] 指向的图片到 [imageView]，目标尺寸 [targetSize]（px，正方形）。
     * 命中缓存时直接在主线程设置；否则后台解码后回到主线程设置。
     */
    fun load(path: String, imageView: ImageView, targetSize: Int) {
        // 用 tag 记录当前请求的 path，用于滚动时校验
        imageView.setTag(TAG_KEY_PATH, path)

        // 先查内存缓存
        memoryCache.get(path)?.let { bmp ->
            if (isSameRequest(imageView, path)) {
                imageView.setImageBitmap(bmp)
            }
            return
        }

        // 占位
        imageView.setImageDrawable(null)

        executor.execute {
            val bitmap = decodeSampledBitmap(path, targetSize, targetSize) ?: return@execute
            memoryCache.put(path, bitmap)
            mainHandler.post {
                if (isSameRequest(imageView, path)) {
                    imageView.setImageBitmap(bitmap)
                }
            }
        }
    }

    /** 当前 ImageView 的 tag 是否仍指向 [path]（即未被复用给新请求）。 */
    private fun isSameRequest(imageView: ImageView, path: String): Boolean =
        imageView.getTag(TAG_KEY_PATH) == path

    /**
     * 解码图片并按需降采样。
     * 第一次只读尺寸（inJustDecodeBounds=true），计算 inSampleSize 后再真正解码。
     */
    private fun decodeSampledBitmap(path: String, reqWidth: Int, reqHeight: Int): Bitmap? {
        if (!File(path).exists()) return null

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)

        val sampleSize = calculateInSampleSize(bounds, reqWidth, reqHeight)

        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565 // 减少内存占用
        }
        return runCatching { BitmapFactory.decodeFile(path, opts) }.getOrNull()
    }

    /**
     * 计算 inSampleSize：保证降采样后宽高均不小于目标尺寸。
     */
    private fun calculateInSampleSize(
        options: BitmapFactory.Options,
        reqWidth: Int,
        reqHeight: Int
    ): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    /** 清空内存缓存。 */
    fun clearCache() {
        memoryCache.evictAll()
    }
}
