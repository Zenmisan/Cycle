import 'package:drift/drift.dart' show Value;
import '../data/database.dart';
import '../rust_bridge/api.dart' as rust;
import 'ble_sync_service.dart';
import 'wifi_direct_service.dart';

/// Available transport tiers in order of throughput and preference.
enum TransportTier {
  /// Highest throughput: Direct Wi-Fi P2P link (Android <-> Windows only).
  wifiDirect,

  /// Fast-path: Shared local subnet Wi-Fi via mDNS and TCP.
  lan,

  /// Universal fallback: Low-power Bluetooth Low Energy GATT transport.
  ble,

  /// Last resort: opt-in relay server, for a peer with no proximity
  /// connection available at all. Only attempted if the user has enabled it
  /// in settings and configured a relay URL.
  relay,
}

/// Consolidated result of a multi-transport synchronization attempt.
class MultiTransportSyncResult {
  final TransportTier tierUsed;
  final bool success;
  final String message;
  final int tasksUpdated;

  const MultiTransportSyncResult({
    required this.tierUsed,
    required this.success,
    required this.message,
    required this.tasksUpdated,
  });
}

/// Orchestrates peer sync with tiered fallback priority:
/// Wi-Fi Direct > LAN mDNS > BLE GATT.
///
/// If an Android <-> Windows pairing is detected and Wi-Fi Direct is available,
/// Wi-Fi Direct is attempted first. If it fails or is unavailable, LAN mDNS
/// is attempted next. If LAN is unavailable, it gracefully falls back to BLE.
Future<MultiTransportSyncResult> syncPeerWithPriority({
  required rust.BlePeer peer,
  required BleSyncService bleService,
  required WifiDirectService wifiDirectService,
  required AppDatabase db,
  String? lanIpAddress,
  String? wifiDirectIpAddress,
  bool isAndroidWindowsPair = false,
}) async {
  // Tier 1: Wi-Fi Direct (highest speed, P2P Wi-Fi link for Android <-> Windows)
  if (isAndroidWindowsPair &&
      wifiDirectIpAddress != null &&
      wifiDirectIpAddress.isNotEmpty &&
      wifiDirectService.isSupported) {
    try {
      final report = await wifiDirectService.syncWithPeer(
        peerId: peer.deviceId,
        ipAddress: wifiDirectIpAddress,
        db: db,
      );
      if (report.success) {
        return MultiTransportSyncResult(
          tierUsed: TransportTier.wifiDirect,
          success: true,
          message: report.message,
          tasksUpdated: report.tasksUpdated.toInt(),
        );
      }
    } catch (_) {
      // Fall through to next tier
    }
  }

  // Tier 2: LAN mDNS (opportunistic fast-path when on same Wi-Fi router)
  if (lanIpAddress != null && lanIpAddress.isNotEmpty) {
    try {
      final lanReport = await rust.syncWithPeerLan(
        peerId: peer.deviceId,
        address: lanIpAddress,
      );
      if (lanReport.success) {
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
        return MultiTransportSyncResult(
          tierUsed: TransportTier.lan,
          success: true,
          message: 'Synced over LAN fast-path (${lanReport.tasksUpdated} tasks updated)',
          tasksUpdated: lanReport.tasksUpdated.toInt(),
        );
      }
    } catch (_) {
      // Fall through to next tier
    }
  }

  // Tier 3: BLE GATT (universal proximity transport, works with zero shared networks)
  final bleReport = await bleService.syncWithPeer(peer, db);
  if (bleReport.success) {
    return MultiTransportSyncResult(
      tierUsed: TransportTier.ble,
      success: true,
      message: bleReport.message,
      tasksUpdated: bleReport.tasksUpdated.toInt(),
    );
  }

  // Tier 4: relay (opt-in, last resort — peer has no proximity connection
  // at all). Only attempted if the user enabled it and configured a URL;
  // never default-on. If unavailable/disabled, fall back to the BLE result
  // above (even on failure — it's the most informative message we have).
  final relaySettings = await db.getRelaySettings();
  if (relaySettings.enabled && relaySettings.relayUrl.isNotEmpty) {
    try {
      final relayReport = await rust.syncWithPeerRelay(
        peerId: peer.deviceId,
        relayUrl: relaySettings.relayUrl,
        token: relaySettings.token,
      );
      if (relayReport.success) {
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
        return MultiTransportSyncResult(
          tierUsed: TransportTier.relay,
          success: true,
          message: 'Synced via relay (${relayReport.tasksUpdated} tasks updated)',
          tasksUpdated: relayReport.tasksUpdated.toInt(),
        );
      }
    } catch (_) {
      // Fall through to the BLE result below.
    }
  }

  return MultiTransportSyncResult(
    tierUsed: TransportTier.ble,
    success: bleReport.success,
    message: bleReport.message,
    tasksUpdated: bleReport.tasksUpdated.toInt(),
  );
}
