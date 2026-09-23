import 'package:flutter_eml_msg_viewer/src/platform/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeBridge', () {
    test('getTemporaryDirectory returns fallback path in test environment', () async {
      final path = await NativeBridge.getTemporaryDirectory();
      expect(path, isNotEmpty);
    });

    test('openFile gracefully returns an error in unimplemented test environment', () async {
      final opened = await NativeBridge.openFile('/invalid/path/file.pdf');
      expect(opened, isNotNull);
    });
  });
}
