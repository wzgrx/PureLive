# PureLive Android scoped file correctness

Published source: https://pub.dev/packages/cross_file_android/versions/1.0.0 . LICENSE is retained. Version1.0.0 remains the current published version; this local patch is explicit.

Actual API27 minified-release diagnostics showed a readable FileProvider URI reported canRead=false while returning the correct16078 bytes, length and name.20 complete reads increased native descriptors80→100. DocumentFile assumes DocumentsContract MIME columns, which generic FileProvider does not implement; native streams also had no close method exposed to Dart.

Keep normal document behavior and use an OS-enforced open/close readability check for generic resources. Generic provider existence is checked against real access, not metadata rows which can also describe missing children. File classification falls back to ContentResolver MIME. No permissions or grants are created or broadened.

Add InputStream.close to the Pigeon source and regenerate both ends with upstream generator27.3.2. Existing wire channel names are retained; only the close channel is added. Generated baseline differs from the published postformatted files in formatting/imports, recorded in the local audit. Stream and bulk reads close in finally; cancellation, ranges, errors and non-seekable/partial skips are covered by regression tests. Native preflight20 reads stayed79→79 with byte/range/bulk and metadata checks passing.

The authored test/scoped_stream_lifecycle.dart is included through the app test driver in the normal14-member gate. Native acceptance uses generated local/provider data only. Original upstream test/example directories are omitted from this runtime copy; no existing project tests are removed.
