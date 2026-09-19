import 'package:flutter/material.dart';

import '../data/database.dart';
import '../rust_bridge/api.dart' as rust;
import '../services/ble_sync_service.dart';

class PeersScreen extends StatefulWidget {
  final AppDatabase db;
  final BleSyncService bleService;

  const PeersScreen({
    super.key,
    required this.db,
    required this.bleService,
  });

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  bool _isSyncing = false;
  String? _syncingPeerId;

  @override
  void initState() {
    super.initState();
    widget.bleService.init();
  }

  Future<void> _handleSync(rust.BlePeer peer) async {
    setState(() {
      _isSyncing = true;
      _syncingPeerId = peer.deviceId;
    });

    final report = await widget.bleService.syncWithPeer(peer, widget.db);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncingPeerId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.success
                ? 'Synced with ${peer.displayName}! (${report.tasksUpdated} tasks updated)'
                : 'Sync failed: ${report.message}',
          ),
          backgroundColor: report.success ? Colors.teal : Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, _) {
        final service = widget.bleService;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Nearby Sync'),
            actions: [
              IconButton(
                icon: service.isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Scan for nearby devices',
                onPressed: service.isScanning ? null : () => service.scan(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Local presence card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.teal.withValues(alpha: 0.2),
                            child: const Icon(Icons.bluetooth, color: Colors.teal),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.deviceId != null
                                      ? 'Cycles-${service.deviceId}'
                                      : 'Loading device...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  service.isAdvertising
                                      ? 'Visible to nearby devices'
                                      : 'Presence hidden',
                                  style: TextStyle(
                                    color: service.isAdvertising
                                        ? Colors.teal
                                        : Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: service.isAdvertising,
                            onChanged: (_) => service.toggleAdvertising(),
                          ),
                        ],
                      ),
                      if (service.statusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          service.statusMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Discovered peers section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Nearby Devices',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (service.discoveredPeers.isNotEmpty)
                    Text(
                      '${service.discoveredPeers.length} found',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (service.discoveredPeers.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 48,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No nearby Cycles devices found.\nTap refresh to scan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                ...service.discoveredPeers.map((peer) {
                  final isThisSyncing =
                      _isSyncing && _syncingPeerId == peer.deviceId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.devices),
                      ),
                      title: Text(peer.displayName),
                      subtitle: Text(
                        peer.rssi != null
                            ? '${peer.address} • ${peer.rssi} dBm'
                            : peer.address,
                      ),
                      trailing: ElevatedButton.icon(
                        icon: isThisSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync, size: 16),
                        label: const Text('Sync'),
                        onPressed: _isSyncing ? null : () => _handleSync(peer),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // Trusted peers section
              if (service.trustedPeers.isNotEmpty) ...[
                const Text(
                  'Trusted Peers (Paired)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...service.trustedPeers.map((peer) {
                  final lastSynced = peer.lastSyncedAt > BigInt.zero
                      ? DateTime.fromMillisecondsSinceEpoch(
                          peer.lastSyncedAt.toInt() * 1000,
                        ).toLocal().toString().substring(0, 16)
                      : 'Never';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        peer.trusted ? Icons.verified : Icons.lock_outline,
                        color: peer.trusted ? Colors.teal : Colors.grey,
                      ),
                      title: Text(peer.displayName),
                      subtitle: Text('Last synced: $lastSynced'),
                      trailing: IconButton(
                        icon: Icon(
                          peer.trusted ? Icons.check_circle : Icons.remove_circle,
                          color: peer.trusted ? Colors.teal : Colors.grey,
                        ),
                        tooltip: peer.trusted ? 'Trusted' : 'Untrusted',
                        onPressed: () => service.setPeerTrust(
                          peer.deviceId,
                          !peer.trusted,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
