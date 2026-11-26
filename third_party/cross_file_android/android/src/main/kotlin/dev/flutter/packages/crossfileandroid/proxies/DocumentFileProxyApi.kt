// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package dev.flutter.packages.crossfileandroid.proxies

import androidx.core.net.toUri
import androidx.documentfile.provider.DocumentFile
import android.provider.DocumentsContract
import java.io.IOException
import dev.flutter.packages.crossfileandroid.ProxyApiRegistrar

/**
 * ProxyApi implementation for [DocumentFile].
 *
 * This class may handle instantiating native object instances that are attached to a Dart instance
 * or handle method calls on the associated native class or an instance of that class.
 */
class DocumentFileProxyApi(override val pigeonRegistrar: ProxyApiRegistrar) :
    PigeonApiDocumentFile(pigeonRegistrar) {
  override fun fromSingleUri(singleUri: String): DocumentFile {
    // Only returns null on platforms below Android 19.
    return DocumentFile.fromSingleUri(pigeonRegistrar.context, singleUri.toUri())!!
  }

  override fun fromTreeUri(treeUri: String): DocumentFile {
    // Only returns null on platforms below Android 19.
    return DocumentFile.fromTreeUri(pigeonRegistrar.context, treeUri.toUri())!!
  }

  override fun canRead(pigeon_instance: DocumentFile): Boolean {
    if (pigeon_instance.canRead()) return true
    // FileProvider supports OpenableColumns, but not DocumentsContract's MIME
    // column. Its readable streams must not be rejected as non-documents.
    return try {
      pigeonRegistrar.context.contentResolver.openInputStream(pigeon_instance.uri)?.use { true } ?: false
    } catch (_: IOException) {
      false
    } catch (_: SecurityException) {
      false
    } catch (_: IllegalArgumentException) {
      false
    }
  }

  override fun delete(pigeon_instance: DocumentFile): Boolean {
    return pigeon_instance.delete()
  }

  override fun exists(pigeon_instance: DocumentFile): Boolean {
    return if (DocumentsContract.isDocumentUri(pigeonRegistrar.context, pigeon_instance.uri)) {
      pigeon_instance.exists()
    } else {
      // Generic providers may return metadata even for a missing child.
      canRead(pigeon_instance)
    }
  }

  override fun lastModified(pigeon_instance: DocumentFile): Long {
    return pigeon_instance.lastModified()
  }

  override fun length(pigeon_instance: DocumentFile): Long {
    return pigeon_instance.length()
  }

  override fun isFile(pigeon_instance: DocumentFile): Boolean {
    if (pigeon_instance.isFile) return true
    return try {
      val mime = pigeonRegistrar.context.contentResolver.getType(pigeon_instance.uri)
      !mime.isNullOrEmpty() && mime != DocumentsContract.Document.MIME_TYPE_DIR
    } catch (_: SecurityException) {
      false
    } catch (_: IllegalArgumentException) {
      false
    }
  }

  override fun isDirectory(pigeon_instance: DocumentFile): Boolean {
    return pigeon_instance.isDirectory
  }

  override fun listFiles(pigeon_instance: DocumentFile): List<DocumentFile> {
    return pigeon_instance.listFiles().toList()
  }

  override fun getUri(pigeon_instance: DocumentFile): String {
    return pigeon_instance.uri.toString()
  }

  override fun getName(pigeon_instance: DocumentFile): String? {
    return pigeon_instance.name
  }
}
