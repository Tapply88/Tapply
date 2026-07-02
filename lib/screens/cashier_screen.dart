import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final Map<String, int> _cart = {}; // productId -> qty
  Member? _selectedMember;
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  int get _total {
    final products = DbService.products;
    return _cart.entries.fold(0, (sum, e) {
      final p = products.get(e.key);
      return sum + (p?.price ?? 0) * e.value;
    });
  }

  void _addToCart(Product p) {
    setState(() => _cart[p.id] = (_cart[p.id] ?? 0) + 1);
  }

  void _removeFromCart(Product p) {
    setState(() {
      final qty = (_cart[p.id] ?? 0) - 1;
      if (qty <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = qty;
      }
    });
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

  Future<void> _checkout(String paymentMethod) async {
    if (_cart.isEmpty) return;
    final products = DbService.products;
    final items = _cart.entries.map((e) {
      final p = products.get(e.key)!;
      return TxItem(productId: p.id, productName: p.name, price: p.price, qty: e.value);
    }).toList();

    // TODO integrasi live: kalau paymentMethod == 'qris_midtrans', panggil
    // MidtransService.createTransaction(...) dulu, tampilkan QRIS/redirect_url
    // pakai webview, baru saveTransaction setelah status "settlement".
    // Untuk sekarang (mode dev) transaksi langsung dicatat "paid".

    await DbService.saveTransaction(

      items: items,
      paymentMethod: paymentMethod,
      memberId: _selectedMember?.id,
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

  @override
  Widget build(BuildContext context) {
    final products = DbService.products.values.where((p) => p.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tapply — Kasir')),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: products.length,
              itemBuilder: (ctx, i) {
                final p = products[i];
                return Card(
                  child: InkWell(
                    onTap: () => _addToCart(p),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_currency.format(p.price)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                ListTile(
                  title: Text(_selectedMember?.name ?? 'Tanpa member'),
                  subtitle: _selectedMember != null
                      ? Text('${_selectedMember!.points} poin')
                      : null,
                  trailing: TextButton(onPressed: _pickMember, child: const Text('Pilih')),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: _cart.entries.map((e) {
                      final p = DbService.products.get(e.key)!;
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text('${_currency.format(p.price)} x ${e.value}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.remove), onPressed: () => _removeFromCart(p)),
                            Text('${e.value}'),
                            IconButton(icon: const Icon(Icons.add), onPressed: () => _addToCart(p)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(_currency.format(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _cart.isEmpty ? null : () => _checkout('cash'),
                              child: const Text('Bayar Cash'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: _cart.isEmpty ? null : () => _checkout('qris_midtrans'),
                              child: const Text('QRIS / Midtrans'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
