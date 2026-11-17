// REFERENCE CODE - not compiled as part of the Dart package.
// Copy to android/app/src/main/kotlin/<your/package>/OrbitSmsImportPlugin.kt
// and register it from MainActivity (see docs/IMPORT.md, "Android on-device").
//
// Implements the `orbit/sms_import` MethodChannel used by
// lib/import/sources/android_device_source.dart.
//
// Requires in AndroidManifest.xml:
//   <uses-permission android:name="android.permission.READ_SMS" />
// Google Play only allows READ_SMS for apps that are (or ask to become) the
// default SMS handler, or that hold an approved exception. Ship this in a
// sideloaded/enterprise build, or only enable it if Orbit becomes a full SMS app.

package com.example.orbit

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

class OrbitSmsImportPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: android.content.Context
    private var activity: Activity? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "orbit/sms_import")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() { activity = null }

    private fun hasPermission() =
        ContextCompat.checkSelfPermission(appContext, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> {
                if (hasPermission()) return result.success(true)
                val act = activity ?: return result.success(false)
                pendingPermission = result
                ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.READ_SMS), REQUEST_CODE)
            }
            else -> io.execute {
                try {
                    val value: Any? = when (call.method) {
                        "status" -> status()
                        "querySms" -> querySms(call.argument<Int>("afterId")!!.toLong(), call.argument<Int>("limit")!!)
                        "queryMms" -> queryMms(call.argument<Int>("afterId")!!.toLong(), call.argument<Int>("limit")!!)
                        "copyPart" -> copyPart(call.argument<String>("partId")!!, call.argument<String>("destinationPath")!!)
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(value) }
                } catch (e: SecurityException) {
                    main.post { result.error("permission", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("error", e.message, null) }
                }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    private fun count(uri: Uri): Int =
        appContext.contentResolver.query(uri, arrayOf("_id"), null, null, null)?.use { it.count } ?: 0

    private fun status(): Map<String, Any> {
        val granted = hasPermission()
        return mapOf(
            "hasPermission" to granted,
            "isDefaultSmsApp" to (Telephony.Sms.getDefaultSmsPackage(appContext) == appContext.packageName),
            "smsCount" to if (granted) count(Telephony.Sms.CONTENT_URI) else 0,
            "mmsCount" to if (granted) count(Telephony.Mms.CONTENT_URI) else 0,
        )
    }

    private fun rows(uri: Uri, selection: String?, args: Array<String>?, order: String?): List<Map<String, String?>> {
        val out = ArrayList<Map<String, String?>>()
        appContext.contentResolver.query(uri, null, selection, args, order)?.use { c ->
            while (c.moveToNext()) {
                val m = HashMap<String, String?>()
                for (i in 0 until c.columnCount) {
                    if (c.getType(i) == android.database.Cursor.FIELD_TYPE_BLOB) continue
                    m[c.getColumnName(i)] = c.getString(i)
                }
                out.add(m)
            }
        }
        return out
    }

    private fun querySms(afterId: Long, limit: Int): List<Map<String, String?>> =
        rows(Telephony.Sms.CONTENT_URI, "_id > ?", arrayOf(afterId.toString()), "_id ASC LIMIT $limit")

    private fun queryMms(afterId: Long, limit: Int): List<Map<String, Any?>> {
        val pdus = rows(Telephony.Mms.CONTENT_URI, "_id > ?", arrayOf(afterId.toString()), "_id ASC LIMIT $limit")
        return pdus.map { pdu ->
            val id = pdu["_id"]!!
            val m = HashMap<String, Any?>(pdu)
            // The provider stores MMS dates in seconds; the Dart side expects ms (like SMS Backup & Restore).
            m["date"] = pdu["date"]?.toLongOrNull()?.times(1000)?.toString()
            m["date_sent"] = pdu["date_sent"]?.toLongOrNull()?.times(1000)?.toString()
            m["parts"] = rows(Uri.parse("content://mms/part"), "mid = ?", arrayOf(id), "seq ASC")
                .map { it - "_data" }
            m["addrs"] = rows(Uri.parse("content://mms/$id/addr"), null, null, null)
            m["address"] = threadRecipients(pdu["thread_id"])
            m
        }
    }

    // Participants of the conversation joined with "~" (excludes the owner),
    // matching SMS Backup & Restore's `address` attribute.
    private val recipientCache = HashMap<String, String?>()
    private fun threadRecipients(threadId: String?): String? {
        if (threadId == null) return null
        return recipientCache.getOrPut(threadId) {
            val ids = appContext.contentResolver.query(
                Uri.parse("content://mms-sms/conversations?simple=true"),
                arrayOf("recipient_ids"), "_id = ?", arrayOf(threadId), null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: return@getOrPut null
            ids.split(" ").filter { it.isNotBlank() }.mapNotNull { rid ->
                appContext.contentResolver.query(
                    Uri.parse("content://mms-sms/canonical-addresses"),
                    arrayOf("address"), "_id = ?", arrayOf(rid), null
                )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            }.joinToString("~")
        }
    }

    private fun copyPart(partId: String, destinationPath: String): Int {
        val dest = File(destinationPath)
        dest.parentFile?.mkdirs()
        var total = 0
        appContext.contentResolver.openInputStream(Uri.parse("content://mms/part/$partId"))?.use { input ->
            dest.outputStream().use { output -> total = input.copyTo(output).toInt() }
        } ?: throw IllegalStateException("Part $partId has no data")
        return total
    }

    companion object { private const val REQUEST_CODE = 0x5345 }
}
