package com.orbit.orbit

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
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

    private lateinit var changes: EventChannel
    private var observer: ContentObserver? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "orbit/sms_import")
        channel.setMethodCallHandler(this)
        changes = EventChannel(binding.binaryMessenger, "orbit/sms_changes")
        changes.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                stopObserving()
                val o = object : ContentObserver(main) {
                    override fun onChange(selfChange: Boolean) = events.success(null)
                }
                // Fires for new, sent, and deleted SMS and MMS while the app is running.
                appContext.contentResolver.registerContentObserver(
                    Uri.parse("content://mms-sms/"), true, o
                )
                observer = o
            }

            override fun onCancel(arguments: Any?) = stopObserving()
        })
    }

    private fun stopObserving() {
        observer?.let { appContext.contentResolver.unregisterContentObserver(it) }
        observer = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        changes.setStreamHandler(null)
        stopObserving()
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
            "requestPermission" -> requestPermission(Manifest.permission.READ_SMS, result)
            "requestContactsPermission" -> requestPermission(Manifest.permission.READ_CONTACTS, result)
            else -> io.execute {
                try {
                    val value: Any? = when (call.method) {
                        "status" -> status()
                        "contactsStatus" -> hasContactsPermission()
                        "queryContacts" -> queryContacts()
                        "readPhoto" -> readPhoto(call.argument<String>("uri")!!)
                        "countSince" -> countSince(
                            call.argument<Number>("smsAfterId")!!.toLong(),
                            call.argument<Number>("mmsAfterId")!!.toLong(),
                        )
                        "openSmsInvite" -> { openSmsInvite(call.argument<String>("number")!!, call.argument<String>("body")!!); null }
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

    private fun requestPermission(permission: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(appContext, permission) == PackageManager.PERMISSION_GRANTED) {
            return result.success(true)
        }
        val act = activity ?: return result.success(false)
        if (pendingPermission != null) return result.success(false)
        pendingPermission = result
        ActivityCompat.requestPermissions(act, arrayOf(permission), REQUEST_CODE)
    }

    private fun openSmsInvite(number: String, body: String) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + Uri.encode(number)))
            .putExtra("sms_body", body)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        main.post { (activity ?: appContext).startActivity(intent) }
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
    // matching SMS Backup & Restore's `address` attribute. Some providers
    // ignore the projection and selection on these URIs, so both tables are
    // read whole and columns are looked up by name.
    private var threadRecipientIds: Map<String, String>? = null
    private var canonicalAddresses: Map<String, String>? = null

    private fun readTable(uri: String, key: String, value: String): Map<String, String> {
        val out = HashMap<String, String>()
        try {
            appContext.contentResolver.query(Uri.parse(uri), null, null, null, null)?.use { c ->
                val k = c.getColumnIndex(key)
                val v = c.getColumnIndex(value)
                if (k < 0 || v < 0) return out
                while (c.moveToNext()) {
                    val id = c.getString(k) ?: continue
                    val text = c.getString(v) ?: continue
                    out[id] = text
                }
            }
        } catch (e: Exception) {
            // Unsupported on this device; the Dart side falls back to the MMS addr rows.
        }
        return out
    }

    private fun threadRecipients(threadId: String?): String? {
        if (threadId == null) return null
        var threads = threadRecipientIds
            ?: readTable("content://mms-sms/conversations?simple=true", "_id", "recipient_ids").also { threadRecipientIds = it }
        if (threadId !in threads) {
            threads = readTable("content://mms-sms/conversations?simple=true", "_id", "recipient_ids").also { threadRecipientIds = it }
        }
        val ids = threads[threadId] ?: return null
        var addresses = canonicalAddresses
            ?: readTable("content://mms-sms/canonical-addresses", "_id", "address").also { canonicalAddresses = it }
        val rids = ids.split(" ").filter { it.isNotBlank() }
        if (rids.any { it !in addresses }) {
            addresses = readTable("content://mms-sms/canonical-addresses", "_id", "address").also { canonicalAddresses = it }
        }
        val resolved = rids.map { addresses[it] }
        if (resolved.any { it.isNullOrBlank() }) return null
        return resolved.joinToString("~")
    }

    private fun hasContactsPermission() =
        ContextCompat.checkSelfPermission(appContext, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    private fun queryContacts(): List<Map<String, String?>> {
        if (!hasContactsPermission()) return emptyList()
        val out = ArrayList<Map<String, String?>>()
        appContext.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} COLLATE NOCASE ASC"
        )?.use { c ->
            val name = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val number = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val normalized = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER)
            val photo = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI)
            val contactId = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            while (c.moveToNext()) {
                val n = if (number >= 0) c.getString(number) else null
                if (n.isNullOrBlank()) continue
                out.add(mapOf(
                    "contactId" to if (contactId >= 0) c.getString(contactId) else null,
                    "name" to if (name >= 0) c.getString(name) else null,
                    "number" to n,
                    "normalizedNumber" to if (normalized >= 0) c.getString(normalized) else null,
                    "photoUri" to if (photo >= 0) c.getString(photo) else null,
                ))
            }
        }
        return out
    }

    private fun readPhoto(uri: String): ByteArray? =
        appContext.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }

    private fun countSince(smsAfterId: Long, mmsAfterId: Long): Map<String, Int> {
        fun countAfter(uri: Uri, afterId: Long) =
            appContext.contentResolver.query(uri, arrayOf("_id"), "_id > ?", arrayOf(afterId.toString()), null)
                ?.use { it.count } ?: 0
        return mapOf(
            "sms" to countAfter(Telephony.Sms.CONTENT_URI, smsAfterId),
            "mms" to countAfter(Telephony.Mms.CONTENT_URI, mmsAfterId),
        )
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
