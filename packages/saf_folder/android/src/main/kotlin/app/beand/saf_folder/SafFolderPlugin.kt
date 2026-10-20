package app.beand.saf_folder

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

// A folder the user picks once through the system dialog (Storage Access
// Framework), kept across restarts via a persistable permission, and a file
// write into it that replaces an existing file of the same name only once
// the new one is complete. For bean'd's auto backup
// (lib/services/auto_backup.dart), which also runs in WorkManager's
// background engine — hence a real plugin and not a channel in
// MainActivity: only plugins are registered there.
class SafFolderPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var resolver: ContentResolver
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        resolver = flutterPluginBinding.applicationContext.contentResolver
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "beand/saf_folder")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "folderName" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                background(result) { if (canWrite(uri)) displayName(uri) else null }
            }
            "writeFile" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val name = call.argument<String>("name")!!
                val source = File(call.argument<String>("source")!!)
                background(result) { writeFile(uri, name, source); null }
            }
            "release" -> {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                try {
                    resolver.releasePersistableUriPermission(uri, RW)
                } catch (_: SecurityException) {
                    // Already gone.
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("saf_folder", e.message ?: e.toString(), null) }
            }
        }
    }

    // ---- Picking ----

    private fun pickFolder(result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("saf_folder", "No activity", null)
            return
        }
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        current.startActivityForResult(intent, REQUEST_PICK)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        background(result) {
            resolver.takePersistableUriPermission(uri, RW)
            mapOf("uri" to uri.toString(), "name" to displayName(uri))
        }
        return true
    }

    // ---- Folder ----

    private fun canWrite(tree: Uri): Boolean = resolver.persistedUriPermissions.any {
        it.uri == tree && it.isWritePermission
    }

    private fun folderDoc(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun displayName(tree: Uri): String? {
        resolver.query(
            folderDoc(tree),
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        )?.use { if (it.moveToFirst()) return it.getString(0) }
        return null
    }

    private fun findChild(tree: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null, null, null,
        )?.use {
            while (it.moveToNext()) {
                if (it.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0))
                }
            }
        }
        return null
    }

    // ---- Writing ----

    // The new content goes into "<name>.part" first; only once that is
    // complete does it replace the old file. A write that breaks off (app
    // killed, storage full) thus never destroys the last good backup.
    // octet-stream for the part: with a typed MIME, some providers append
    // their own extension to the name.
    private fun writeFile(tree: Uri, name: String, source: File) {
        if (!canWrite(tree)) throw IllegalStateException("No access to the folder any more")
        val folder = folderDoc(tree)
        val partName = "$name.part"
        findChild(tree, partName)?.let { DocumentsContract.deleteDocument(resolver, it) }
        val part = DocumentsContract.createDocument(resolver, folder, OCTET, partName)
            ?: throw IllegalStateException("Could not create a file in the folder")
        copy(source, part)

        findChild(tree, name)?.let { DocumentsContract.deleteDocument(resolver, it) }
        val renamed = try {
            DocumentsContract.renameDocument(resolver, part, name)
        } catch (_: Exception) {
            null
        }
        if (renamed != null) return

        // Provider without rename: write the target directly, then drop
        // the part.
        val target = findChild(tree, name)
            ?: DocumentsContract.createDocument(resolver, folder, OCTET, name)
            ?: throw IllegalStateException("Could not create a file in the folder")
        copy(source, target)
        DocumentsContract.deleteDocument(resolver, part)
    }

    private fun copy(source: File, target: Uri) {
        // "wt": truncate — otherwise a shorter file keeps the old tail.
        val out = resolver.openOutputStream(target, "wt")
            ?: throw IllegalStateException("Could not open the file for writing")
        out.use { o -> source.inputStream().use { it.copyTo(o, 1 shl 16) } }
    }

    // ---- Activity ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
        activity = null
    }

    companion object {
        private const val REQUEST_PICK = 0xBEAD
        private const val OCTET = "application/octet-stream"
        private const val RW =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }
}
