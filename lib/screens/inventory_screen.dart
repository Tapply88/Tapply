import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/product.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);
const _addNewValue = '__add_new__';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _searchCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd MMM yyyy');
  String _query = '';

  /// Dropdown kategori + opsi "Tambah kategori baru". Mengembalikan kategori terpilih.
  Future<String?> _promptNewCategory(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategori Baru', style: TextStyle(color: _navy)),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'mis. Minuman, Tambahan')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _editProduct(Product p) async {
    final nameCtrl = TextEditingController(text: p.name);
    final stockCtrl = TextEditingController(text: '${p.stock}');
    final skuCtrl = TextEditingController(text: p.sku);
    final volumeCtrl = TextEditingController(text: p.volume ?? '');
    String category = p.category;
    String? imageBase64 = p.imageBase64;
    DateTime? expiryDate = p.expiryDate;
    DateTime? productionDate = p.productionDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cats = DbService.categories;
          if (!cats.contains(category)) cats.add(category);
          return AlertDialog(
            title: const Text('Edit Produk', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      ...cats.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(value: _addNewValue, child: Text('+ Tambah kategori baru')),
                    ],
                    onChanged: (v) async {
                      if (v == _addNewValue) {
                        final newCat = await _promptNewCategory(ctx);
                        if (newCat != null && newCat.isNotEmpty) {
                          await DbService.addCategory(newCat);
                          setDialogState(() => category = newCat);
                        }
                      } else if (v != null) {
                        setDialogState(() => category = v);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stok saat ini'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(labelText: 'SKU', hintText: 'Kosongkan buat generate otomatis'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton(
                          onPressed: () => setDialogState(() => skuCtrl.text = DbService.suggestSkuForName(nameCtrl.text)),
                          child: const Text('Saran'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: volumeCtrl,
                    decoration: const InputDecoration(labelText: 'Volume/Ukuran (opsional)', hintText: 'mis. 250ml, 500ml'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          productionDate == null ? 'Tanggal produksi: -' : 'Produksi: ${_dateFmt.format(productionDate!)}',
                          style: const TextStyle(fontSize: 13, color: _navy),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: productionDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setDialogState(() => productionDate = picked);
                        },
                        child: const Text('Pilih'),
                      ),
                      if (productionDate != null)
                        TextButton(
                          onPressed: () => setDialogState(() => productionDate = null),
                          child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiryDate == null ? 'Tanggal kedaluwarsa: -' : 'Kedaluwarsa: ${_dateFmt.format(expiryDate!)}',
                          style: const TextStyle(fontSize: 13, color: _navy),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: expiryDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setDialogState(() => expiryDate = picked);
                        },
                        child: const Text('Pilih'),
                      ),
                      if (expiryDate != null)
                        TextButton(
                          onPressed: () => setDialogState(() => expiryDate = null),
                          child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () async {
                  await DbService.setProductName(p.id, nameCtrl.text.trim().isEmpty ? p.name : nameCtrl.text.trim());
                  await DbService.setProductCategory(p.id, category);
                  await DbService.setStock(p.id, int.tryParse(stockCtrl.text) ?? p.stock);
                  await DbService.setProductImage(p.id, imageBase64);
                  await DbService.setProductSku(p.id, skuCtrl.text);
                  await DbService.setProductExpiry(p.id, expiryDate);
                  await DbService.setProductVolume(p.id, volumeCtrl.text.trim().isEmpty ? null : volumeCtrl.text.trim());
                  await DbService.setProductProductionDate(p.id, productionDate);
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
    final skuCtrl = TextEditingController();
    String category = DbService.categories.isNotEmpty ? DbService.categories.first : 'Jamu';
    String? imageBase64;
    DateTime? expiryDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cats = DbService.categories;
          return AlertDialog(
            title: const Text('Tambah Produk', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      ...cats.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(value: _addNewValue, child: Text('+ Tambah kategori baru')),
                    ],
                    onChanged: (v) async {
                      if (v == _addNewValue) {
                        final newCat = await _promptNewCategory(ctx);
                        if (newCat != null && newCat.isNotEmpty) {
                          await DbService.addCategory(newCat);
                          setDialogState(() => category = newCat);
                        }
                      } else if (v != null) {
                        setDialogState(() => category = v);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)')),
                  const SizedBox(height: 8),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok awal')),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(labelText: 'SKU', hintText: 'Kosongkan buat generate otomatis'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton(
                          onPressed: () => setDialogState(() => skuCtrl.text = DbService.suggestSkuForName(nameCtrl.text)),
                          child: const Text('Saran'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiryDate == null ? 'Tanggal kedaluwarsa: -' : 'Kedaluwarsa: ${_dateFmt.format(expiryDate!)}',
                          style: const TextStyle(fontSize: 13, color: _navy),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: expiryDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setDialogState(() => expiryDate = picked);
                        },
                        child: const Text('Pilih'),
                      ),
                    ],
                  ),
                ],
              ),
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
        category: category,
        stock: int.tryParse(stockCtrl.text) ?? 0,
        imageBase64: imageBase64,
        sku: skuCtrl.text,
        expiryDate: expiryDate,
      );
      setState(() {});
    }
  }

  Future<void> _manageCategories() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cats = DbService.categories;
          return AlertDialog(
            title: const Text('Kelola Kategori', style: TextStyle(color: _navy)),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...cats.map((c) => ListTile(dense: true, title: Text(c), leading: const Icon(Icons.label_outline, size: 18, color: _navy))),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Kategori baru', isDense: true))),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _navy),
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) return;
                          await DbService.addCategory(ctrl.text.trim());
                          ctrl.clear();
                          setDialogState(() {});
                        },
                        child: const Text('Tambah'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
    setState(() {});
  }

  void _printLabel(Product p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LabelGeneratorScreen(product: p)));
  }

  @override
  Widget build(BuildContext context) {
    final allItems = DbService.products.values.toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? allItems
        : allItems.where((p) => p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(onPressed: _manageCategories, icon: const Icon(Icons.category_outlined), tooltip: 'Kelola Kategori'),
          IconButton(onPressed: _addProduct, icon: const Icon(Icons.add)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari nama produk, kategori, atau SKU...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Gak ada produk yang cocok.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final p = items[i];
                      final low = p.stock <= 5;
                      final expiringSoon = p.expiryDate != null && p.expiryDate!.isBefore(DateTime.now().add(const Duration(days: 7)));
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
                        subtitle: Text(
                          '${p.category} • ${_currency.format(p.price)} • ${p.sku.isEmpty ? "belum ada SKU" : p.sku}'
                          '${p.expiryDate != null ? " • EXP ${_dateFmt.format(p.expiryDate!)}" : ""}',
                          style: TextStyle(fontSize: 11, color: expiringSoon ? Colors.red : null),
                        ),
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
                            IconButton(icon: const Icon(Icons.qr_code, size: 18), tooltip: 'Cetak Label', onPressed: () => _printLabel(p)),
                            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editProduct(p)),
                          ],
                        ),
                        onTap: () => _editProduct(p),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: _addProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Halaman cetak label — QR code + barcode Code128, ukuran label bisa dipilih,
