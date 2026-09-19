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

  test('BLE local device ID is non-empty and 8 characters', () async {
    final deviceId = await rust.getDeviceId();
    expect(deviceId, isNotEmpty);
    expect(deviceId.length, 8);
  });

  test('BLE advertising state query', () async {
    final advertising = await rust.isBleAdvertising();
    expect(advertising, isA<bool>());
  });

  test('BLE peer trust and storage operations', () async {
    final initialPeers = await rust.getTrustedPeers();
    expect(initialPeers, isA<List<rust.BlePeerIdentity>>());

    // Test sync report generation
    final report = await rust.syncWithPeerBle(
      peerId: 'peer0001',
      address: '00:11:22:33:44:55',
    );
    expect(report.peerId, 'peer0001');
    expect(report.success, isTrue);

    // Verify peer is in peer store after handshake
    final peers = await rust.getTrustedPeers();
    final peer = peers.firstWhere((p) => p.deviceId == 'peer0001');
    expect(peer.trusted, isTrue);

    // Toggle trust
    await rust.setPeerTrust(peerId: 'peer0001', trusted: false);
    final updatedPeers = await rust.getTrustedPeers();
    final updatedPeer = updatedPeers.firstWhere((p) => p.deviceId == 'peer0001');
    expect(updatedPeer.trusted, isFalse);
  });
}
