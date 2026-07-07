import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'cashier_screen.dart';
import 'membership_screen.dart';
import 'report_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import '../services/db_service.dart';
import '../models/staff_member.dart';

const _navy = Color(0xFF623609);
const _grey = Color(0xFFD6CFC6);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  Timer? _syncTimer;

  final _screens = const [
    CashierScreen(),
    MembershipScreen(),
    InventoryScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Sinkron diem-diem di background — gak ada tombol manual, gak ada
    // notifikasi yang ganggu kasir. Jalan tiap 2 menit selama app kebuka.
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      DbService.pullFromCloud();
      DbService.retryPendingSyncs();
    });
    // Coba sekali langsung pas app kebuka juga.
    DbService.pullFromCloud();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPairingForm() async {
    final urlCtrl = TextEditingController(text: DbService.syncServerUrl);
    final keyCtrl = TextEditingController(text: DbService.syncApiKey);

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Dashboard', style: TextStyle(color: _navy)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Get the server URL & API code from the web dashboard → Settings → Sync.',
                style: TextStyle(fontSize: 12, color: const Color(0xFF623609)),
              ),
              const SizedBox(height: 12),
              TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL Server Sync'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'API Code')),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              if (urlCtrl.text.trim().isEmpty || keyCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DbService.setSyncServerUrl(urlCtrl.text.trim());
      await DbService.setSyncApiKey(keyCtrl.text.trim());
      if (mounted) setState(() {});
      await DbService.pullFromCloud();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openStartShiftForm() async {
    final staffList = DbService.staffList;
    final cashCtrl = TextEditingController(text: '0');

    if (staffList.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Staff Configured', style: TextStyle(color: _navy)),
          content: const Text('Add at least one cashier or supervisor in the dashboard before starting a shift.'),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _navy),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    StaffMember? selectedStaff = staffList.first;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Start Shift', style: TextStyle(color: _navy)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<StaffMember>(
                  initialValue: selectedStaff,
                  decoration: const InputDecoration(labelText: 'Cashier'),
                  items: staffList
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text('${s.name} (${s.role == 'supervisor' ? 'Supervisor' : 'Cashier'})'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedStaff = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cashCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Starting Cash'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _navy),
              onPressed: () {
                if (selectedStaff == null) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Start Shift'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && selectedStaff != null) {
      await DbService.setCurrentCashier(name: selectedStaff!.name, email: '');
      await DbService.startShift(startingCash: int.tryParse(cashCtrl.text) ?? 0);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DbService.isPaired) {
      return Scaffold(
        backgroundColor: _grey,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', height: 140),
                const SizedBox(height: 24),
                const Text('Device Not Connected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                const SizedBox(height: 8),
                const Text(
                  'Connect this device to your business dashboard first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: const Color(0xFF623609)),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  onPressed: _openPairingForm,
                  child: const Text('Connect Now'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder(
      valueListenable: DbService.shifts.listenable(),
      builder: (context, box, _) {
        if (DbService.currentOpenShift == null) {
          return Scaffold(
            backgroundColor: _grey,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo.png', height: 160),
                    const SizedBox(height: 32),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                      onPressed: _openStartShiftForm,
                      child: const Text('Start Shift', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          body: _screens[_index],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'),
              NavigationDestination(icon: Icon(Icons.card_membership), label: 'Member'),
              NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventory'),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Report'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}