/// bisa generate banyak sekaligus dengan nomor urut (buat batch/traceability
/// per botol/unit, terpisah dari SKU produk).
class LabelGeneratorScreen extends StatefulWidget {
  final Product product;
  const LabelGeneratorScreen({super.key, required this.product});

  @override
  State<LabelGeneratorScreen> createState() => _LabelGeneratorScreenState();
}

class _LabelGeneratorScreenState extends State<LabelGeneratorScreen> {
  final _dateFmt = DateFormat('d MMM yy');
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _startCtrl = TextEditingController(text: '1');
  final _qtyCtrl = TextEditingController(text: '10');
  String _labelSize = '60x40mm';
  List<int> _generatedNumbers = [];

  String? _selectedVariation;
  final Set<String> _selectedAddons = {};
  bool _showPrice = true;
  DateTime? _productionDate;
  DateTime? _expiryDate;

  static const _sizes = {
    '60x40mm': Size(220, 160),
    '50x30mm': Size(190, 130),
    '40x30mm': Size(160, 130),
  };

  @override
  void initState() {
    super.initState();
    _productionDate = widget.product.productionDate;
    _expiryDate = widget.product.expiryDate;
  }

  int get _labelPrice {
    int total = widget.product.price;
    for (final addonName in _selectedAddons) {
      final addon = DbService.addons.where((a) => a.name == addonName);
      if (addon.isNotEmpty) total += addon.first.price;
    }
    return total;
  }

