import 'package:flutter/material.dart';
import 'cashier_screen.dart';
import 'membership_screen.dart';
import 'report_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import '../services/db_service.dart';
import '../services/app_strings.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [
    CashierScreen(),
    MembershipScreen(),
    InventoryScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  Future<void> _openStartShiftForm() async {
    final nameCtrl = TextEditingController(text: DbService.currentCashierName);
    final emailCtrl = TextEditingController(text: DbService.currentCashierEmail);
    final cashCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('mulai_shift'), style: const TextStyle(color: _navy)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('nama_kasir'))),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: InputDecoration(labelText: AppStrings.t('email_kasir')), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 8),
              TextField(
                controller: cashCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: AppStrings.t('modal_awal')),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(AppStrings.t('mulai_shift')),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DbService.setCurrentCashier(name: nameCtrl.text.trim(), email: emailCtrl.text.trim());
      await DbService.startShift(startingCash: int.tryParse(cashCtrl.text) ?? 0);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Text(AppStrings.t('mulai_shift'), style: const TextStyle(fontSize: 16)),
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.point_of_sale), label: AppStrings.t('nav_kasir')),
          NavigationDestination(icon: const Icon(Icons.card_membership), label: AppStrings.t('nav_member')),
          NavigationDestination(icon: const Icon(Icons.inventory_2), label: AppStrings.t('nav_inventory')),
          NavigationDestination(icon: const Icon(Icons.bar_chart), label: AppStrings.t('nav_laporan')),
          NavigationDestination(icon: const Icon(Icons.settings), label: AppStrings.t('nav_setelan')),
        ],
      ),
    );
  }
}
