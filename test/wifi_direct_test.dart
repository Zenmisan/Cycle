import 'package:flutter_test/flutter_test.dart';
import 'package:cycles/services/wifi_direct_service.dart';
import 'package:cycles/services/sync_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WifiDirectPeer & ConnectionInfo models', () {
    test('deserializes peer map correctly', () {
      final map = {
        'deviceName': 'DIRECT-Android-42',
        'deviceAddress': '02:00:00:00:00:00',
        'primaryDeviceType': '10-0050F204-5',
        'status': 3,
      };

      final peer = WifiDirectPeer.fromMap(map);
      expect(peer.deviceName, 'DIRECT-Android-42');
      expect(peer.deviceAddress, '02:00:00:00:00:00');
      expect(peer.primaryDeviceType, '10-0050F204-5');
      expect(peer.status, 3);
    });

    test('deserializes connection info map correctly', () {
      final map = {
        'groupFormed': true,
        'isGroupOwner': true,
        'groupOwnerAddress': '192.168.49.1',
      };

      final info = WifiDirectConnectionInfo.fromMap(map);
      expect(info.groupFormed, isTrue);
      expect(info.isGroupOwner, isTrue);
      expect(info.groupOwnerAddress, '192.168.49.1');
    });
  });

  group('WifiDirectService initialization', () {
    test('initializes gracefully on non-Android host', () async {
      final service = WifiDirectService();
      await service.init();

      // On Linux/macOS host, Wi-Fi Direct is not supported per PLAN.md
      expect(service.isDiscovering, isFalse);
      expect(service.isConnected, isFalse);
      expect(service.peers, isEmpty);
    });
  });

  group('TransportTier enum ordering', () {
    test('tiers represent upgrade hierarchy: wifiDirect > lan > ble > relay', () {
      expect(TransportTier.values.length, 4);
      expect(TransportTier.wifiDirect.index, 0);
      expect(TransportTier.lan.index, 1);
      expect(TransportTier.ble.index, 2);
      expect(TransportTier.relay.index, 3);
    });
  });
}
