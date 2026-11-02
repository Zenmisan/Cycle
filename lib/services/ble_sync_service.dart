import 'dart:io' show Platform;
import 'dart:math';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../data/sync_bridge.dart';
import '../rust_bridge/api.dart' as rust;
import '../rust_bridge/crdt.dart' as rust show TaskRecord;
import 'ble_permission_service.dart';

/// High-level service coordinating BLE device discovery, presence advertising,
/// trust-on-first-use pairing, and CRDT synchronization with nearby peers across
/// Android (native BLE GATT), Linux (Rust BlueZ), and iOS (CoreBluetooth).
class BleSyncService extends ChangeNotifier {
  static const MethodChannel _androidChannel = MethodChannel('cycles/ble_gatt');
  static const MethodChannel _iosChannel = MethodChannel('cycles/ble_peripheral');

  AppDatabase? _db;
  String? _deviceId;
  bool _isAdvertising = false;
  bool _isScanning = false;
  List<rust.BlePeer> _discoveredPeers = [];
  List<rust.BlePeerIdentity> _trustedPeers = [];
  String? _statusMessage;

  String? get deviceId => _deviceId;
  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;
  List<rust.BlePeer> get discoveredPeers => _discoveredPeers;
  List<rust.BlePeerIdentity> get trustedPeers => _trustedPeers;
  String? get statusMessage => _statusMessage;

  void setDatabase(AppDatabase db) {
    _db = db;
  }

  /// Initializes local device ID and loads trusted peer history.
  Future<void> init({AppDatabase? db}) async {
    if (db != null) {
      _db = db;
    }

    try {
      _deviceId = await rust.getDeviceId();
      await refreshTrustedPeers();

      if (!kIsWeb && Platform.isAndroid) {
        _androidChannel.setMethodCallHandler(_handleAndroidPlatformCall);
        _isAdvertising = await _androidChannel.invokeMethod<bool>('isAdvertising') ?? false;
      } else if (!kIsWeb && Platform.isIOS) {
        _isAdvertising = await _iosChannel.invokeMethod<bool>('isAdvertising') ?? false;
      } else {
        _isAdvertising = await rust.isBleAdvertising();
      }
    } catch (e) {
      debugPrint('BleSyncService init error: $e');
    }
    notifyListeners();
  }

  Future<dynamic> _handleAndroidPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPeerDiscovered':
        final args = call.arguments as Map<dynamic, dynamic>? ?? {};
        final devId = args['deviceId'] as String? ?? '';
        final name = args['displayName'] as String? ?? 'Cycles-$devId';
        final address = args['address'] as String? ?? '';
        final rssi = args['rssi'] as int?;

        if (devId.isNotEmpty && address.isNotEmpty) {
          final existingIndex = _discoveredPeers.indexWhere((p) => p.address == address || p.deviceId == devId);
          final peer = rust.BlePeer(
            deviceId: devId,
            displayName: name,
            address: address,
            rssi: rssi,
          );

          if (existingIndex >= 0) {
            _discoveredPeers[existingIndex] = peer;
          } else {
            _discoveredPeers.add(peer);
          }
          notifyListeners();
        }
        break;

      case 'onSyncMessageReceived':
        final args = call.arguments as Map<dynamic, dynamic>? ?? {};
        final peerAddress = args['peerAddress'] as String? ?? 'unknown';
        final payload = args['payload'] as Uint8List? ?? Uint8List(0);

