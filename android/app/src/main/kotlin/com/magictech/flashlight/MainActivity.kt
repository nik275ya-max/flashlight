package com.magictech.flashlight

import android.content.Intent
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.magictech.flashlight/background"
    private val loudnessExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "loudness-analyzer") }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startBackgroundService()
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, MagnetForegroundService::class.java))
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        val keepOn = call.argument<Boolean>("keepOn") ?: true
                        runOnUiThread { applyKeepScreenOn(keepOn) }
                        result.success(null)
                    }
                    "analyzeLoudness" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_argument", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            loudnessExecutor.execute {
                                val rmsDb = LoudnessAnalyzer.analyze(path)
                                runOnUiThread { result.success(mapOf("rmsDb" to rmsDb)) }
                            }
                        } catch (e: Exception) {
                            // Executor rejected (e.g. shutting down): still
                            // reply so the Dart side never hangs.
                            result.success(mapOf("rmsDb" to null))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        loudnessExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun applyKeepScreenOn(keepOn: Boolean) {
        if (keepOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun startBackgroundService() {
        val intent = Intent(this, MagnetForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
