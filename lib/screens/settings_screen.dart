import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'promo_screen.dart';

const _navy = Color(0xFF092762);

/// Tab "More" — sengaja dibikin minim. Pengaturan bisnis (profil, tax/service,
/// diskon, rounding, PIN, print check, queue number, varian & tambahan)
/// sekarang cuma bisa diatur dari dashboard web, biar kasir gak bisa
/// ubah-ubah kebijakan bisnis dari device. Yang tersisa di sini cuma alat
/// kerja operasional kasir.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pulling = false;

  Future<void> _editPairing() async {
    final urlCtrl = TextEditingController(text: DbService.syncServerUrl);
    final keyCtrl = TextEditingController(text: DbService.syncApiKey);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koneksi Dashboard', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL Server Sync')),
            const SizedBox(height: 8),
            TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Kode API')),
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
    if (ok == true) {
      await DbService.setSyncServerUrl(urlCtrl.text.trim());
      await DbService.setSyncApiKey(keyCtrl.text.trim());
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Cashier Tools', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Business settings (profile, tax/service, discount, rounding, PIN, variants & add-ons, etc.) '
            'are now managed only from the web dashboard, so they stay consistent across every device. '
            'Changes there sync here automatically.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromoScreen())),
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Manage Promo'),
          ),
          const Divider(height: 40),
          const Text('Sync', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            DbService.isPaired ? 'Connected to dashboard.' : 'Not connected yet.',
            style: TextStyle(fontSize: 12, color: DbService.isPaired ? Colors.green : Colors.red),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: _editPairing,
            child: Text(DbService.isPaired ? 'Change Connection' : 'Connect to Dashboard'),
          ),
          if (DbService.pendingSyncCount > 0) ...[
            const SizedBox(height: 10),
            Text('${DbService.pendingSyncCount} item(s) waiting to resend (automatic, no action needed).', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}
