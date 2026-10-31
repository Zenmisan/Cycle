import 'package:flutter/material.dart';

/// Parses a hex color string (e.g. '#009688', '009688', '#fff', '#ff009688')
/// safely without throwing FormatException on invalid input.
Color parseProjectColor(String? hexString, {Color fallback = const Color(0xFF009688)}) {
  if (hexString == null) return fallback;
  var hex = hexString.trim().replaceAll('#', '');
  if (hex.isEmpty) return fallback;

  // Handle 3-character shorthand '#RGB' -> 'RRGGBB'
  if (hex.length == 3) {
    hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
  }

  // Handle standard 6-character '#RRGGBB'
  if (hex.length == 6) {
    hex = 'FF$hex';
  }

  if (hex.length != 8) return fallback;

  final val = int.tryParse(hex, radix: 16);
  if (val == null) return fallback;
  return Color(val);
}

/// Displays a deletion confirmation modal. Returns true if confirmed.
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Reusable clean empty state widget for lists.
Widget buildEmptyState({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final theme = Theme.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    ),
  );
}
