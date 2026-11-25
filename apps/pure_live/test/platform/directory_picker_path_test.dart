import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/directory_picker_path.dart';

void main() {
  test('directory picks preserve desktop paths and the Android user-specific primary volume', () {
    expect(pickedDirectoryPath(Uri.parse('file:///home/user/My%20Records'), windows: false), '/home/user/My Records');
    expect(pickedDirectoryPath(Uri.parse('file:///C:/Records'), windows: true), r'C:\Records');
    expect(
      pickedDirectoryPath(
        Uri.parse('content://com.android.externalstorage.documents/tree/primary%3AMy%20Records'),
        windows: false,
        externalStorageRoot: '/storage/emulated/10',
      ),
      '/storage/emulated/10/My Records',
    );
    expect(
      pickedDirectoryPath(
        Uri.parse('content://com.android.externalstorage.documents/tree/ABCD-1234%3AVideos'),
        windows: false,
      ),
      '/storage/ABCD-1234/Videos',
    );
  });

  test('a provider URL, missing primary root or escaping tree cannot become a writable path', () {
    for (final value in [
      'content://downloads/tree/primary%3AVideos',
      'content://com.android.externalstorage.documents/tree/primary%3AVideos',
      'content://com.android.externalstorage.documents/tree/ABCD-1234%3A..%2Foutside',
      'content://com.android.externalstorage.documents/tree/ABCD-1234%3A%2Foutside',
      'https://example.test/tree/ABCD-1234%3AVideos',
    ]) {
      expect(pickedDirectoryPath(Uri.parse(value), windows: false), isNull, reason: value);
    }
  });
}
