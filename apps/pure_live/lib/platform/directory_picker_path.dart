import 'package:path/path.dart' as p;

/// Maps the directory picker's resource URI to the filesystem paths the
/// existing recorder, backup and downloader can actually use. An arbitrary
/// provider URI must never become a Directory("content://...") path.
String? pickedDirectoryPath(Uri? uri, {required bool windows, String? externalStorageRoot}) {
  if (uri == null || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (uri.isScheme('file')) {
    if (!uri.hasAbsolutePath || uri.pathSegments.any((part) => part.contains('/'))) return null;
    if (!windows && uri.host.isNotEmpty && uri.host != 'localhost') return null;
    if (windows && uri.host.isEmpty) {
      if (uri.pathSegments.isEmpty || !RegExp(r'^[a-zA-Z]:$').hasMatch(uri.pathSegments.first)) return null;
      if (uri.pathSegments.skip(1).any((part) => RegExp('[<>:"|?*]').hasMatch(part))) return null;
    }
    return uri.toFilePath(windows: windows);
  }
  if (windows || uri.scheme != 'content') return null;
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments.first != 'tree') return null;
  final document = segments[1];
  // AOSP DownloadStorageProvider uses `downloads` for its root and `raw:`
  // for folder document IDs. MediaStore IDs require provider access and
  // cannot be guessed as filesystem paths.
  if (uri.host == 'com.android.providers.downloads.documents') {
    final root = externalStorageRoot;
    if (root == null || !p.posix.isAbsolute(root)) return null;
    final downloads = p.posix.join(root, 'Download');
    if (document == 'downloads') return downloads;
    if (!document.startsWith('raw:')) return null;
    final path = document.substring(4);
    if (!p.posix.isAbsolute(path) ||
        path.contains(r'\') ||
        path.contains('\u0000') ||
        path.split('/').any((part) => part == '..' || part == '.')) {
      return null;
    }
    return path == downloads || p.posix.isWithin(downloads, path) ? path : null;
  }
  if (uri.host != 'com.android.externalstorage.documents') return null;

  final colon = document.indexOf(':');
  if (colon < 1) return null;
  final volume = document.substring(0, colon);
  final relative = document.substring(colon + 1);
  if (relative.startsWith('/') ||
      relative.contains(r'\') ||
      relative.contains('\u0000') ||
      relative.split('/').any((part) => part == '..' || part == '.')) {
    return null;
  }
  final root = volume == 'primary'
      ? externalStorageRoot
      : RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(volume)
      ? '/storage/$volume'
      : null;
  if (root == null || !p.posix.isAbsolute(root)) return null;
  return relative.isEmpty ? root : p.posix.join(root, relative);
}
