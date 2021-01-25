import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitmap_texture/bitmap_texture.dart';

void main() {
  const MethodChannel channel = MethodChannel('bitmap_texture');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await BitmapTexture.platformVersion, '42');
  });
}
