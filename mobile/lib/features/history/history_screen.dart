import 'package:flutter/material.dart';

import '../../domain/entities.dart';
import '../../state/app_state.dart';
import '../shared/ui.dart';

class HistoryScreen extends StatefulWidget {
  final AppState state;
  const HistoryScreen({super.key, required this.state});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    widget.state.loadHistory();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _openDetail(SessionEntity session) async {
    await widget.state.loadEvents(session.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [StatusChip(status: session.status), const SizedBox(width: 10)]),
          const SizedBox(height: 8),
          Text('شروع: ${session.startedAt?.toLocal() ?? "—"}'),
          if (session.resolvedAt != null) Text('پایان: ${session.resolvedAt!.toLocal()}'),
          const Divider(),
          const Text('Event Timeline:', style: TextStyle(fontWeight: FontWeight.bold)),
          ...widget.state.activeEvents.map(
            (e) => ListTile(
              dense: true,
              leading: const Icon(Icons.circle, size: 8),
              title: Text(e.eventType, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              subtitle: e.payload.isEmpty ? null : Text(e.payload.toString(), style: const TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ErrorBanner(message: state.lastError),
        if (state.history.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('هنوز Session‌ای ثبت نشده.')))
        else
          ...state.history.map((s) => Card(
                child: ListTile(
                  leading: StatusChip(status: s.status),
                  title: Text('Session ${s.id.substring(0, 8)}…'),
                  subtitle: Text('شروع: ${s.startedAt?.toLocal() ?? "—"} | تریگر: ${s.triggerType}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => _openDetail(s),
                ),
              )),
      ],
    );
  }
}
