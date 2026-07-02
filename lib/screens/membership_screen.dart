import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/member.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final _uuid = const Uuid();
  final _searchCtrl = TextEditingController();
  Member? _found;
  bool _searched = false;

  void _search() {
    final result = DbService.findMemberByPhone(_searchCtrl.text.trim());
    setState(() {
      _found = result;
      _searched = true;
    });
  }

  Future<void> _addMember() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _searchCtrl.text.trim());
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
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
      setState(() {
        _found = member;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daftar lengkap member (semua data pelanggan) akan tersedia di dashboard admin. '
              'Di sini kasir hanya bisa cari 1 nomor untuk cek poin atau daftarkan member baru.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Cari no. HP', hintText: '08xxxxxxxxxx'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: _search,
                  child: const Text('Cari'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_searched && _found != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(_found!.name.isNotEmpty ? _found!.name[0].toUpperCase() : '?')),
                  title: Text(_found!.name),
                  subtitle: Text(_found!.phone),
                  trailing: Text('${_found!.points} poin', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ),
              )
            else if (_searched && _found == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Member tidak ditemukan.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: _addMember,
                    child: const Text('Daftarkan Member Baru'),
                  ),
                ],
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: _addMember,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
