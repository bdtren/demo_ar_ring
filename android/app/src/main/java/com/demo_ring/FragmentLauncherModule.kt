package com.demo_ring

import android.app.Activity
import android.util.Log
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentManager
import com.demo_ring.fragment.CameraFragment
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod

class FragmentLauncherModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {
    override fun getName(): String = "FragmentLauncher"

    @ReactMethod
    fun launchFragment() {
        val activity: Activity? = currentActivity
        if (activity is FragmentActivity) {
            val fragmentManager: FragmentManager = activity.supportFragmentManager
            val fragment: Fragment = CameraFragment()
            fragmentManager.beginTransaction()
                .replace(android.R.id.content, fragment, "CAMERA_FRAGMENT")
                .addToBackStack(null)
                .commitAllowingStateLoss()
        } else {
            Log.e("FragmentLauncher", "Activity is not a FragmentActivity")
        }
    }
}
