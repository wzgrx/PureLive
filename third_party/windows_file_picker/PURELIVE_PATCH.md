# PureLive cross_file0.4 compatibility

Upstream published source: https://pub.dev/packages/windows_file_picker/versions/2.0.2
Archive SHA256: cd1be37ada0abcfaa55bddb7410e8515844e35cd77669c35d9a28a15722299d8
License: retained in LICENSE. Published runtime/native sources and public13.x/2.x APIs are preserved.

File picker Dart migration is adapted from https://github.com/vicajilau/flutter_file_picker/pull/2300 at64fcc8a55cc60dca1b962ad45cfe1fb0cf0547d7. Only cross_file-related runtime hunks are replayed onto the stable published versions; unrelated14.0 removals and native behavior changes are excluded. The name/path/bytes/URI APIs consumed by PureLive stay compatible.

Share packages are adapted to asynchronous XFile metadata and FileSystemXFile/scoped storage. Scoped resources are streamed to an isolated temporary folder before invoking the existing native share channel. Native Android/Apple/Windows implementations are unchanged. Web file names and MIME lookup follow cross_file0.4 metadata.

Dependency bounds now allow cross_file0.4 and its supported SDK floor. No patch changes the upstream cross_file implementation or invents a newer upstream package version. Root overrides select these reproducible local consumers. Regression and platform acceptance are recorded in docs/Z-工程文档和维护/Z01-工具链和依赖/Z01.5-剩余依赖文件接口升级/.

This runtime copy omits upstream example/test directories; their original contents are retained in the local upgrade audit, and project migration regression tests cover real file bytes, scoped URI types and streams, share arguments, cancellation and failed-copy cleanup. No pre-existing project tests were removed. PURELIVE_PATCH.diff contains the exact runtime/pubspec delta against the published archive.
