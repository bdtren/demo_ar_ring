package com.demo_ring

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.util.Log
import android.view.View
import androidx.core.content.ContextCompat
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import kotlin.math.max
import kotlin.math.min

class OverlayView(context: Context, attrs: AttributeSet?) :
    View(context, attrs) {

    private var results: HandLandmarkerResult? = null
    private var linePaint = Paint()
    private var pointPaint = Paint()
    private var ringLinePaint = Paint()
    private var onRingPoseUpdate: ((x: Float, y: Float, z: Float, angleDeg: Float, width: Float, height: Float) -> Unit)? = null

    private var scaleFactor: Float = 1f
    private var imageWidth: Int = 1
    private var imageHeight: Int = 1

    init {
        initPaints()
    }

    fun clear() {
        results = null
        linePaint.reset()
        pointPaint.reset()
        ringLinePaint.reset()
        invalidate()
        initPaints()
    }

    private fun initPaints() {
        linePaint.color =
            ContextCompat.getColor(context!!, R.color.mp_color_primary)
        linePaint.strokeWidth = LANDMARK_STROKE_WIDTH
        linePaint.style = Paint.Style.STROKE

        pointPaint.color = Color.RED
        pointPaint.strokeWidth = LANDMARK_STROKE_WIDTH
        pointPaint.style = Paint.Style.FILL

        ringLinePaint.color = Color.YELLOW
        ringLinePaint.strokeWidth = 12f
        ringLinePaint.style = Paint.Style.STROKE
    }

    fun setOnRingPoseUpdateListener(listener: (x: Float, y: Float, z: Float, angleDeg: Float, width: Float, height: Float) -> Unit) {
        onRingPoseUpdate = listener
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        results?.let { handLandmarkerResult ->
            for (landmark in handLandmarkerResult.landmarks()) {
                // Calculate hand width using distance between index and pinky MCP joints
                val indexMCP = landmark.get(5)  // Index finger MCP
                val pinkyMCP = landmark.get(17) // Pinky finger MCP

                val indexX = indexMCP.x() * imageWidth * scaleFactor
                val indexY = indexMCP.y() * imageHeight * scaleFactor
                val pinkyX = pinkyMCP.x() * imageWidth * scaleFactor
                val pinkyY = pinkyMCP.y() * imageHeight * scaleFactor

                // Calculate hand width
                val handWidth = kotlin.math.sqrt(
                    (pinkyX - indexX) * (pinkyX - indexX) +
                    (pinkyY - indexY) * (pinkyY - indexY)
                ) * 0.9f

                // Draw perpendicular line at 60% of the distance between ring finger MCP and PIP
                val mcp = landmark.get(13)  // Ring finger MCP
                val pip = landmark.get(14)  // Ring finger PIP

                // Calculate base points
                val x1 = mcp.x() * imageWidth * scaleFactor
                val y1 = mcp.y() * imageHeight * scaleFactor
                val x2 = pip.x() * imageWidth * scaleFactor
                val y2 = pip.y() * imageHeight * scaleFactor

                // Calculate 60% point
                val x60 = x1 + (x2 - x1) * 0.6f
                val y60 = y1 + (y2 - y1) * 0.6f

                // Calculate perpendicular vector
                val dx = x2 - x1
                val dy = y2 - y1
                val length = kotlin.math.sqrt(dx * dx + dy * dy)
                val perpX = -dy / length
                val perpY = dx / length

                // Use hand width to scale the perpendicular line length
                val perpLength = handWidth * 0.2f  // 20% of hand width

                // Calculate end points of perpendicular line
                val perpX1 = x60 - perpX * perpLength
                val perpY1 = y60 - perpY * perpLength
                val perpX2 = x60 + perpX * perpLength
                val perpY2 = y60 + perpY * perpLength

                // Draw the perpendicular yellow line
//                canvas.drawLine(perpX1, perpY1, perpX2, perpY2, ringLinePaint)
//                canvas.drawPoint(x60, y60, pointPaint)

                // Calculate line angle in degrees
                val lineAngleRad = kotlin.math.atan2(perpY2 - perpY1, perpX2 - perpX1)
                val lineAngleDeg = Math.toDegrees(lineAngleRad.toDouble()).toFloat()

                // Pass screen coordinates directly
                val x = x60 // Screen x coordinate
                val y = y60 // Screen y coordinate
                val z = -3f  // Keep the same depth

                // Update ring pose with screen coordinates
                onRingPoseUpdate?.invoke(
                    x,
                    y,
                    z,
                    -lineAngleDeg,  // Negate the angle
                    perpLength / 3.7f,
                    0f  //Not applied for now
                )
            }
        }
    }

    fun setResults(
        handLandmarkerResults: HandLandmarkerResult,
        imageHeight: Int,
        imageWidth: Int,
        runningMode: RunningMode = RunningMode.IMAGE
    ) {
        results = handLandmarkerResults

        this.imageHeight = imageHeight
        this.imageWidth = imageWidth

        scaleFactor = when (runningMode) {
            RunningMode.IMAGE,
            RunningMode.VIDEO -> {
                min(width * 1f / imageWidth, height * 1f / imageHeight)
            }
            RunningMode.LIVE_STREAM -> {
                // PreviewView is in FILL_START mode. So we need to scale up the
                // landmarks to match with the size that the captured images will be
                // displayed.
                max(width * 1f / imageWidth, height * 1f / imageHeight)
            }
        }
        invalidate()
    }

    companion object {
        private const val LANDMARK_STROKE_WIDTH = 8F
    }
}
