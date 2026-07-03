import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/variation.dart';
import '../models/addon.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

class VariantsScreen extends StatefulWidget {
  const VariantsScreen({super.key});

  @override
  State<VariantsScreen> createState() => _VariantsScreenState();
}

class _VariantsScreenState extends State<VariantsScreen> {
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Future<void> _editVariation({Variation? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Varian Baru' : 'Edit Varian', style: const TextStyle(color: _navy)),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama varian', hintText: 'mis. Hangat, Dingin, Less Ice')),
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
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      if (existing != null) {
        await DbService.updateVariation(existing.id, nameCtrl.text.trim());
      } else {
        await DbService.addVariation(nameCtrl.text.trim());
      }
      setState(() {});
    }
  }

  Future<void> _deleteVariation(Variation v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Varian?'),
        content: Text('Yakin mau hapus "${v.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await DbService.deleteVariation(v.id);
      setState(() {});
    }
  }

  Future<void> _editAddon({Addon? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? '${existing.price}' : '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambahan Baru' : 'Edit Tambahan', style: const TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama tambahan', hintText: 'mis. Extra Madu')),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Harga tambahan (Rp, 0 = gratis)'),
            ),
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
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final price = int.tryParse(priceCtrl.text) ?? 0;
      if (existing != null) {
        await DbService.updateAddon(existing.id, name: nameCtrl.text.trim(), price: price);
      } else {
        await DbService.addAddon(name: nameCtrl.text.trim(), price: price);
      }
      setState(() {});
    }
  }

  Future<void> _deleteAddon(Addon a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Tambahan?'),
        content: Text('Yakin mau hapus "${a.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await DbService.deleteAddon(a.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final variations = DbService.variations;
    final addons = DbService.addons;

    return Scaffold(
      appBar: AppBar(title: const Text('Varian & Tambahan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Varian', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
              TextButton.icon(
                onPressed: () => _editVariation(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah'),
              ),
            ],
          ),
          const Text(
            'Pilihan wajib (pilih satu) yang muncul tiap produk ditambah ke keranjang, mis. Hangat/Dingin.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (variations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada varian.', style: TextStyle(color: Colors.grey)),
            )
          else
            ...variations.map((v) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.tune, size: 18, color: _navy),
                  title: Text(v.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editVariation(existing: v)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deleteVariation(v)),
                    ],
                  ),
                )),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tambahan', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
              TextButton.icon(
                onPressed: () => _editAddon(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah'),
              ),
            ],
          ),
          const Text(
            'Pilihan opsional (boleh lebih dari satu), masing-masing bisa punya harga tambahan sendiri.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (addons.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada tambahan.', style: TextStyle(color: Colors.grey)),
            )
          else
            ...addons.map((a) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.add_circle_outline, size: 18, color: _navy),
                  title: Text(a.name),
                  subtitle: Text(a.price > 0 ? '+${_currency.format(a.price)}' : 'Gratis'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editAddon(existing: a)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deleteAddon(a)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
