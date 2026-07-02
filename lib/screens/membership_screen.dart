import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/member.dart';
import '../services/db_service.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final _uuid = const Uuid();

  Future<void> _addMember() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daftar Member Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'No. HP'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
      final member = Member(
        id: _uuid.v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        joinedAt: DateTime.now(),
      );
      await DbService.members.put(member.id, member);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = DbService.members.values.toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member & Poin'),
        actions: [IconButton(onPressed: _addMember, icon: const Icon(Icons.person_add))],
      ),
      body: members.isEmpty
          ? const Center(child: Text('Belum ada member. Tap + buat daftarin.'))
          : ListView.builder(
              itemCount: members.length,
              itemBuilder: (ctx, i) {
                final m = members[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?')),
                  title: Text(m.name),
                  subtitle: Text(m.phone),
                  trailing: Text('${m.points} poin', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _addMember, child: const Icon(Icons.add)),
    );
  }
}
