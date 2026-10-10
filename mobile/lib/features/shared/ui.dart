import 'package:flutter/material.dart';

import '../../domain/entities.dart';

class StatusChip extends StatelessWidget {
  final EmergencyStatus status;
  const StatusChip({super.key, required this.status});

  Color get _color => switch (status) {
        EmergencyStatus.active => Colors.green,
        EmergencyStatus.degraded => Colors.orange,
        EmergencyStatus.failed => Colors.red,
        EmergencyStatus.resolved || EmergencyStatus.cancelled => Colors.blueGrey,
        _ => Colors.amber.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(6)),
      child: Text(
        status.persianLabel,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String? message;
  const ErrorBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
    );
  }
}
