package com.uu03.notes_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app reads and writes plain .md files in a shared folder (e.g. /storage/emulated/0/Notes)
 * so that Syncthing can sync that folder between the phone and the PC.
 *
 * On Android 11+ (API 30+) reading a shared folder requires the "All files access" permission.
 * On Android 10 and older the legacy WRITE_EXTERNAL_STORAGE permission is enough.
 *
 * This is implemented with a plain MethodChannel instead of a third-party plugin so that the
 * app has no extra Gradle dependencies.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "notes_app/storage"
    private val legacyStorageRequestCode = 1001
    private val legacyPermissions = arrayOf(
        Manifest.permission.WRITE_EXTERNAL_STORAGE,
        Manifest.permission.READ_EXTERNAL_STORAGE
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStorageAccess" -> result.success(hasStorageAccess())
                    "requestStorageAccess" -> {
                        requestStorageAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasStorageAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStorageAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Opens the system screen where the user flips the "Allow management of all files"
            // switch for this app. The <package:...> variant goes straight to our own entry.
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                        .setData(Uri.parse("package:$packageName"))
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(legacyPermissions, legacyStorageRequestCode)
        }
    }
}
