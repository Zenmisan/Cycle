import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service responsible for verifying and requesting Bluetooth runtime permissions,
/// particularly for Android 12+ (API 31+) which mandates BLUETOOTH_SCAN,
/// BLUETOOTH_CONNECT, and BLUETOOTH_ADVERTISE.
class BlePermissionService {
  BlePermissionService._();
  static final BlePermissionService instance = BlePermissionService._();

  static const MethodChannel _channel = MethodChannel('cycles/ble_permissions');

  /// Checks whether all necessary BLE permissions have been granted.
  Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) {
      return true; // Non-Android platforms don't use Android runtime permissions
    }

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('checkPermissions');
      return res?['granted'] as bool? ?? false;
    } catch (e) {
      debugPrint('[BlePermissionService] Error checking permissions: $e');
      return false;
    }
  }

  /// Requests the required Bluetooth runtime permissions from the user.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('requestPermissions');
      final granted = res?['granted'] as bool? ?? false;
      if (!granted) {
        final denied = res?['deniedPermissions'] as List?;
        debugPrint('[BlePermissionService] Permissions denied: $denied');
      }
      return granted;
    } catch (e) {
      debugPrint('[BlePermissionService] Error requesting permissions: $e');
      return false;
    }
  }

  /// Ensures BLE permissions are active, requesting them if not already granted.
  Future<bool> ensureBlePermissions() async {
    final granted = await checkPermissions();
    if (granted) return true;
    return await requestPermissions();
  }
}
