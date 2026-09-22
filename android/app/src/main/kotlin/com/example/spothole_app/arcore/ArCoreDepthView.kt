package com.example.spothole_app.arcore

import android.app.Activity
import android.content.Context
import android.graphics.PixelFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.Surface
import android.view.View
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

internal class ArCoreDepthView(
    context: Context,
    private val activity: Activity,
    private val manager: ArCoreDepthManager,
) : PlatformView, GLSurfaceView.Renderer {
    private val surfaceView = GLSurfaceView(context)
    private val session = Session(context)
    private val disposed = AtomicBoolean(false)
    private val sessionLock = Any()
    private var resumed = false
    private var textureId = 0
    private var program = 0
    private var surfaceWidth = 1
    private var surfaceHeight = 1
    private var pendingResult: MethodChannel.Result? = null
    private val quadVertices = floatBufferOf(
        -1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f,
    )
    private val quadTextureCoordinates = floatBufferOf(
        0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f,
    )

    init {
        val config = session.config
        config.depthMode = Config.DepthMode.AUTOMATIC
        config.focusMode = Config.FocusMode.AUTO
        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        session.configure(config)
        surfaceView.setEGLContextClientVersion(2)
        surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        surfaceView.holder.setFormat(PixelFormat.TRANSLUCENT)
        surfaceView.setRenderer(this)
        surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        manager.attach(this)
    }

    override fun getView(): View = surfaceView

    fun requestFrame(result: MethodChannel.Result) {
        synchronized(sessionLock) {
            if (disposed.get() || !resumed) {
                result.error("DEPTH_CAMERA_PAUSED", "La cámara ARCore está pausada.", null)
                return
            }
            if (pendingResult != null) {
                result.error("FRAME_REQUEST_BUSY", "Ya existe una captura pendiente.", null)
                return
            }
            pendingResult = result
        }
    }

    fun resumeSession() {
        synchronized(sessionLock) {
            if (disposed.get() || resumed) return
            try {
                session.resume()
                surfaceView.onResume()
                resumed = true
            } catch (error: CameraNotAvailableException) {
                pendingResult?.error("CAMERA_NOT_AVAILABLE", error.message, null)
                pendingResult = null
            }
        }
    }

    fun pauseSession() {
        synchronized(sessionLock) {
            if (!resumed) return
            surfaceView.onPause()
            session.pause()
            resumed = false
            pendingResult?.error("DEPTH_CAMERA_PAUSED", "La cámara ARCore fue pausada.", null)
            pendingResult = null
        }
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        textureId = createExternalTexture()
        session.setCameraTextureName(textureId)
        program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        surfaceWidth = width.coerceAtLeast(1)
        surfaceHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, surfaceWidth, surfaceHeight)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (!resumed || disposed.get() || textureId == 0) return
        val rotation = activity.display?.rotation ?: Surface.ROTATION_0
        session.setDisplayGeometry(rotation, surfaceWidth, surfaceHeight)
        val frame = try {
            session.update()
        } catch (_: CameraNotAvailableException) {
            return
        }
        if (frame.hasDisplayGeometryChanged()) {
            val ndc = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
            val texture = FloatArray(8)
            frame.transformCoordinates2d(
                com.google.ar.core.Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                ndc,
                com.google.ar.core.Coordinates2d.TEXTURE_NORMALIZED,
                texture,
            )
            quadTextureCoordinates.position(0)
            quadTextureCoordinates.put(texture)
            quadTextureCoordinates.position(0)
        }
        drawBackground()
        val result = synchronized(sessionLock) {
            val value = pendingResult
            pendingResult = null
            value
        } ?: return
        if (frame.camera.trackingState != TrackingState.TRACKING) {
            Log.d(
                "SpotholeARCore",
                "SPOTHOLE_AR tracking=PAUSED reason=${frame.camera.trackingFailureReason.name}",
            )
            activity.runOnUiThread {
                result.error("TRACKING_UNAVAILABLE", frame.camera.trackingFailureReason.name, null)
            }
            return
        }
        Log.d("SpotholeARCore", "SPOTHOLE_AR tracking=TRACKING")
        val snapshot = captureSnapshot(frame)
        activity.runOnUiThread {
            if (snapshot == null) {
                result.error("FRAME_NOT_YET_AVAILABLE", "RGB o Depth aún no disponible.", null)
            } else {
                result.success(snapshot)
            }
        }
    }

    private fun captureSnapshot(frame: com.google.ar.core.Frame): Map<String, Any>? {
        val cameraImage = try {
            frame.acquireCameraImage()
        } catch (_: NotYetAvailableException) {
            return null
        }
        cameraImage.use { rgb ->
            val rawDepth = try {
                frame.acquireRawDepthImage16Bits()
            } catch (_: NotYetAvailableException) {
                null
            }
            val rawConfidence = if (rawDepth != null) {
                try {
                    frame.acquireRawDepthConfidenceImage()
                } catch (_: NotYetAvailableException) {
                    null
                }
            } else {
                null
            }
            val fullDepth = try {
                frame.acquireDepthImage16Bits()
            } catch (_: NotYetAvailableException) {
                null
            }
            Log.d(
                "SpotholeARCore",
                "SPOTHOLE_DEPTH rawAvailable=${rawDepth != null} " +
                    "rawWidth=${rawDepth?.width ?: 0} rawHeight=${rawDepth?.height ?: 0} " +
                    "confidenceAvailable=${rawConfidence != null} " +
                    "fullAvailable=${fullDepth != null} timestamp=${frame.timestamp}",
            )
            try {
                val selectedDepth = if (rawDepth != null && rawConfidence != null) {
                    rawDepth
                } else {
                    fullDepth ?: return null
                }
                val intrinsics = frame.camera.imageIntrinsics
                val focal = intrinsics.focalLength
                val principal = intrinsics.principalPoint
                val dimensions = intrinsics.imageDimensions
                val pose = FloatArray(16)
                frame.camera.pose.toMatrix(pose, 0)
                return mutableMapOf<String, Any>().apply {
                    putAll(DepthFrameData.copyYuvImage(rgb))
                    put("rotationDegrees", cameraRotationDegrees())
                    put("frameTimestampNs", frame.timestamp)
                    put("fx", focal[0].toDouble())
                    put("fy", focal[1].toDouble())
                    put("cx", principal[0].toDouble())
                    put("cy", principal[1].toDouble())
                    put("intrinsicsWidth", dimensions[0])
                    put("intrinsicsHeight", dimensions[1])
                    put("imageToTexture", DepthFrameData.imageToTextureTransform(frame, rgb.width, rgb.height).toList())
                    put("cameraPose", pose.toList())
                    put("depth", DepthFrameData.copyDepthImage(selectedDepth))
                    put("rawDepth", rawDepth != null && rawConfidence != null)
                    if (rawConfidence != null) {
                        put("confidence", DepthFrameData.copyDepthImage(rawConfidence))
                    }
                    if (rawDepth != null && rawConfidence != null && fullDepth != null) {
                        put("fallbackDepth", DepthFrameData.copyDepthImage(fullDepth))
                    }
                }
            } finally {
                rawConfidence?.close()
                rawDepth?.close()
                fullDepth?.close()
            }
        }
    }

    private fun cameraRotationDegrees(): Int {
        val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = session.cameraConfig.cameraId
        val sensor = cameraManager.getCameraCharacteristics(cameraId)
            .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val displayDegrees = when (activity.display?.rotation ?: Surface.ROTATION_0) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        return (sensor - displayDegrees + 360) % 360
    }

    private fun drawBackground() {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glUseProgram(program)
        val position = GLES20.glGetAttribLocation(program, "aPosition")
        val texCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
        quadVertices.position(0)
        quadTextureCoordinates.position(0)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, quadVertices)
        GLES20.glVertexAttribPointer(texCoord, 2, GLES20.GL_FLOAT, false, 0, quadTextureCoordinates)
        GLES20.glEnableVertexAttribArray(position)
        GLES20.glEnableVertexAttribArray(texCoord)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "cameraTexture"), 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(position)
        GLES20.glDisableVertexAttribArray(texCoord)
        GLES20.glDepthMask(true)
    }

    override fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        pauseSession()
        session.close()
        manager.detach(this)
    }

    companion object {
        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() { gl_Position = aPosition; vTexCoord = aTexCoord; }
        """
        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES cameraTexture;
            void main() { gl_FragColor = texture2D(cameraTexture, vTexCoord); }
        """

        private fun floatBufferOf(vararg values: Float): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply { put(values); position(0) }

        private fun createExternalTexture(): Int {
            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textures[0])
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            return textures[0]
        }

        private fun createProgram(vertexSource: String, fragmentSource: String): Int {
            fun compile(type: Int, source: String): Int = GLES20.glCreateShader(type).also { shader ->
                GLES20.glShaderSource(shader, source)
                GLES20.glCompileShader(shader)
            }
            return GLES20.glCreateProgram().also { value ->
                GLES20.glAttachShader(value, compile(GLES20.GL_VERTEX_SHADER, vertexSource))
                GLES20.glAttachShader(value, compile(GLES20.GL_FRAGMENT_SHADER, fragmentSource))
                GLES20.glLinkProgram(value)
            }
        }
    }
}
