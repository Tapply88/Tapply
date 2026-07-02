import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Future<void> _editStock(Product p) async {
    final controller = TextEditingController(text: '${p.stock}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name, style: const TextStyle(color: _navy)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Stok saat ini'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text) ?? p.stock),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result != null) {
      await DbService.setStock(p.id, result);
      setState(() {});
    }
  }

  Future<void> _addProduct() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Produk', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama produk')),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)')),
            TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok awal')),
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
    if (ok == true && nameCtrl.text.isNotEmpty) {
      await DbService.addProduct(
        name: nameCtrl.text.trim(),
        price: int.tryParse(priceCtrl.text) ?? 0,
        category: 'Jamu',
        stock: int.tryParse(stockCtrl.text) ?? 0,
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = DbService.products.values.toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [IconButton(onPressed: _addProduct, icon: const Icon(Icons.add))],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final p = items[i];
          final low = p.stock <= 5;
          return ListTile(
            title: Text(p.name),
            subtitle: Text(_currency.format(p.price)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: low ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: low ? Colors.red : Colors.green),
                  ),
                  child: Text(
                    'Stok: ${p.stock}',
                    style: TextStyle(
                      color: low ? Colors.red.shade800 : Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editStock(p)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: _addProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}
