import 'package:flutter/material.dart';

import '../data/database.dart';

/// Minimal settings screen for the phase 6 relay transport — opt-in,
/// off by default. Sync UX for actually *using* the relay to reach a
/// specific out-of-proximity peer belongs with the other transports
/// (`PeersScreen`) once a peer's device_id is known there; this screen only
/// covers enabling it and pointing it at a self-hosted server.
class RelaySettingsScreen extends StatefulWidget {
  final AppDatabase db;
  const RelaySettingsScreen({super.key, required this.db});

  @override
  State<RelaySettingsScreen> createState() => _RelaySettingsScreenState();
}

class _RelaySettingsScreenState extends State<RelaySettingsScreen> {
  bool _enabled = false;
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.db.getRelaySettings();
    setState(() {
      _enabled = settings.enabled;
      _urlController.text = settings.relayUrl;
      _tokenController.text = settings.token;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await widget.db.setRelaySettings(
      enabled: _enabled,
      relayUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relay settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Sync (Relay)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Last-resort sync for a paired device that\'s never in '
                  'BLE/WiFi range — off by default. Point this at your own '
                  'self-hosted relay server; it only ever moves opaque '
                  'bytes, never reads task content.',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enable relay sync'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Relay server URL',
                    hintText: 'wss://relay.example.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Shared secret token',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
    );
  }
}
