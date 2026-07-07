import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'dart:convert';
import '../models/product.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF623609);

/// Inventory di app HANYA buat urus stock. Nama, harga, kategori, foto, SKU,
/// varian/tambahan, dan ukuran label semuanya dikelola dari dashboard web —
/// biar kasir gak bisa ubah-ubah data produk secara gak sengaja.
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

  Future<void> _editStock(Product p) async {
    final ctrl = TextEditingController(text: '${p.stock}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name, style: const TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.sku.isNotEmpty) Text('SKU: ${p.sku}', style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Stock'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Product name, price, category, photo, SKU, and variants are managed from the web dashboard.',
              style: TextStyle(fontSize: 11, color: const Color(0xFF623609)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text) ?? p.stock),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await DbService.setStock(p.id, result);
      setState(() {});
    }
  }

  void _printLabel(Product p) {
    if (!DbService.isProActive) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Label Printing is a Pro Feature', style: TextStyle(color: _navy)),
          content: const Text('Upgrade your plan from the dashboard to unlock QR/barcode label printing.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }
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
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search product, category, or SKU...',
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
                ? const Center(child: Text('No matching products.', style: TextStyle(color: const Color(0xFF623609))))
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
                            color: const Color(0xFFD6CFC6),
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
                          '${p.category} • ${_currency.format(p.price)} • ${p.sku.isEmpty ? "no SKU" : p.sku}'
                          '${p.expiryDate != null ? " • EXP ${_dateFmt.format(p.expiryDate!)}" : ""}',
                          style: TextStyle(fontSize: 11, color: expiringSoon ? Colors.red : null),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: low ? Colors.red.shade50 : const Color(0xFFEFECE5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: low ? Colors.red : const Color(0xFF623609)),
                              ),
                              child: Text(
                                'Stock: ${p.stock}',
                                style: TextStyle(
                                  color: low ? Colors.red.shade800 : const Color(0xFF623609),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.qr_code, size: 18), tooltip: 'Print Label', onPressed: () => _printLabel(p)),
                          ],
                        ),
                        onTap: () => _editStock(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Halaman cetak label. Cuma nomor awal, jumlah, dan tanggal produksi/expiry
/// yang bisa diatur di sini — ukuran label, SKU, varian/tambahan, dan
/// tampil-tidaknya harga semua udah dikonfigurasi dari dashboard web.
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
  List<int> _generatedNumbers = [];

  late DateTime? _productionDate;
  late DateTime? _expiryDate;

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
    for (final addonName in widget.product.labelAddons) {
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
    final cardSize = _sizes[p.labelSize] ?? _sizes['60x40mm']!;

    return Scaffold(
      appBar: AppBar(title: Text('Print Label — ${p.name}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF3F3F3), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Label size, SKU, variant/add-ons, and price visibility are set from the dashboard. '
                'Here you can only set batch dates and quantity.',
                style: TextStyle(fontSize: 11, color: const Color(0xFF623609)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => _pickDate(isProduction: true),
                    child: Text(_productionDate == null ? 'Production Date' : 'Prod: ${_dateFmt.format(_productionDate!)}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => _pickDate(isProduction: false),
                    child: Text(_expiryDate == null ? 'Expiry Date' : 'Exp: ${_dateFmt.format(_expiryDate!)}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Start Number'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _navy),
              onPressed: _generate,
              child: const Text('⚡ Generate Labels'),
            ),
            const SizedBox(height: 20),
            if (_generatedNumbers.isEmpty)
              const Expanded(
                child: Center(child: Text('Set the options above, then tap Generate.', style: TextStyle(color: const Color(0xFF623609)))),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_generatedNumbers.length} labels generated', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
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
                      'Preview — for physical printing: paper size ${p.labelSize}, margin None, scale 100%.',
                      style: const TextStyle(fontSize: 11, color: const Color(0xFF623609)),
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
      if (p.labelVariant != null) p.labelVariant!,
      ...p.labelAddons,
    ].join(', ');

    return Container(
      width: size.width,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF623609)), borderRadius: BorderRadius.circular(6)),
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
                      style: const TextStyle(fontSize: 9, color: const Color(0xFF623609)),
                    ),
                    if (variantLine.isNotEmpty)
                      Text(variantLine, style: const TextStyle(fontSize: 9, color: Colors.black87, fontWeight: FontWeight.w600)),
                    if (_productionDate != null)
                      Text('Prod: ${_dateFmt.format(_productionDate!)}', style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
                    if (_expiryDate != null)
                      Text('Exp: ${_dateFmt.format(_expiryDate!)}', style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
                    if (p.showPriceOnLabel)
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
