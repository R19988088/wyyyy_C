package com.r19988088.wyyyy

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val feedbackHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.r19988088.wyyyy/cover_feedback",
        ).setMethodCallHandler { call, result ->
            if (call.method != "coverChanged") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val hapticStrength = (call.argument<Double>("hapticStrength") ?: 0.0)
                .coerceIn(0.0, 1.0)
            val soundStrength = (call.argument<Double>("soundStrength") ?: 0.0)
                .coerceIn(0.0, 1.0)
            result.success(null)
            feedbackHandler.post {
                playCoverFeedback(hapticStrength, soundStrength)
            }
        }
    }

    private fun playCoverFeedback(hapticStrength: Double, soundStrength: Double) {
        if (soundStrength > 0.0) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.playSoundEffect(AudioManager.FX_KEY_CLICK, soundStrength.toFloat())
        }
        if (hapticStrength <= 0.0) return
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val amplitude = (hapticStrength * 255).roundToInt().coerceAtLeast(1)
            vibrator.vibrate(VibrationEffect.createOneShot(14, amplitude))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(14)
        }
    }
}
