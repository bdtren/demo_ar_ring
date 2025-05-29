package com.demo_ring

import android.content.Context
import android.graphics.PixelFormat
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.view.View
import android.widget.ProgressBar
import com.demo_ring.renderer.MyGLRenderer

class MyGLSurfaceView(context: Context, attrs: AttributeSet?) : GLSurfaceView(context, attrs) {
    private val renderer: MyGLRenderer
    private var progressBar: ProgressBar? = null

    init {
        holder.setFormat(PixelFormat.TRANSLUCENT)
        setZOrderOnTop(true)

        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        // Use OpenGL ES 2.0
        setEGLContextClientVersion(2)
        renderer = MyGLRenderer(context)
        setRenderer(renderer)
        // continuous rendering so model stays visible
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    fun setProgressBar(progressBar: ProgressBar) {
        this.progressBar = progressBar
        updateLoadingState()
    }

    private fun updateLoadingState() {
        post {
            progressBar?.visibility = if (renderer.isLoaded) View.GONE else View.VISIBLE
        }
    }

    fun setRingPose(x: Float, y: Float, z: Float, angleDeg: Float, width: Float, height: Float) {
        queueEvent {
            renderer.updatePose(x, y, z, angleDeg, width, height)
            updateLoadingState()
        }
    }
}
