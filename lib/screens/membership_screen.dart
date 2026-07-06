import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    DateTime? birthDate;
    final dateFmt = DateFormat('dd MMM yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Register New Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      birthDate == null ? 'Birthday (optional)' : 'Birthday: ${dateFmt.format(birthDate!)}',
                      style: const TextStyle(fontSize: 13, color: _navy),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1930),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => birthDate = picked);
                    },
                    child: const Text('Pick'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _navy),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
      final member = Member(
        id: _uuid.v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        joinedAt: DateTime.now(),
        birthDate: birthDate,
      );
      await DbService.saveMember(member);
      setState(() {
        _found = member;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DbService.isProActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Member')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: _navy),
                const SizedBox(height: 16),
                const Text('Member Accounts is a Pro Feature', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                const SizedBox(height: 8),
                const Text(
                  'Upgrade your plan from the dashboard to unlock member accounts and loyalty points.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The full member list (all customer data) is available in the admin dashboard. '
              'Here the cashier can only search one number to check points or register a new member.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Search by phone number', hintText: '08xxxxxxxxxx'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: _search,
                  child: const Text('Search'),
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
                  trailing: Text('${_found!.points} points', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ),
              )
            else if (_searched && _found == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Member not found.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: _addMember,
                    child: const Text('Register New Member'),
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
