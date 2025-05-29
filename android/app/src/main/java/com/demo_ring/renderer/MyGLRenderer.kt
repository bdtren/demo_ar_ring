package com.demo_ring.renderer

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class MyGLRenderer(private val context: Context) : GLSurfaceView.Renderer {

    // Model data buffers
    private lateinit var vertexBuffer: FloatBuffer
    private var vertexCount = 0

    // Original object dimensions - using fixed values for screen space
    private var originalWidth = 2f  // Full width of screen in OpenGL coordinates (-1 to 1)
    private var originalHeight = 2f // Full height of screen in OpenGL coordinates (-1 to 1)

    // MVP matrices
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix       = FloatArray(16)
    private val modelMatrix      = FloatArray(16)
    private val mvpMatrix        = FloatArray(16)

    // Shader handles
    private var program = 0
    private var positionHandle = 0
    private var mvpMatrixHandle = 0
    var isLoaded = false

    @Volatile private var tx = 0f
    @Volatile private var ty = 0f
    @Volatile private var tz = -3f      // keep default camera distance
    @Volatile private var rotDeg = 0f    // rotation around Z
    @Volatile private var targetWidth = 1f     // target width in 3D space
    @Volatile private var screenWidth = 1f     // screen width for coordinate conversion
    @Volatile private var screenHeight = 1f    // screen height for coordinate conversion

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 0f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)

        // Get viewport dimensions
        val viewport = IntArray(4)
        GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, viewport, 0)
        originalWidth = viewport[2].toFloat()  // width
        originalHeight = viewport[3].toFloat() // height

        // 1) Load and parse OBJ
        loadObj("models/ring_3d.obj")
        isLoaded = true

        // 2) Compile shaders & link program
        val vertShader = loadShader(GLES20.GL_VERTEX_SHADER, VERT_SHADER_CODE)
        val fragShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAG_SHADER_CODE)
        program = GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vertShader)
            GLES20.glAttachShader(it, fragShader)
            GLES20.glLinkProgram(it)
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        // Update screen dimensions for coordinate conversion
        screenWidth = width.toFloat()
        screenHeight = height.toFloat()

        val ratio = width.toFloat() / height
        // 45° fov, near=0.1, far=100
        Matrix.perspectiveM(projectionMatrix, 0, 45f, ratio, 0.1f, 100f)
        // Camera at (0,0,3), looking at 0,0,0, up=(0,1,0)
        Matrix.setLookAtM(viewMatrix, 0,
            0f, 0f, 3f,
            0f, 0f, 0f,
            0f, 1f, 0f)
    }

    fun updatePose(x: Float, y: Float, z: Float, angleDeg: Float, w: Float, h: Float) {
        // Convert screen coordinates to OpenGL coordinates
        // Screen: (0,0) at top-left, (width,height) at bottom-right
        // OpenGL: (-1,-2.2) at bottom-left, (1,2.5) at top-right
        tx = (x / screenWidth) * 2f - 1f  // Map x from [0,width] to [-1,1]
        ty = 2.4f - (y / screenHeight) * 4.6f  // Map y from [0,height] to [2.5,-2.2]
        tz = z
        rotDeg = angleDeg
        targetWidth = w

        Log.i("MYGLCAMERA_", "X data: $x - $screenWidth - $tx")
        Log.i("MYGLCAMERA_", "Y data: $y - $screenHeight - $ty")
    }

    override fun onDrawFrame(gl: GL10?) {
        // EARLY EXIT if data isn't ready
        if (!isLoaded || !::vertexBuffer.isInitialized || vertexCount == 0) {
            return
        }

        GLES20.glClear( GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT )
        GLES20.glUseProgram(program)

        // Calculate scale based on width only, maintaining aspect ratio
        val scale = targetWidth / originalWidth

        // BUILD Mₘ = T · R · S
        Matrix.setIdentityM(modelMatrix, 0)
        // Apply translation directly from screen coordinates
        Matrix.translateM(modelMatrix, 0, tx, ty, tz)
        // Apply rotation around Z axis
        Matrix.rotateM(modelMatrix, 0, rotDeg, 0f, 0f, 1f)
        // Apply uniform scaling
        Matrix.scaleM(modelMatrix, 0, scale, scale, scale)

        // MVP = P · V · Mₘ
        Matrix.multiplyMM(mvpMatrix, 0, viewMatrix, 0,  modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, mvpMatrix, 0)

        // pass MVP & draw as before…
        GLES20.glUniformMatrix4fv(mvpMatrixHandle, 1, false, mvpMatrix, 0)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 3*4, vertexBuffer)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)
        GLES20.glDisableVertexAttribArray(positionHandle)
    }

    private fun loadObj(filename: String) {
        val verts = mutableListOf<Float>()
        val faces = mutableListOf<Int>()

        context.assets.open(filename).bufferedReader().forEachLine { line ->
            when {
                line.startsWith("v ") -> {
                    val parts = line.split("\\s+".toRegex())
                    verts += parts[1].toFloat()
                    verts += parts[2].toFloat()
                    verts += parts[3].toFloat()
                }
                line.startsWith("f ") -> {
                    // drop the leading "f", then for each face token split on '/' and parse only the vertex index
                    line.split("\\s+".toRegex())
                        .drop(1)                // e.g. ["7//7","8//8","9//9"]
                        .take(3)                // handle triangles only
                        .forEach { token ->
                            val idx = token
                                .split("/")[0]      // get the substring before any '/'
                                .toInt() - 1        // convert to 0-based
                            faces += idx
                        }
                }
            }
        }

        // build flat float array: each triangle's 3 verts
        val flat = FloatArray(faces.size * 3)
        for (i in faces.indices) {
            flat[i*3 + 0] = verts[faces[i]*3 + 0]
            flat[i*3 + 1] = verts[faces[i]*3 + 1]
            flat[i*3 + 2] = verts[faces[i]*3 + 2]
        }
        vertexCount = flat.size / 3

        vertexBuffer = ByteBuffer
            .allocateDirect(flat.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(flat); position(0) }
    }


    private fun loadShader(type: Int, code: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, code)
            GLES20.glCompileShader(shader)
        }
    }

    companion object {
        // simple unlit shaders
        private const val VERT_SHADER_CODE = """
      uniform mat4 uMVPMatrix;
      attribute vec3 aPosition;
      void main() {
        gl_Position = uMVPMatrix * vec4(aPosition, 1.0);
      }
    """
        private const val FRAG_SHADER_CODE = """
      precision mediump float;
      void main() {
        gl_FragColor = vec4(0.8, 0.8, 0.8, 1.0);
      }
    """
    }
}
