package com.example.spothole_app

import com.example.spothole_app.arcore.ArCoreDepthManager
import com.example.spothole_app.arcore.ArCoreDepthViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var arCoreDepthManager: ArCoreDepthManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = ArCoreDepthManager(this)
        arCoreDepthManager = manager
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArCoreDepthManager.CHANNEL_NAME,
        ).setMethodCallHandler(manager::handleMethodCall)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ArCoreDepthViewFactory.VIEW_TYPE,
            ArCoreDepthViewFactory(this, manager),
        )
    }

    override fun onResume() {
        super.onResume()
        arCoreDepthManager?.onHostResume()
    }

    override fun onPause() {
        arCoreDepthManager?.onHostPause()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        arCoreDepthManager?.close()
        arCoreDepthManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
