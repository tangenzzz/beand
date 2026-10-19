package app.beand

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

// Saliency mask for cutting gear photos out (lib/services/gear_cutout.dart):
// U²-Net small (assets/models/u2netp_fp16.tflite) on the standalone LiteRT
// runtime, on the device, without Google Play services (GrapheneOS has
// none). Returns only the mask; cropping and grading happen in Dart, the
// same for Android and iOS.
object Cutout {
    private const val SIZE = 320
    private const val MODEL = "assets/models/u2netp_fp16.tflite"

    // The first (finest) of U²-Net's side outputs; the converter names it
    // "Identity".
    private const val OUTPUT = "Identity"
    private val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val std = floatArrayOf(0.229f, 0.224f, 0.225f)

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var interpreter: Interpreter? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "beand/cutout").setMethodCallHandler { call, result ->
            when (call.method) {
                "mask" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("args", "path missing", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        try {
                            val mask = mask(context, path)
                            main.post {
                                result.success(
                                    mapOf("width" to SIZE, "height" to SIZE, "mask" to mask),
                                )
                            }
                        } catch (e: Throwable) {
                            main.post { result.error("cutout", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun interpreter(context: Context): Interpreter {
        interpreter?.let { return it }
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(MODEL)
        val bytes = context.assets.open(key).use { it.readBytes() }
        val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        model.put(bytes).rewind()
        return Interpreter(model, Interpreter.Options().setNumThreads(4))
            .also { interpreter = it }
    }

    // 320×320 grayscale mask, 0–255, scaled to its own min..max (as rembg).
    private fun mask(context: Context, path: String): ByteArray {
        val source = BitmapFactory.decodeFile(path) ?: error("Could not read image")
        val bitmap = Bitmap.createScaledBitmap(source, SIZE, SIZE, true)
        val pixels = IntArray(SIZE * SIZE)
        bitmap.getPixels(pixels, 0, SIZE, 0, 0, SIZE, SIZE)
        var max = 1e-6f
        for (p in pixels) {
            max = maxOf(
                max,
                ((p shr 16) and 0xFF) / 255f,
                ((p shr 8) and 0xFF) / 255f,
                (p and 0xFF) / 255f,
            )
        }
        // NHWC float input.
        val input = ByteBuffer.allocateDirect(4 * 3 * SIZE * SIZE).order(ByteOrder.nativeOrder())
        for (p in pixels) {
            val rgb = floatArrayOf(
                ((p shr 16) and 0xFF) / 255f,
                ((p shr 8) and 0xFF) / 255f,
                (p and 0xFF) / 255f,
            )
            for (c in 0..2) input.putFloat((rgb[c] / max - mean[c]) / std[c])
        }
        input.rewind()

        val tflite = interpreter(context)
        val index = (0 until tflite.outputTensorCount)
            .firstOrNull { tflite.getOutputTensor(it).name() == OUTPUT } ?: 0
        val output = ByteBuffer.allocateDirect(4 * SIZE * SIZE).order(ByteOrder.nativeOrder())
        tflite.runForMultipleInputsOutputs(arrayOf<Any>(input), mapOf<Int, Any>(index to output))
        output.rewind()
        val values = FloatArray(SIZE * SIZE) { output.float }
        var lo = Float.MAX_VALUE
        var hi = -Float.MAX_VALUE
        for (v in values) {
            lo = minOf(lo, v)
            hi = maxOf(hi, v)
        }
        val range = maxOf(hi - lo, 1e-6f)
        return ByteArray(values.size) { i ->
            (((values[i] - lo) / range) * 255f).toInt().coerceIn(0, 255).toByte()
        }
    }
}
