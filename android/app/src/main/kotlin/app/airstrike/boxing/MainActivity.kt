package app.airstrike.boxing

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.SoundPool
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener, EventChannel.StreamHandler {
    private val sensors by lazy { getSystemService(Context.SENSOR_SERVICE) as SensorManager }
    private val prefs by lazy { getSharedPreferences("skyglide", Context.MODE_PRIVATE) }
    private var events: EventChannel.EventSink? = null
    private var audio: SoundPool? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val pool = SoundPool.Builder().setMaxStreams(3).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        ).build()
        audio = pool
        val cues = mapOf("pass" to pool.load(this, R.raw.pass, 1),
            "feather" to pool.load(this, R.raw.feather, 1), "stop" to pool.load(this, R.raw.landing, 1),
            "shield" to pool.load(this, R.raw.shield, 1), "shatter" to pool.load(this, R.raw.shatter, 1),
            "chapter" to pool.load(this, R.raw.chapter, 1))
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "skyglide/tilt").setStreamHandler(this)
        MethodChannel(messenger, "skyglide/game").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(mapOf("best" to prefs.getInt("best", 0), "sound" to prefs.getBoolean("sound", true),
                    "featherBalance" to prefs.getInt("featherBalance", 0)))
                "featherBalance" -> {
                    prefs.edit().putInt("featherBalance", (call.arguments as Number).toInt()).apply()
                    result.success(null)
                }
                "best" -> {
                    prefs.edit().putInt("best", maxOf(prefs.getInt("best", 0), (call.arguments as Number).toInt())).apply()
                    result.success(null)
                }
                "sound" -> {
                    prefs.edit().putBoolean("sound", call.arguments as Boolean).apply()
                    result.success(null)
                }
                "cue" -> {
                    cues[call.arguments as String]?.let { pool.play(it, .65f, .65f, 1, 0, 1f) }
                    result.success(null)
                }
                "awake" -> {
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        onCancel(null)
        events = sink
        for (type in intArrayOf(Sensor.TYPE_GRAVITY, Sensor.TYPE_ACCELEROMETER)) {
            val sensor = sensors.getDefaultSensor(type) ?: continue
            if (sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)) return
        }
        sink.error("unavailable", "Tilt sensor unavailable", null)
    }

    override fun onSensorChanged(event: SensorEvent) {
        events?.success(listOf(event.timestamp / 1_000_000L,
            event.values[1].toDouble(), event.values[2].toDouble()))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        events = null
    }
    override fun onStop() {
        onCancel(null)
        super.onStop()
    }
    override fun onDestroy() {
        onCancel(null)
        audio?.release()
        super.onDestroy()
    }
}
