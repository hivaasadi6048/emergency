import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../shared/ui.dart';

class ContactsScreen extends StatefulWidget {
  final AppState state;
  const ContactsScreen({super.key, required this.state});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    widget.state.loadContacts();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _openForm({String? id, String? name, String? phone, String? relationship}) async {
    final nameCtrl = TextEditingController(text: name ?? '');
    final phoneCtrl = TextEditingController(text: phone ?? '');
    final relCtrl = TextEditingController(text: relationship ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? 'افزودن مخاطب' : 'ویرایش مخاطب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')),
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'موبایل (۰۹۱۲… یا +98…)')),
          TextField(controller: relCtrl, decoration: const InputDecoration(labelText: 'نسبت (اختیاری)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (saved != true) return;
    final ok = id == null
        ? await widget.state.addContact(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim(), relationship: relCtrl.text.trim())
        : await widget.state.updateContact(id, name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim(), relationship: relCtrl.text.trim());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.state.lastError ?? 'ذخیره نشد')));
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف مخاطب؟'),
        content: Text('«$name» از مخاطبین شما حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await widget.state.deleteContact(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ErrorBanner(message: state.lastError),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'مخاطبین مورد اعتماد در وضعیت اضطراری از طریق لینک کوتاه‌عمر و قابل لغو، وضعیت و آخرین موقعیت شما را می‌بینند.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ),
        ...state.contacts.map((c) => Card(
              child: ListTile(
                title: Text(c.name),
                subtitle: Text('${c.phone}${c.relationship.isEmpty ? '' : ' — ${c.relationship}'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c.id, c.name),
                ),
                onTap: () => _openForm(id: c.id, name: c.name, phone: c.phone, relationship: c.relationship),
              ),
            )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('افزودن مخاطب'),
        ),
      ],
    );
  }
}
