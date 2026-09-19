import 'dart:io' show Platform;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../rust_bridge/api.dart' as rust;

/// Discovered Wi-Fi Direct P2P peer.
class WifiDirectPeer {
  final String deviceName;
  final String deviceAddress;
  final String primaryDeviceType;
  final int status;

  const WifiDirectPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.primaryDeviceType,
    required this.status,
  });

  factory WifiDirectPeer.fromMap(Map<dynamic, dynamic> map) {
    return WifiDirectPeer(
      deviceName: map['deviceName'] as String? ?? 'Unknown',
      deviceAddress: map['deviceAddress'] as String? ?? '',
      primaryDeviceType: map['primaryDeviceType'] as String? ?? '',
      status: map['status'] as int? ?? 3,
    );
  }
}

/// Information about the active Wi-Fi Direct P2P group.
class WifiDirectConnectionInfo {
  final bool groupFormed;
  final bool isGroupOwner;
  final String groupOwnerAddress;

  const WifiDirectConnectionInfo({
    required this.groupFormed,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });

  factory WifiDirectConnectionInfo.fromMap(Map<dynamic, dynamic> map) {
    return WifiDirectConnectionInfo(
      groupFormed: map['groupFormed'] as bool? ?? false,
      isGroupOwner: map['isGroupOwner'] as bool? ?? false,
      groupOwnerAddress: map['groupOwnerAddress'] as String? ?? '',
    );
  }
}

/// Service managing Wi-Fi Direct peer discovery, group formation, and high-speed
/// P2P data synchronization (Android <-> Windows tier).
class WifiDirectService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('cycles/wifi_direct');

  bool _isSupported = false;
  bool _isDiscovering = false;
  bool _isConnected = false;
  List<WifiDirectPeer> _peers = [];
  WifiDirectConnectionInfo? _connectionInfo;
  String? _statusMessage;

  bool get isSupported => _isSupported;
  bool get isDiscovering => _isDiscovering;
  bool get isConnected => _isConnected;
  List<WifiDirectPeer> get peers => _peers;
  WifiDirectConnectionInfo? get connectionInfo => _connectionInfo;
  String? get statusMessage => _statusMessage;

  /// Initializes platform channel event listeners and checks device support.
  Future<void> init() async {
    // Wi-Fi Direct is scoped to Android and Windows per PLAN.md
    if (kIsWeb || (!Platform.isAndroid && !Platform.isWindows)) {
      _isSupported = false;
      _statusMessage = 'Wi-Fi Direct is not supported on this platform';
      notifyListeners();
      return;
    }

    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handlePlatformCall);
      try {
        final supported = await _channel.invokeMethod<bool>('isSupported');
        _isSupported = supported ?? false;
      } catch (e) {
        _isSupported = false;
        debugPrint('WifiDirectService support check failed: $e');
      }
    } else if (Platform.isWindows) {
      // Windows WinRT WiFiDirect support exists; flagged as needing physical Windows host verification
      _isSupported = true;
    }

    notifyListeners();
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPeersDiscovered':
        final list = (call.arguments as List<dynamic>?) ?? [];
        _peers = list
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => WifiDirectPeer.fromMap(m))
            .toList();
        notifyListeners();
        break;
      case 'onConnectionChanged':
        final map = (call.arguments as Map<dynamic, dynamic>?) ?? {};
        _connectionInfo = WifiDirectConnectionInfo.fromMap(map);
        _isConnected = _connectionInfo?.groupFormed ?? false;
        notifyListeners();
        break;
      case 'onStateChanged':
        final enabled = call.arguments as bool? ?? false;
        if (!enabled) {
          _peers = [];
          _isConnected = false;
        }
        notifyListeners();
        break;
    }
  }

  /// Initiates peer discovery.
  Future<void> discover() async {
    if (!_isSupported) return;
    _isDiscovering = true;
    _statusMessage = 'Scanning for Wi-Fi Direct peers...';
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<bool>('discoverPeers');
        final currentPeers =
            await _channel.invokeMethod<List<dynamic>>('getDiscoveredPeers');
        if (currentPeers != null) {
          _peers = currentPeers
              .whereType<Map<dynamic, dynamic>>()
              .map((m) => WifiDirectPeer.fromMap(m))
              .toList();
        }
      }
      _statusMessage = 'Found ${_peers.length} Wi-Fi Direct peers';
    } catch (e) {
      _statusMessage = 'Discovery error: $e';
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  /// Connects to a remote Wi-Fi Direct device address.
  Future<bool> connect(String deviceAddress) async {
    if (!_isSupported) return false;
    _statusMessage = 'Connecting to $deviceAddress...';
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        final ok = await _channel.invokeMethod<bool>('connect', {
          'deviceAddress': deviceAddress,
        });
        if (ok == true) {
          _statusMessage = 'Wi-Fi Direct connection established';
          await updateConnectionInfo();
          return true;
        }
      }
      return false;
    } catch (e) {
      _statusMessage = 'Connect failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Refreshes the active group connection information.
  Future<WifiDirectConnectionInfo?> updateConnectionInfo() async {
    if (Platform.isAndroid) {
      try {
        final map = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('getConnectionInfo');
        if (map != null) {
          _connectionInfo = WifiDirectConnectionInfo.fromMap(map);
          _isConnected = _connectionInfo?.groupFormed ?? false;
          notifyListeners();
          return _connectionInfo;
        }
      } catch (e) {
        debugPrint('Failed to get connection info: $e');
      }
    }
    return null;
  }

  /// Disconnects and dissolves the active P2P group.
  Future<void> disconnect() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('disconnect');
      } catch (e) {
        debugPrint('Disconnect failed: $e');
      }
    }
    _isConnected = false;
    _connectionInfo = null;
    notifyListeners();
  }

  /// Synchronizes tasks over the established Wi-Fi Direct IP link.
  Future<rust.WifiDirectSyncReport> syncWithPeer({
    required String peerId,
    required String ipAddress,
    required AppDatabase db,
  }) async {
    _statusMessage = 'Syncing with $peerId over Wi-Fi Direct...';
    notifyListeners();

    try {
      final report = await rust.syncWithPeerWifiDirect(
        peerId: peerId,
        address: ipAddress,
      );

      if (report.success) {
        final allTasks = await rust.allTasks();
        for (final t in allTasks) {
          await db.upsertTask(
            TasksCompanion(
              id: Value(t.id),
              projectId: Value(t.projectId),
              title: Value(t.title),
              notes: Value(t.notes),
              due: Value(
                t.dueMillis != null
                    ? DateTime.fromMillisecondsSinceEpoch(t.dueMillis!.toInt())
                    : null,
              ),
              tags: Value(t.tags.join(',')),
              status: Value(t.status),
              priority: Value(t.priority),
              createdAt: Value(
                DateTime.fromMillisecondsSinceEpoch(
                  t.createdAtMillis.toInt(),
                ),
              ),
              updatedAt: Value(
                DateTime.fromMillisecondsSinceEpoch(
                  t.updatedAtMillis.toInt(),
                ),
              ),
            ),
          );
        }
        _statusMessage =
            'Wi-Fi Direct sync succeeded (${report.tasksUpdated} tasks updated)';
      } else {
        _statusMessage = 'Wi-Fi Direct sync failed: ${report.message}';
      }

      notifyListeners();
      return report;
    } catch (e) {
      _statusMessage = 'Wi-Fi Direct sync error: $e';
      notifyListeners();
      return rust.WifiDirectSyncReport(
        peerId: peerId,
        success: false,
        message: e.toString(),
        tasksUpdated: BigInt.zero,
      );
    }
  }
}
