package com.example.spothole_app.arcore

import android.media.Image
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame

internal object DepthFrameData {
    fun copyPlane(plane: Image.Plane): ByteArray {
        val buffer = plane.buffer.duplicate()
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        return bytes
    }

    fun copyYuvImage(image: Image): Map<String, Any> {
        require(image.planes.size >= 3)
        return mapOf(
            "width" to image.width,
            "height" to image.height,
            "timestampNs" to image.timestamp,
            "yBytes" to copyPlane(image.planes[0]),
            "uBytes" to copyPlane(image.planes[1]),
            "vBytes" to copyPlane(image.planes[2]),
            "yRowStride" to image.planes[0].rowStride,
            "uRowStride" to image.planes[1].rowStride,
            "vRowStride" to image.planes[2].rowStride,
            "uPixelStride" to image.planes[1].pixelStride,
            "vPixelStride" to image.planes[2].pixelStride,
        )
    }

    fun copyDepthImage(image: Image): Map<String, Any> {
        val plane = image.planes[0]
        return mapOf(
            "width" to image.width,
            "height" to image.height,
            "timestampNs" to image.timestamp,
            "bytes" to copyPlane(plane),
            "rowStride" to plane.rowStride,
            "pixelStride" to plane.pixelStride,
        )
    }

    fun imageToTextureTransform(frame: Frame, width: Int, height: Int): FloatArray {
        val source = floatArrayOf(0f, 0f, width.toFloat(), 0f, 0f, height.toFloat())
        val target = FloatArray(source.size)
        frame.transformCoordinates2d(
            Coordinates2d.IMAGE_PIXELS,
            source,
            Coordinates2d.TEXTURE_NORMALIZED,
            target,
        )
        return target
    }
}