        if (_db != null && payload.isNotEmpty) {
          await handleIncomingSyncMessage(_db!, peerAddress, payload);
          // Generate next sync response if needed and enqueue on GATT server
          final nextResponse = await generateSyncMessageFor(peerAddress);
          if (nextResponse != null && nextResponse.isNotEmpty) {
            await _androidChannel.invokeMethod('enqueueServerResponse', {
              'payload': nextResponse,
            });
          }
          await refreshTrustedPeers();
          notifyListeners();
        }
        break;
    }
  }

  /// Toggles BLE presence advertising (GATT server + LE advertisement).
  Future<void> toggleAdvertising() async {
    try {
      if (_isAdvertising) {
        if (!kIsWeb && Platform.isAndroid) {
          await _androidChannel.invokeMethod('stopAdvertising');
        } else if (!kIsWeb && Platform.isIOS) {
          await _iosChannel.invokeMethod('stopAdvertising');
        } else {
          await rust.stopBleAdvertising();
        }
        _isAdvertising = false;
        _statusMessage = 'Presence advertising stopped';
      } else {
        final permitted = await BlePermissionService.instance.ensureBlePermissions();
        if (!permitted) {
          _statusMessage = 'Bluetooth permission required for presence advertising';
          notifyListeners();
          return;
        }

        final devId = _deviceId ?? await rust.getDeviceId();
        final shortId = devId.length > 8 ? devId.substring(0, 8) : devId;
        final advName = 'Cycles-$shortId';

        if (!kIsWeb && Platform.isAndroid) {
          final res = await _androidChannel.invokeMethod<String>('startAdvertising', {
            'deviceId': devId,
            'name': advName,
          });
          _isAdvertising = true;
          _statusMessage = res ?? 'Advertising as $advName';
        } else if (!kIsWeb && Platform.isIOS) {
          final res = await _iosChannel.invokeMethod<String>('startAdvertising', {
            'name': advName,
          });
          _isAdvertising = true;
          _statusMessage = res ?? 'Advertising as $advName';
        } else {
          final res = await rust.startBleAdvertising();
          _isAdvertising = true;
          _statusMessage = res;
        }
      }
    } catch (e) {
      _statusMessage = 'Advertising error: $e';
    }
    notifyListeners();
  }

  /// Scans for nearby Cycles peers over BLE.
  Future<void> scan() async {
    if (_isScanning) return;

    final permitted = await BlePermissionService.instance.ensureBlePermissions();
    if (!permitted) {
      _statusMessage = 'Bluetooth permission required for peer scanning';
      notifyListeners();
      return;
    }

    _isScanning = true;
    _statusMessage = 'Scanning for nearby peers...';
    notifyListeners();

    try {
      if (!kIsWeb && Platform.isAndroid) {
        _discoveredPeers.clear();
        await _androidChannel.invokeMethod('startScan');
        // Scan for 4 seconds to collect nearby LE advertisements
        await Future.delayed(const Duration(seconds: 4));
        await _androidChannel.invokeMethod('stopScan');
        _statusMessage = _discoveredPeers.isEmpty
            ? 'No nearby Cycles peers found'
            : 'Found ${_discoveredPeers.length} nearby peer${_discoveredPeers.length == 1 ? '' : 's'}';
      } else {
        final peers = await rust.scanBlePeers();
        _discoveredPeers = peers;
        _statusMessage = peers.isEmpty
            ? 'No nearby Cycles peers found'
            : 'Found ${peers.length} nearby peer${peers.length == 1 ? '' : 's'}';
      }
    } catch (e) {
      _statusMessage = 'Scan failed: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Refreshes the list of trusted/paired peers from the local store.
  Future<void> refreshTrustedPeers() async {
    try {
      _trustedPeers = await rust.getTrustedPeers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching trusted peers: $e');
    }
  }

  /// Sets whether a peer is trusted.
  Future<void> setPeerTrust(String peerId, bool trusted) async {
    try {
      await rust.setPeerTrust(peerId: peerId, trusted: trusted);
      await refreshTrustedPeers();
    } catch (e) {
      _statusMessage = 'Failed to update trust: $e';
      notifyListeners();
    }
  }

  /// Initiates a BLE sync round with a discovered peer, applying any updated
  /// tasks back into the Drift database.
  Future<rust.BleSyncReport> syncWithPeer(rust.BlePeer peer, AppDatabase db) async {
    _statusMessage = 'Syncing with ${peer.displayName}...';
    notifyListeners();

    try {
      rust.BleSyncReport report;

      if (!kIsWeb && Platform.isAndroid) {
        // Native Android GATT Client sync
        final outgoing = await generateSyncMessageFor(peer.deviceId) ?? Uint8List(0);
        final response = await _androidChannel.invokeMethod<Uint8List>('syncWithPeer', {
          'address': peer.address,
          'peerId': peer.deviceId,
          'payload': outgoing,
        });

        int tasksCount = 0;
        if (response != null && response.isNotEmpty) {
          final updated = await rust.mergeIncoming(peerId: peer.deviceId, bytes: response);
          for (final record in updated) {
            await db.upsertTask(_recordToCompanion(record));
          }
          tasksCount = updated.length;
        }

        report = rust.BleSyncReport(
          peerId: peer.deviceId,
          success: true,
          message: 'Sync completed via Android GATT',
          tasksUpdated: BigInt.from(tasksCount),
        );
      } else {
        // Desktop / Linux BlueZ sync
        report = await rust.syncWithPeerBle(
          peerId: peer.deviceId,
          address: peer.address,
        );

        if (report.success && report.tasksUpdated.toInt() > 0) {
          final all = await rust.allTasks();
          for (final r in all) {
            await db.upsertTask(_recordToCompanion(r));
          }
        }
      }

      await refreshTrustedPeers();
      _statusMessage = report.success
          ? 'Synced with ${peer.displayName} (${report.tasksUpdated} tasks updated)'
          : 'Sync failed: ${report.message}';
      notifyListeners();
      return report;
    } catch (e) {
      final failReport = rust.BleSyncReport(
        peerId: peer.deviceId,
        success: false,
        message: e.toString(),
        tasksUpdated: BigInt.zero,
      );
      _statusMessage = 'Sync error: $e';
      notifyListeners();
      return failReport;
    }
  }

  TasksCompanion _recordToCompanion(rust.TaskRecord r) {
    return TasksCompanion(
      id: Value(r.id),
      projectId: Value(r.projectId),
      title: Value(r.title),
      notes: Value(r.notes),
      due: Value(
        r.dueMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r.dueMillis!),
      ),
      tags: Value(r.tags.join(',')),
      status: Value(r.status),
      priority: Value(r.priority),
      createdAt: Value(DateTime.fromMillisecondsSinceEpoch(r.createdAtMillis)),
      updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(r.updatedAtMillis)),
    );
  }
}
