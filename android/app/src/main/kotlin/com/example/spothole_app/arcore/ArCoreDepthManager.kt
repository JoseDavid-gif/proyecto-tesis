package com.example.spothole_app.arcore

import android.app.Activity
import android.util.Log
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ArCoreDepthManager(
    private val activity: Activity,
) : AutoCloseable {
    companion object {
        const val CHANNEL_NAME = "spothole/arcore_depth"
        private const val TAG = "SpotholeARCore"
    }

    private var closed = false
    private var cameraView: ArCoreDepthView? = null
    private var hostResumed = false

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("MANAGER_CLOSED", "El servicio ARCore está cerrado.", null)
            return
        }
        when (call.method) {
            "checkAvailability" -> result.success(checkAvailability())
            "requestInstall" -> requestInstall(call, result)
            "checkDepthSupport" -> result.success(checkDepthSupport())
            "acquireFrame" -> acquireFrame(result)
            "pauseDepthCamera" -> {
                cameraView?.pauseSession()
                result.success(null)
            }
            "resumeDepthCamera" -> {
                cameraView?.resumeSession()
                result.success(null)
            }
            "disposeDepthCamera" -> {
                cameraView?.dispose()
                cameraView = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    internal fun attach(view: ArCoreDepthView) {
        cameraView?.dispose()
        cameraView = view
        if (hostResumed) view.resumeSession()
    }

    internal fun detach(view: ArCoreDepthView) {
        if (cameraView === view) cameraView = null
    }

    fun onHostResume() {
        hostResumed = true
        cameraView?.resumeSession()
    }

    fun onHostPause() {
        hostResumed = false
        cameraView?.pauseSession()
    }

    private fun acquireFrame(result: MethodChannel.Result) {
        val view = cameraView
        if (view == null) {
            result.error("DEPTH_CAMERA_NOT_READY", "La cámara ARCore no está lista.", null)
            return
        }
        view.requestFrame(result)
    }

    private fun checkAvailability(): Map<String, Any> {
        val availability = ArCoreApk.getInstance().checkAvailability(activity)
        val response = mutableMapOf<String, Any>(
            "availability" to availability.name,
            "supported" to availability.isSupported,
            "transient" to availability.isTransient,
        )
        Log.d(TAG, "ARCORE_AVAILABLE=${availability.isSupported} state=${availability.name}")
        return response
    }

    private fun requestInstall(call: MethodCall, result: MethodChannel.Result) {
        val userRequestedInstall = call.argument<Boolean>("userRequestedInstall") ?: true
        try {
            val status = ArCoreApk.getInstance().requestInstall(activity, userRequestedInstall)
            result.success(mapOf("installStatus" to status.name))
        } catch (error: UnavailableException) {
            result.error("ARCORE_UNAVAILABLE", error.javaClass.simpleName, null)
        }
    }

    private fun checkDepthSupport(): Map<String, Any> {
        var session: Session? = null
        return try {
            session = Session(activity)
            val automatic = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            val raw = session.isDepthModeSupported(Config.DepthMode.RAW_DEPTH_ONLY)
            Log.d(TAG, "DEPTH_AUTOMATIC_SUPPORTED=$automatic RAW_DEPTH_SUPPORTED=$raw")
            mapOf(
                "sessionSupported" to true,
                "automaticDepthSupported" to automatic,
                "rawDepthSupported" to raw,
            )
        } catch (error: UnavailableException) {
            Log.d(TAG, "ARCore session unavailable: ${error.javaClass.simpleName}")
            mapOf(
                "sessionSupported" to false,
                "automaticDepthSupported" to false,
                "rawDepthSupported" to false,
                "reason" to error.javaClass.simpleName,
            )
        } catch (error: RuntimeException) {
            Log.d(TAG, "ARCore session check failed: ${error.javaClass.simpleName}")
            mapOf(
                "sessionSupported" to false,
                "automaticDepthSupported" to false,
                "rawDepthSupported" to false,
                "reason" to error.javaClass.simpleName,
            )
        } finally {
            session?.close()
        }
    }

    override fun close() {
        closed = true
        cameraView?.dispose()
        cameraView = null
    }
}