  void _generate() {
    final start = int.tryParse(_startCtrl.text) ?? 1;
    final qty = (int.tryParse(_qtyCtrl.text) ?? 1).clamp(1, 100);
    setState(() => _generatedNumbers = List.generate(qty, (i) => start + i));
  }

  Future<void> _pickDate({required bool isProduction}) async {
    final current = isProduction ? _productionDate : _expiryDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isProduction) {
        _productionDate = picked;
      } else {
        _expiryDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final cardSize = _sizes[_labelSize]!;
    final variations = DbService.variations;
    final addons = DbService.addons;

    return Scaffold(
      appBar: AppBar(title: Text('Cetak Label — ${p.name}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _labelSize,
                          decoration: const InputDecoration(labelText: 'Ukuran Label'),
                          items: _sizes.keys.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setState(() => _labelSize = v ?? _labelSize),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _startCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Nomor Awal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Jumlah Label'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (variations.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedVariation,
                      decoration: const InputDecoration(labelText: 'Varian (opsional)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tanpa Varian')),
                        ...variations.map((v) => DropdownMenuItem(value: v.name, child: Text(v.name))),
                      ],
                      onChanged: (v) => setState(() => _selectedVariation = v),
                    ),
                  if (addons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Tambahan (opsional, boleh lebih dari satu)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: addons.map((a) {
                        final selected = _selectedAddons.contains(a.name);
                        final priceLabel = a.price > 0 ? ' (+${_currency.format(a.price)})' : '';
                        return FilterChip(
                          label: Text('${a.name}$priceLabel', style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          selectedColor: _navy.withValues(alpha: 0.15),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedAddons.add(a.name);
                            } else {
                              _selectedAddons.remove(a.name);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () => _pickDate(isProduction: true),
                          child: Text(_productionDate == null ? 'Tanggal Produksi' : 'Prod: ${_dateFmt.format(_productionDate!)}', style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () => _pickDate(isProduction: false),
                          child: Text(_expiryDate == null ? 'Tanggal Kedaluwarsa' : 'Exp: ${_dateFmt.format(_expiryDate!)}', style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Tanggal ini khusus buat batch label kali ini, gak ngubah data produk yang tersimpan.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: _navy,
                    title: const Text('Tampilkan Harga di Label'),
                    subtitle: _showPrice ? Text('${_currency.format(_labelPrice)} (harga dasar + tambahan terpilih)', style: const TextStyle(fontSize: 11)) : null,
                    value: _showPrice,
                    onChanged: (v) => setState(() => _showPrice = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _navy),
                    onPressed: _generate,
                    child: const Text('⚡ Generate Label'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_generatedNumbers.isEmpty)
              const Expanded(
                child: Center(child: Text('Atur pengaturan di atas, terus tap Generate.', style: TextStyle(color: Colors.grey))),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_generatedNumbers.length} label dibuat', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _generatedNumbers.map((num) => _buildLabelCard(p, num, cardSize)).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preview — pas print fisik: paper size $_labelSize, margin None, scale 100%.',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelCard(Product p, int barcodeNum, Size size) {
    final qrData = 'TAPPLY|${p.sku}|$barcodeNum|${_productionDate?.toIso8601String() ?? ""}';
    final variantLine = [
      if (_selectedVariation != null) _selectedVariation!,
      ..._selectedAddons,
    ].join(', ');

    return Container(
      width: size.width,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (p.volume != null && p.volume!.isNotEmpty) p.volume!,
                        if (p.sku.isNotEmpty) p.sku,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    if (variantLine.isNotEmpty)
                      Text(variantLine, style: const TextStyle(fontSize: 9, color: Colors.black87, fontWeight: FontWeight.w600)),
                    if (_productionDate != null)
                      Text('Prod: ${_dateFmt.format(_productionDate!)}', style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
                    if (_expiryDate != null)
                      Text('Exp: ${_dateFmt.format(_expiryDate!)}', style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
                    if (_showPrice)
                      Text(_currency.format(_labelPrice), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              QrImageView(data: qrData, size: 48, backgroundColor: Colors.white),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: '$barcodeNum',
              drawText: true,
              style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
