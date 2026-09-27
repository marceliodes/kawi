import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/services/platform_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.kawi/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getWindowHandle returns handle when channel responds', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getWindowHandle') {
            return 'x11:0x2a00001';
          }
          return null;
        });

    final handle = await PlatformWindowService.getWindowHandle();
    expect(handle, 'x11:0x2a00001');
  });

  test('getWindowHandle returns null when channel throws exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          throw PlatformException(code: 'UNAVAILABLE');
        });

    final handle = await PlatformWindowService.getWindowHandle();
    expect(handle, isNull);
  });
}
