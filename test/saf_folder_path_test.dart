import 'package:flutter_test/flutter_test.dart';
import 'package:saf_folder/saf_folder.dart';

void main() {
  const storage = 'content://com.android.externalstorage.documents/tree';
  const downloads = 'content://com.android.providers.downloads.documents/tree';

  test('a folder in internal storage shows its whole path', () {
    expect(
      SafFolder.pathOf('$storage/primary%3ADocuments%2Fbeand%2FBackups'),
      'Internal storage/Documents/beand/Backups',
    );
  });

  test('the top of a volume is just the volume', () {
    expect(SafFolder.pathOf('$storage/primary%3A'), 'Internal storage');
  });

  test('an SD card keeps its volume name', () {
    expect(
      SafFolder.pathOf('$storage/1A2B-3C4D%3ABackups'),
      '1A2B-3C4D/Backups',
    );
  });

  test('the Download folder has no path in its URI but a known place', () {
    expect(
      SafFolder.pathOf('$downloads/downloads'),
      'Internal storage/Download',
    );
    expect(
      SafFolder.pathOf(
        '$downloads/raw%3A%2Fstorage%2Femulated%2F13%2FDownload%2Fbeand',
      ),
      'Internal storage/Download/beand',
    );
  });

  test('without a readable path there is none', () {
    expect(SafFolder.pathOf('$downloads/msd%3A1234'), isNull);
    expect(
      SafFolder.pathOf(
        'content://org.nextcloud.documents/tree/opaque%2Fdocument',
      ),
      isNull,
    );
    expect(SafFolder.pathOf('bookmark:AAAA'), isNull);
  });
}
