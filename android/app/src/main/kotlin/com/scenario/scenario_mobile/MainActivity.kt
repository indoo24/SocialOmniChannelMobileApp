package com.scenario.scenario_mobile

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.ContactsContract.CommonDataKinds.Phone
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingContact: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTACT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickPhone") pickPhone(result) else result.notImplemented()
            }
    }

    /**
     * Opens the system's phone-number picker. The user picks one number of one
     * contact there, and the result grants this app read access to that single
     * row for the duration of the call: no READ_CONTACTS permission, no prompt,
     * and nothing else of the address book is visible to the app.
     */
    private fun pickPhone(result: MethodChannel.Result) {
        if (pendingContact != null) {
            result.error("busy", "A contact pick is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_PICK).apply { type = Phone.CONTENT_TYPE }
        try {
            pendingContact = result
            startActivityForResult(intent, PICK_PHONE_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingContact = null
            result.error("unavailable", "No contacts app can pick a number.", null)
        }
    }

    @Deprecated("Activity result API; FlutterActivity is not a ComponentActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_PHONE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingContact ?: return
        pendingContact = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.query(
                uri,
                arrayOf(Phone.DISPLAY_NAME, Phone.NUMBER, Phone.TYPE, Phone.LABEL),
                null,
                null,
                null,
            )?.use { c ->
                if (!c.moveToFirst()) {
                    result.success(null)
                    return
                }
                val type = if (c.isNull(2)) Phone.TYPE_OTHER else c.getInt(2)
                val label = Phone.getTypeLabel(resources, type, c.getString(3)).toString()
                result.success(
                    mapOf(
                        "name" to (c.getString(0) ?: ""),
                        "phone" to (c.getString(1) ?: ""),
                        "type" to whatsAppType(type),
                        "label" to label,
                    ),
                )
            } ?: result.success(null)
        } catch (_: SecurityException) {
            result.error("denied", "The picked number could not be read.", null)
        }
    }

    /** WhatsApp's phone types; "" for anything it has no word for. */
    private fun whatsAppType(type: Int): String = when (type) {
        Phone.TYPE_MOBILE -> "CELL"
        Phone.TYPE_HOME -> "HOME"
        Phone.TYPE_WORK, Phone.TYPE_WORK_MOBILE -> "WORK"
        Phone.TYPE_MAIN -> "MAIN"
        else -> ""
    }

    private companion object {
        const val CONTACT_CHANNEL = "scenario/contact_picker"
        const val PICK_PHONE_REQUEST = 0x5C07
    }
}
