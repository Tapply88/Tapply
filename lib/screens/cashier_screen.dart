import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

const _variations = ['Hangat', 'Dingin'];
const _addonPrices = {
  'Extra Madu': 3000,
  'Extra Jahe': 2000,
  'Kurang Gula': 0,
};

class CartLine {
  final String signature;
  final Product product;
  final String variation;
  final List<String> addons;
  final bool memberDiscount;
  final int unitPrice;
  int qty;

  CartLine({
    required this.signature,
    required this.product,
    required this.variation,
    required this.addons,
    required this.memberDiscount,
    required this.unitPrice,
    required this.qty,
  });

  int get subtotal => unitPrice * qty;

  String get note {
    final parts = <String>[variation];
    if (addons.isNotEmpty) parts.add(addons.join(', '));
    if (memberDiscount) parts.add('Diskon member 10%');
    return parts.join(' • ');
  }
}

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final List<CartLine> _cart = [];
  Member? _selectedMember;
  String _salesType = 'Dine In';
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _customCashController = TextEditingController();

  int get _subtotal => _cart.fold(0, (sum, l) => sum + l.subtotal);
  Map<String, int> get _totals => DbService.computeTotals(_subtotal);
  int get _grandTotal => _totals['grandTotal']!;

  Future<void> _openProductModifier(Product p) async {
    if (p.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} stok habis')),
      );
      return;
    }
    String variation = _variations.first;
    final Set<String> addons = {};
    int qty = 1;
    bool memberDiscount = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final addonTotal = addons.fold<int>(0, (s, a) => s + (_addonPrices[a] ?? 0));
          int unit = p.price + addonTotal;
          if (memberDiscount) unit = (unit * 0.9).round();

          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                        Column(
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                            Text(_currency.format(unit), style: const TextStyle(color: _navy)),
                          ],
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _navy),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Simpan'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('VARIAN | PILIH SATU', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: _variations.map((v) {
                        final selected = variation == v;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: selected ? _navy : Colors.transparent,
                                foregroundColor: selected ? Colors.white : _navy,
                                side: const BorderSide(color: _navy),
                              ),
                              onPressed: () => setDialogState(() => variation = v),
                              child: Text(v),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('TAMBAHAN | BOLEH LEBIH DARI SATU', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _addonPrices.keys.map((a) {
                        final selected = addons.contains(a);
                        final priceLabel = _addonPrices[a]! > 0 ? ' (+${_currency.format(_addonPrices[a])})' : '';
                        return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selected ? _navy : Colors.transparent,
                            foregroundColor: selected ? Colors.white : _navy,
                            side: const BorderSide(color: _navy),
                          ),
                          onPressed: () => setDialogState(() {
                            if (selected) {
                              addons.remove(a);
                            } else {
                              addons.add(a);
                            }
                          }),
                          child: Text('$a$priceLabel', style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('JUMLAH', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          style: IconButton.styleFrom(side: const BorderSide(color: _navy)),
                          icon: const Icon(Icons.remove, color: _navy),
                          onPressed: () => setDialogState(() { if (qty > 1) qty--; }),
                        ),
                        Expanded(child: Center(child: Text('$qty', style: const TextStyle(fontSize: 16, color: _navy)))),
                        IconButton(
                          style: IconButton.styleFrom(side: const BorderSide(color: _navy)),
                          icon: const Icon(Icons.add, color: _navy),
                          onPressed: () => setDialogState(() { if (qty < p.stock) qty++; }),
                        ),
                      ],
                    ),
                    if (_selectedMember != null) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: _navy,
                        title: const Text('Diskon member 10%', style: TextStyle(fontSize: 13, color: _navy)),
                        value: memberDiscount,
                        onChanged: (v) => setDialogState(() => memberDiscount = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      final addonTotal = addons.fold<int>(0, (s, a) => s + (_addonPrices[a] ?? 0));
      int unit = p.price + addonTotal;
      if (memberDiscount) unit = (unit * 0.9).round();
      final sig = '${p.id}-$variation-${addons.join(",")}-$memberDiscount';
      setState(() {
        final existing = _cart.where((l) => l.signature == sig);
        if (existing.isNotEmpty) {
          existing.first.qty += qty;
        } else {
          _cart.add(CartLine(
            signature: sig,
            product: p,
            variation: variation,
            addons: addons.toList(),
            memberDiscount: memberDiscount,
            unitPrice: unit,
            qty: qty,
          ));
        }
      });
    }
  }

  Future<void> _pickMember() async {
    final phoneController = TextEditingController();
    final result = await showDialog<Member?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cari Member (no. HP)'),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '08xxxxxxxxxx'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              final m = DbService.findMemberByPhone(phoneController.text.trim());
              Navigator.pop(ctx, m);
              if (m == null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Member tidak ditemukan. Daftarkan dulu di tab Member.')),
                );
              }
            },
            child: const Text('Cari'),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _selectedMember = result);
  }

  Future<void> _pickSalesType() async {
    final options = ['Dine In', 'Take Away', 'Online'];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Jenis Penjualan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((o) {
            final selected = o == _salesType;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: selected ? _navy : Colors.transparent,
                    foregroundColor: selected ? Colors.white : _navy,
                    side: const BorderSide(color: _navy),
                  ),
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Text(o),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
    if (result != null) setState(() => _salesType = result);
  }

  void _saveBillDraft() {
    if (_cart.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill disimpan sebagai draft (fitur simpan permanen menyusul)')),
    );
  }

  void _printBill() {
    if (_cart.isEmpty) return;
    final totals = _totals;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Text(DbService.businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navy)),
                        if (DbService.businessAddress.isNotEmpty)
                          Text(DbService.businessAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        if (DbService.businessPhone.isNotEmpty)
                          Text(DbService.businessPhone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Text(_salesType, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  ..._cart.map((l) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${l.product.name} x${l.qty}', style: const TextStyle(fontSize: 13)),
                                  Text(l.note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Text(_currency.format(l.subtotal), style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                  _receiptRow('Sub-Total', _subtotal),
                  if (totals['tax']! > 0) _receiptRow('Tax', totals['tax']!),
                  if (totals['service']! > 0) _receiptRow('Service', totals['service']!),
                  if (totals['discount']! > 0) _receiptRow('Diskon', -totals['discount']!),
                  if (totals['rounding'] != 0) _receiptRow('Pembulatan', totals['rounding']!),
                  const Divider(height: 20),
                  _receiptRow('Total', totals['grandTotal']!, bold: true),
                  const SizedBox(height: 20),
                  const Center(child: Text('Terima kasih!', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: _navy,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_currency.format(amount), style: style),
        ],
      ),
    );
  }

  Future<void> _checkout(String paymentMethod) async {
    if (_cart.isEmpty) return;
    final totals = _totals;
    final items = _cart
        .map((l) => TxItem(
              productId: l.product.id,
              productName: l.product.name,
              price: l.unitPrice,
              qty: l.qty,
              note: l.note,
            ))
        .toList();

    await DbService.saveTransaction(
      items: items,
      paymentMethod: paymentMethod,
      memberId: _selectedMember?.id,
      salesType: _salesType,
      taxAmount: totals['tax']!,
      serviceAmount: totals['service']!,
      discountAmount: totals['discount']!,
      roundingAdjustment: totals['rounding']!,
    );

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaksi berhasil disimpan!')),
    );
  }

  Future<void> _openManualQrisDialog(int total) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QRIS', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total: ${_currency.format(total)}', style: const TextStyle(color: _navy, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            const Text(
              'Minta pelanggan scan QRIS yang ada di meja kasir, lalu konfirmasi setelah dana masuk.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              Navigator.pop(ctx);
              _checkout('qris_manual');
            },
            child: const Text('Sudah Dibayar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentSheet() async {
    if (_cart.isEmpty) return;
    final total = _grandTotal;
    final quickAmounts = <int>{
      total,
      ((total ~/ 5000) + 1) * 5000,
      ((total ~/ 10000) + 1) * 10000,
    }.toList()
      ..sort();
    _customCashController.clear();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: _navy), onPressed: () => Navigator.pop(ctx)),
                  Text(_currency.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navy)),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Cash', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickAmounts.map((a) {
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkout('cash');
                    },
                    child: Text(_currency.format(a)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customCashController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nominal lain',
                        hintText: 'Masukkan jumlah cash',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _navy),
                    onPressed: () {
                      final amount = int.tryParse(_customCashController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      if (amount < total) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Nominal kurang dari total tagihan')),
                        );
                        return;
                      }
                      final change = amount - total;
                      Navigator.pop(ctx);
                      _checkout('cash');
                      if (change > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Kembalian: ${_currency.format(change)}')),
                        );
                      }
                    },
                    child: const Text('Bayar'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('QRIS (Manual, tanpa Midtrans)', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openManualQrisDialog(total);
                },
                icon: const Icon(Icons.qr_code, size: 18),
                label: const Text('Tampilkan Kode QRIS'),
              ),
              const SizedBox(height: 20),
              const Text('E-Wallet / QRIS (Midtrans)', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['GoPay', 'OVO', 'DANA', 'QRIS'].map((w) {
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkout('qris_midtrans');
                    },
                    child: Text(w),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text('EDC / Kartu', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['BCA', 'Mandiri', 'BNI'].map((b) {
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkout('edc_$b');
                    },
                    child: Text(b),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = DbService.products.values.where((p) => p.isActive).toList();
    final totals = _totals;

    return Scaffold(
      backgroundColor: _grey,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 90,
        backgroundColor: _grey,
        title: Image.asset('assets/logo.png', height: 72),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.85,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: products.length,
              itemBuilder: (ctx, i) {
                final p = products[i];
                final outOfStock = p.stock <= 0;
                return Material(
                  color: outOfStock ? const Color(0xFFEDEDED) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openProductModifier(p),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _navy, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _grey,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.local_cafe_outlined, color: _navy.withValues(alpha: outOfStock ? 0.3 : 1), size: 32),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: outOfStock ? Colors.red.shade100 : Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: outOfStock ? Colors.red : _navy, width: 0.5),
                                    ),
                                    child: Text(
                                      outOfStock ? 'Habis' : 'Stok ${p.stock}',
                                      style: TextStyle(fontSize: 10, color: outOfStock ? Colors.red.shade800 : _navy),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: outOfStock ? Colors.grey : _navy)),
                                Text(_currency.format(p.price), style: TextStyle(fontSize: 12, color: outOfStock ? Colors.grey : _navy)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: 1,
            color: _navy.withValues(alpha: 0.2),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  InkWell(
                    onTap: _pickMember,
                    child: Container(
                      width: double.infinity,
                      color: _grey,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text(
                        _selectedMember != null
                            ? '${_selectedMember!.name} • ${_selectedMember!.points} poin'
                            : '+ Tambah Pelanggan',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: _navy),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _pickSalesType,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_salesType, style: const TextStyle(color: _navy)),
                          const Icon(Icons.arrow_drop_down, color: _navy),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(child: Text('Belum ada item', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _cart.length,
                            itemBuilder: (ctx, i) {
                              final l = _cart[i];
                              return ListTile(
                                title: Text(l.product.name, style: const TextStyle(color: _navy, fontWeight: FontWeight.bold)),
                                subtitle: Text(l.note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_currency.format(l.subtotal), style: const TextStyle(color: _navy)),
                                    Text('x${l.qty}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      children: [
                        _totalRow('Sub-Total', _subtotal),
                        if (totals['tax']! > 0) _totalRow('Tax', totals['tax']!),
                        if (totals['service']! > 0) _totalRow('Service', totals['service']!),
                        if (totals['discount']! > 0) _totalRow('Diskon', -totals['discount']!),
                        if (totals['rounding'] != 0) _totalRow('Pembulatan', totals['rounding']!),
                        const Divider(height: 12),
                        _totalRow('Total', totals['grandTotal']!, bold: true),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _saveBillDraft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: _grey,
                            alignment: Alignment.center,
                            child: const Text('Save Bill', style: TextStyle(color: _navy)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _printBill,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: const Color(0xFFE0E0E0),
                            alignment: Alignment.center,
                            child: const Text('Print Bill', style: TextStyle(color: _navy)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: _cart.isEmpty ? null : _openPaymentSheet,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      color: _cart.isEmpty ? Colors.grey : _navy,
                      alignment: Alignment.center,
                      child: Text(
                        'Charge ${_currency.format(_grandTotal)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      color: _navy,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 15 : 13,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_currency.format(amount), style: style),
        ],
      ),
    );
  }
}
