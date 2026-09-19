import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../rust_bridge/api.dart' as rust;
import '../rust_bridge/crdt.dart' as rust show TaskRecord;
import 'ble_permission_service.dart';

/// High-level service coordinating BLE device discovery, presence advertising,
/// trust-on-first-use pairing, and CRDT synchronization with nearby peers.
class BleSyncService extends ChangeNotifier {
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

  /// Initializes local device ID and loads trusted peer history.
  Future<void> init() async {
    try {
      _deviceId = await rust.getDeviceId();
      _isAdvertising = await rust.isBleAdvertising();
      await refreshTrustedPeers();
    } catch (e) {
      debugPrint('BleSyncService init error: $e');
    }
    notifyListeners();
  }

  /// Toggles BLE presence advertising (GATT server + LE advertisement).
  Future<void> toggleAdvertising() async {
    try {
      if (_isAdvertising) {
        await rust.stopBleAdvertising();
        _isAdvertising = false;
        _statusMessage = 'Presence advertising stopped';
      } else {
        final permitted = await BlePermissionService.instance.ensureBlePermissions();
        if (!permitted) {
          _statusMessage = 'Bluetooth permission required for presence advertising';
          notifyListeners();
          return;
        }
        final res = await rust.startBleAdvertising();
        _isAdvertising = true;
        _statusMessage = res;
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
      final peers = await rust.scanBlePeers();
      _discoveredPeers = peers;
      _statusMessage = peers.isEmpty
          ? 'No nearby Cycles peers found'
          : 'Found ${peers.length} nearby peer${peers.length == 1 ? '' : 's'}';
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
      final report = await rust.syncWithPeerBle(
        peerId: peer.deviceId,
        address: peer.address,
      );

      if (report.success && report.tasksUpdated.toInt() > 0) {
        // Rehydrate updated tasks from Automerge into Drift's relational tables
        final all = await rust.allTasks();
        for (final r in all) {
          await db.upsertTask(_recordToCompanion(r));
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
