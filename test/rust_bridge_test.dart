import 'package:flutter_test/flutter_test.dart';
import 'package:cycles/rust_bridge/frb_generated.dart';
import 'package:cycles/rust_bridge/api.dart' as rust;

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  test('ping round-trips through the Rust FFI bridge', () async {
    final result = await rust.ping(name: 'cycles');
    expect(result, 'pong, cycles');
  });
}
