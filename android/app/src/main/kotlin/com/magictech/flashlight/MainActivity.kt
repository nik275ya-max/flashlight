package com.magictech.flashlight

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
                    "listLaunchableApps" -> {
                        try {
                            result.success(queryLaunchableApps())
                        } catch (e: Exception) {
                            // An empty list is better than a broken picker.
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrEmpty()) {
                            result.error("invalid_argument", "packageName is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(launchApp(packageName))
                    }
                    "openOverlaySettings" -> {
                        result.success(openOverlaySettings())
                    }
                    "canLaunchInBackground" -> {
                        result.success(canLaunchInBackground())
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

    /**
     * Every installed app that has a launcher entry, with its label and icon.
     *
     * The list is what the script editor shows as "choose an app", so it only
     * contains apps the user can actually start.
     */
    private fun queryLaunchableApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>(resolved.size)
        for (info in resolved) {
            val packageName = info.activityInfo?.packageName ?: continue
            // An app can expose several launcher activities - list it once.
            if (!seen.add(packageName)) continue
            val label = try {
                info.loadLabel(pm)?.toString()
            } catch (e: Exception) {
                null
            }
            apps.add(
                mapOf(
                    "packageName" to packageName,
                    "label" to (label ?: packageName),
                    "icon" to encodeIcon(info.loadIcon(pm)),
                )
            )
        }
        apps.sortBy { (it["label"] as String).lowercase() }
        return apps
    }

    /** Renders a launcher icon into a small PNG so Dart can show it. */
    private fun encodeIcon(drawable: Drawable?): ByteArray? {
        if (drawable == null) return null
        return try {
            val size = 96
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Starts the launcher activity of [packageName].
     *
     * Returns false when the app is not installed or has no launcher entry.
     * On Android 10+ a launch from the background is only allowed with the
     * "display over other apps" permission - the system silently drops the
     * intent otherwise, so the caller cannot tell the difference.
     */
    private fun launchApp(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent == null) return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Opens the system page where the overlay permission is granted. */
    private fun openOverlaySettings(): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** True when the app may start activities while in the background. */
    private fun canLaunchInBackground(): Boolean {
        return try {
            Settings.canDrawOverlays(this)
        } catch (e: Exception) {
            false
        }
    }
}
