package com.example.dart_sip_ua_example

import android.app.Service
import android.content.Intent
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class CallService : Service() {
    private var flutterEngine: FlutterEngine? = null

    override fun onCreate() {
        super.onCreate()
        flutterEngine = FlutterEngine(this)
        flutterEngine!!.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "com.example.sip")
        channel.invokeMethod("acceptIncomingCall", null)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        flutterEngine?.destroy()
        super.onDestroy()
    }
} 