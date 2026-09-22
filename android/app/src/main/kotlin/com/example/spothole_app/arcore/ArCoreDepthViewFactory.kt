package com.example.spothole_app.arcore

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ArCoreDepthViewFactory(
    private val activity: Activity,
    private val manager: ArCoreDepthManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    companion object {
        const val VIEW_TYPE = "spothole/arcore_depth_view"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ArCoreDepthView(context, activity, manager)
}
