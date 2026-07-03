import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  Future<void> _editProduct(Product p) async {
    final stockCtrl = TextEditingController(text: '${p.stock}');
    String? imageBase64 = p.imageBase64;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(p.name, style: const TextStyle(color: _navy)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 500, maxHeight: 500);
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    setDialogState(() => imageBase64 = base64Encode(bytes));
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      border: Border.all(color: _navy, width: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFCFCFCF),
                    ),
                    child: imageBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(base64Decode(imageBase64!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok saat ini'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () async {
                  await DbService.setStock(p.id, int.tryParse(stockCtrl.text) ?? p.stock);
                  await DbService.setProductImage(p.id, imageBase64);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addProduct() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    String? imageBase64;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Tambah Produk', style: TextStyle(color: _navy)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 500, maxHeight: 500);
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    setDialogState(() => imageBase64 = base64Encode(bytes));
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      border: Border.all(color: _navy, width: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFCFCFCF),
                    ),
                    child: imageBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(base64Decode(imageBase64!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
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
          );
        },
      ),
    );
    if (ok == true && nameCtrl.text.isNotEmpty) {
      await DbService.addProduct(
        name: nameCtrl.text.trim(),
        price: int.tryParse(priceCtrl.text) ?? 0,
        category: 'Jamu',
        stock: int.tryParse(stockCtrl.text) ?? 0,
        imageBase64: imageBase64,
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
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFCFCFCF),
              ),
              child: p.imageBase64 != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(base64Decode(p.imageBase64!), fit: BoxFit.cover),
                    )
                  : const Icon(Icons.local_cafe_outlined, color: _navy, size: 20),
            ),
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
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editProduct(p)),
              ],
            ),
            onTap: () => _editProduct(p),
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
