cat > lib/screens/report_screen.dart << 'REPEOF'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';

const _navy = Color(0xFF092762);

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  void _showReceipt(BuildContext context, tx) {
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
                  ReceiptView(tx: tx),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final todayTotal = DbService.totalSalesToday();
    final byProduct = DbService.salesByProduct();
    final sortedEntries = byProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final allTx = DbService.transactions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final lowStock = DbService.products.values.where((p) => p.stock <= 5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sales Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today\'s Sales'),
                  const SizedBox(height: 4),
                  Text(currency.format(todayTotal), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (lowStock.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠ Low Stock (${lowStock.length} products)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                    const SizedBox(height: 8),
                    ...lowStock.map((p) => Text('${p.name} — ${p.stock} left', style: TextStyle(color: Colors.red.shade800))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Sales by Payment Method', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...(() {
            final byMethod = DbService.salesByPaymentMethod();
            final sorted = byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            if (sorted.isEmpty) {
              return [const Text('No transactions yet.', style: TextStyle(fontSize: 12, color: Colors.grey))];
            }
            return sorted
                .map((e) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.payments_outlined, size: 18, color: _navy),
                      title: Text(paymentMethodLabel(e.key)),
                      trailing: Text(currency.format(e.value), style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                    ))
                .toList();
          })(),
          const SizedBox(height: 20),
          const Text('Best-selling Products (all time)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...sortedEntries.map((e) => ListTile(
                dense: true,
                title: Text(e.key),
                trailing: Text('${e.value} sold'),
              )),
          const SizedBox(height: 20),
          const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('Tap to view full receipt', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          ...allTx.take(100).map((t) => ListTile(
                dense: true,
                onTap: () => _showReceipt(context, t),
                title: Text(currency.format(t.total)),
                subtitle: Text('${paymentMethodLabel(t.paymentMethod)} • ${DateFormat('dd MMM yyyy, HH:mm').format(t.createdAt)}'),
                trailing: Text(t.status),
              )),
        ],
      ),
    );
  }
}
REPEOF

cat > lib/screens/membership_screen.dart << 'MEMEOF'
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/member.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final _uuid = const Uuid();
  final _searchCtrl = TextEditingController();
  Member? _found;
  bool _searched = false;

  void _search() {
    final result = DbService.findMemberByPhone(_searchCtrl.text.trim());
    setState(() {
      _found = result;
      _searched = true;
    });
  }

  Future<void> _addMember() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _searchCtrl.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register New Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
      final member = Member(
        id: _uuid.v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        joinedAt: DateTime.now(),
      );
      await DbService.saveMember(member);
      setState(() {
        _found = member;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The full member list (all customer data) is available in the admin dashboard. '
              'Here the cashier can only search one number to check points or register a new member.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Search by phone number', hintText: '08xxxxxxxxxx'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: _search,
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_searched && _found != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(_found!.name.isNotEmpty ? _found!.name[0].toUpperCase() : '?')),
                  title: Text(_found!.name),
                  subtitle: Text(_found!.phone),
                  trailing: Text('${_found!.points} points', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ),
              )
            else if (_searched && _found == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Member not found.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: _addMember,
                    child: const Text('Register New Member'),
                  ),
                ],
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: _addMember,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
MEMEOF

cat > lib/screens/cashier_screen.dart << 'CASHIEREOF'
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../models/promo.dart';
import '../models/held_bill.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';
import 'shift_screen.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

class CartLine {
  final String signature;
  final Product product;
  final String variation;
  final List<String> addons;
  final bool memberDiscount;
  final int unitPrice;
  int qty;
  final String? optInPromoId; // promo scope 'item' yang di-opt-in khusus baris ini

  CartLine({
    required this.signature,
    required this.product,
    required this.variation,
    required this.addons,
    required this.memberDiscount,
    required this.unitPrice,
    required this.qty,
    this.optInPromoId,
  });

  int get subtotal => unitPrice * qty;

  String get note {
    final parts = <String>[];
    if (variation.isNotEmpty) parts.add(variation);
    if (addons.isNotEmpty) parts.add(addons.join(', '));
    if (memberDiscount) parts.add('Member discount 10%');
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
  String? _guestName;
  String _salesType = 'Dine In';
  final _pageController = PageController();
  int _categoryIndex = 0;
  String? _chosenPromoId;
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _customCashController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (DbService.currentCashierName.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCashierLogin());
    }
  }

  Future<void> _openCashierLogin() async {
    final nameCtrl = TextEditingController(text: DbService.currentCashierName);
    final emailCtrl = TextEditingController(text: DbService.currentCashierEmail);
    await showDialog(
      context: context,
      barrierDismissible: DbService.currentCashierName.isNotEmpty,
      builder: (ctx) => AlertDialog(
        title: const Text('Who is working this shift?', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This name & email show on the receipt as "Served by". Simple version — not yet connected to account-based login on the dashboard.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Cashier Name')),
            const SizedBox(height: 8),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Cashier Email'), keyboardType: TextInputType.emailAddress),
          ],
        ),
        actions: [
          if (DbService.currentCashierName.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await DbService.setCurrentCashier(name: nameCtrl.text.trim(), email: emailCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  int get _subtotal => _cart.fold(0, (sum, l) => sum + l.subtotal);

  /// Subtotal per produk (gabungan semua varian/add-on produk yang sama di keranjang),
  /// dipakai buat ngecek promo yang scope-nya "produk tertentu".
  Map<String, int> get _productSubtotals {
    final map = <String, int>{};
    for (final l in _cart) {
      map[l.product.id] = (map[l.product.id] ?? 0) + l.subtotal;
    }
    return map;
  }

  /// Total qty per produk di keranjang — dipakai buat promo nominal tetap per-produk
  /// (biar diskonnya kelipatan tiap produk itu ditambahin, bukan cuma sekali flat).
  Map<String, int> get _productQuantities {
    final map = <String, int>{};
    for (final l in _cart) {
      map[l.product.id] = (map[l.product.id] ?? 0) + l.qty;
    }
    return map;
  }

  /// Nentuin diskon yang dipakai: kalau kasir udah pilih promo tertentu, pakai itu;
  /// kalau cuma ada 1 promo valid, otomatis dipakai; kalau ada beberapa, WAJIB dipilih
  /// dulu (gak boleh nebak sendiri); kalau nggak ada promo sama sekali, fallback ke
  /// diskon manual di Setelan (kalau aktif).
  int _itemScopeDiscountAmount(Promo p) {
    int total = 0;
    for (final l in _cart) {
      if (l.optInPromoId == p.id) {
        total += p.discountType == 'fixed' ? (p.value * l.qty).round() : (l.subtotal * p.value / 100).round();
      }
    }
    return total;
  }

  ({int amount, String label, Promo? promo}) _resolveDiscount() {
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals);

    if (_chosenPromoId == 'NONE') {
      if (DbService.discountEnabled) {
        return (amount: (_subtotal * DbService.discountPercent / 100).round(), label: DbService.discountPromoName, promo: null);
      }
      return (amount: 0, label: '', promo: null);
    }

    if (_chosenPromoId != null) {
      final match = valid.where((p) => p.id == _chosenPromoId);
      if (match.isNotEmpty) {
        final p = match.first;
        final amt = p.scope == 'item'
            ? _itemScopeDiscountAmount(p)
            : DbService.promoDiscountAmount(p, cartSubtotal: _subtotal, productSubtotals: _productSubtotals, productQuantities: _productQuantities);
        return (amount: amt, label: p.name, promo: p);
      }
    }

    if (valid.length == 1) {
      final p = valid.first;
      final amt = p.scope == 'item'
          ? _itemScopeDiscountAmount(p)
          : DbService.promoDiscountAmount(p, cartSubtotal: _subtotal, productSubtotals: _productSubtotals, productQuantities: _productQuantities);
      return (amount: amt, label: p.name, promo: p);
    }

    if (valid.length > 1) {
      return (amount: 0, label: '', promo: null); // nunggu kasir pilih
    }

    if (DbService.discountEnabled) {
      return (amount: (_subtotal * DbService.discountPercent / 100).round(), label: DbService.discountPromoName, promo: null);
    }
    return (amount: 0, label: '', promo: null);
  }

  /// Catatan diskon buat satu baris keranjang, kalau baris itu kena promo produk-tertentu
  /// atau di-opt-in ke promo per-item.
  String? _lineDiscountNote(CartLine line) {
    final resolved = _resolveDiscount();
    final promo = resolved.promo;
    if (promo == null) return null;

    if (promo.scope == 'item') {
      if (line.optInPromoId != promo.id) return null;
      final share = promo.discountType == 'fixed' ? (promo.value * line.qty).round() : (line.subtotal * promo.value / 100).round();
      if (share <= 0) return null;
      return 'Promo ${promo.name}: -${_currency.format(share)}';
    }

    if (promo.scope != 'product') return null;
    if (!promo.productIds.contains(line.product.id)) return null;
    final share = promo.discountType == 'fixed'
        ? (promo.value * line.qty).round()
        : (line.subtotal * promo.value / 100).round();
    if (share <= 0) return null;
    return 'Promo ${promo.name}: -${_currency.format(share)}';
  }

  Map<String, int> get _totals => DbService.computeTotals(_subtotal, discountAmount: _resolveDiscount().amount);
  int get _grandTotal => _totals['grandTotal']!;
  String get _discountLabel => _resolveDiscount().label;

  Future<void> _openPromoPicker() async {
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals);
    if (valid.isEmpty) return;
    String? temp = _chosenPromoId ?? (valid.length == 1 ? valid.first.id : null);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Select Promo', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('No Promo'),
                    value: 'NONE',
                    groupValue: temp,
                    onChanged: (v) => setDialogState(() => temp = v),
                  ),
                  ...valid.map((p) {
                    final subtitleText = p.scope == 'item'
                        ? '${p.discountType == 'fixed' ? '-${_currency.format(p.value.round())}' : '-${p.value.toStringAsFixed(0)}%'} per item • checked when adding the product'
                        : '-${_currency.format(DbService.promoDiscountAmount(p, cartSubtotal: _subtotal, productSubtotals: _productSubtotals, productQuantities: _productQuantities))}${p.scope == 'product' ? ' • specific product' : ''}';
                    return RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(subtitleText),
                      value: p.id,
                      groupValue: temp,
                      onChanged: (v) => setDialogState(() => temp = v),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () => Navigator.pop(ctx, temp),
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) setState(() => _chosenPromoId = result);
  }

  Future<void> _addCustomItem() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Item', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create an item not in the menu, e.g. service fee, special order, etc.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item name')),
            const SizedBox(height: 8),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (Rp)')),
            const SizedBox(height: 8),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim();
      final price = int.tryParse(priceCtrl.text) ?? 0;
      final qty = int.tryParse(qtyCtrl.text) ?? 1;
      if (name.isEmpty || price <= 0 || qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid name, price, and quantity')),
        );
        return;
      }
      final customProduct = Product(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        price: price,
        category: 'Custom',
        stock: 1 << 20,
      );
      setState(() {
        _cart.add(CartLine(
          signature: customProduct.id,
          product: customProduct,
          variation: '',
          addons: const [],
          memberDiscount: false,
          unitPrice: price,
          qty: qty,
        ));
      });
    }
  }

  Future<void> _confirmRemoveLine(CartLine line) async {
    if (!DbService.pinRequiredForCancel) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel Item?', style: TextStyle(color: _navy)),
          content: Text('Yakin mau cancel "${line.product.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Item'),
            ),
          ],
        ),
      );
      if (confirm == true) setState(() => _cart.remove(line));
      return;
    }

    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cancel', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter PIN to cancel "${line.product.name}"'),
            const SizedBox(height: 8),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (pinCtrl.text == DbService.managerPin) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Wrong PIN')));
              }
            },
            child: const Text('Cancel Item'),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => _cart.remove(line));
  }

  Future<void> _openProductModifier(Product p) async {
    if (p.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} stok habis')),
      );
      return;
    }
    final availableVariations = DbService.variations;
    final availableAddons = DbService.addons;
    final addonPriceMap = {for (final a in availableAddons) a.name: a.price};

    String? variation = availableVariations.isNotEmpty ? availableVariations.first.name : null;
    final Set<String> addons = {};
    int qty = 1;
    bool memberDiscount = false;
    bool itemPromoOptIn = false;

    final activePromo = _resolveDiscount().promo;
    final itemPromo = (activePromo != null && activePromo.scope == 'item' &&
            (activePromo.productIds.isEmpty || activePromo.productIds.contains(p.id)))
        ? activePromo
        : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final addonTotal = addons.fold<int>(0, (s, a) => s + (addonPriceMap[a] ?? 0));
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
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        Column(
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                            Text(_currency.format(unit), style: const TextStyle(color: _navy)),
                          ],
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _navy),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (availableVariations.isNotEmpty) ...[
                      const Text('VARIATION | CHOOSE ONE', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: availableVariations.map((v) {
                          final selected = variation == v.name;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: selected ? _navy : Colors.transparent,
                                  foregroundColor: selected ? Colors.white : _navy,
                                  side: const BorderSide(color: _navy),
                                ),
                                onPressed: () => setDialogState(() => variation = v.name),
                                child: Text(v.name),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (availableAddons.isNotEmpty) ...[
                      const Text('ADD-ONS | CHOOSE MULTIPLE', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availableAddons.map((addon) {
                          final selected = addons.contains(addon.name);
                          final priceLabel = addon.price > 0 ? ' (+${_currency.format(addon.price)})' : '';
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected ? _navy : Colors.transparent,
                              foregroundColor: selected ? Colors.white : _navy,
                              side: const BorderSide(color: _navy),
                            ),
                            onPressed: () => setDialogState(() {
                              if (selected) {
                                addons.remove(addon.name);
                              } else {
                                addons.add(addon.name);
                              }
                            }),
                            child: Text('${addon.name}$priceLabel', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text('QUANTITY', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                        title: const Text('Member discount 10%', style: TextStyle(fontSize: 13, color: _navy)),
                        value: memberDiscount,
                        onChanged: (v) => setDialogState(() => memberDiscount = v),
                      ),
                    ],
                    if (itemPromo != null) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: Colors.green,
                        title: Text(
                          itemPromo.name,
                          style: const TextStyle(fontSize: 13, color: _navy, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          itemPromo.discountType == 'fixed'
                              ? '-${_currency.format(itemPromo.value.round())} per item'
                              : '-${itemPromo.value.toStringAsFixed(0)}% per item',
                          style: const TextStyle(fontSize: 11, color: Colors.green),
                        ),
                        value: itemPromoOptIn,
                        onChanged: (v) => setDialogState(() => itemPromoOptIn = v),
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
      final addonTotal = addons.fold<int>(0, (s, a) => s + (addonPriceMap[a] ?? 0));
      int unit = p.price + addonTotal;
      if (memberDiscount) unit = (unit * 0.9).round();
      final optInId = (itemPromo != null && itemPromoOptIn) ? itemPromo.id : null;
      final variationLabel = variation ?? '';
      final sig = '${p.id}-$variationLabel-${addons.join(",")}-$memberDiscount-${optInId ?? ""}';
      setState(() {
        final existing = _cart.where((l) => l.signature == sig);
        if (existing.isNotEmpty) {
          existing.first.qty += qty;
        } else {
          _cart.add(CartLine(
            signature: sig,
            product: p,
            variation: variationLabel,
            addons: addons.toList(),
            memberDiscount: memberDiscount,
            unitPrice: unit,
            qty: qty,
            optInPromoId: optInId,
          ));
        }
      });
    }
  }

  Future<void> _pickMember() async {
    final phoneController = TextEditingController();
    final guestController = TextEditingController(text: _guestName ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customer', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FIND MEMBER (PHONE NO.)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: '08xxxxxxxxxx', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: () {
                    final m = DbService.findMemberByPhone(phoneController.text.trim());
                    if (m == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Member not found. Register them first in the Member tab.')),
                      );
                      return;
                    }
                    setState(() {
                      _selectedMember = m;
                      _guestName = null;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('OR GUEST NAME (NON-MEMBER)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: guestController,
                    decoration: const InputDecoration(hintText: 'Customer name', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                  onPressed: () {
                    if (guestController.text.trim().isEmpty) return;
                    setState(() {
                      _guestName = guestController.text.trim();
                      _selectedMember = null;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Pakai'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _pickSalesType() async {
    final customCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Select Sales Type', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in ['Dine In', 'Take Away'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _salesType == o ? _navy : Colors.transparent,
                            foregroundColor: _salesType == o ? Colors.white : _navy,
                            side: const BorderSide(color: _navy),
                          ),
                          onPressed: () => Navigator.pop(ctx, o),
                          child: Text(o),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('ONLINE ORDER', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['GoFood', 'GrabFood', 'ShopeeFood'].map((platform) {
                      final label = 'Online - $platform';
                      return OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _salesType == label ? _navy : Colors.transparent,
                          foregroundColor: _salesType == label ? Colors.white : _navy,
                          side: const BorderSide(color: _navy),
                        ),
                        onPressed: () => Navigator.pop(ctx, label),
                        child: Text(platform),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Other platform',
                            hintText: 'Enter manually',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _navy),
                        onPressed: () {
                          if (customCtrl.text.trim().isEmpty) return;
                          Navigator.pop(ctx, 'Online - ${customCtrl.text.trim()}');
                        },
                        child: const Text('Pakai'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) setState(() => _salesType = result);
  }

  Future<void> _saveBillDraft() async {
    if (_cart.isEmpty) return;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Bill', style: TextStyle(color: _navy)),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(labelText: 'Table Name/Number (optional)', hintText: 'e.g. Table 5'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final bill = HeldBill(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      items: _cart
          .map((l) => HeldBillItem(
                productId: l.product.id,
                productName: l.product.name,
                unitPrice: l.unitPrice,
                qty: l.qty,
                variation: l.variation,
                addons: l.addons,
                memberDiscount: l.memberDiscount,
                optInPromoId: l.optInPromoId,
              ))
          .toList(),
      salesType: _salesType,
      memberId: _selectedMember?.id,
      guestName: _guestName,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      chosenPromoId: _chosenPromoId,
    );
    await DbService.saveHeldBill(bill);

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
      _guestName = null;
      _chosenPromoId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bill${bill.note != null ? ' (${bill.note})' : ''} saved.')),
    );
  }

  void _openHeldBillsList() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saved Bills', style: TextStyle(color: _navy)),
        content: SizedBox(
          width: 360,
          child: ValueListenableBuilder(
            valueListenable: DbService.heldBills.listenable(),
            builder: (context, box, _) {
              final bills = DbService.heldBillsSorted;
              if (bills.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No saved bills yet.', style: TextStyle(color: Colors.grey)),
                );
              }
              return SizedBox(
                height: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bills.length,
                  itemBuilder: (ctx, i) {
                    final bill = bills[i];
                    final total = bill.items.fold<int>(0, (s, it) => s + it.unitPrice * it.qty);
                    return ListTile(
                      title: Text(bill.note ?? 'Bill ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                      subtitle: Text(
                        '${bill.items.length} item • ${_currency.format(total)} • ${DateFormat('HH:mm').format(bill.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _loadHeldBill(bill);
                            },
                            child: const Text('Open'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (c2) => AlertDialog(
                                  title: const Text('Delete This Bill?'),
                                  content: const Text('Deleted bills cannot be recovered.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) await DbService.deleteHeldBill(bill.id);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _loadHeldBill(HeldBill bill) async {
    if (_cart.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cart Not Empty'),
          content: const Text('Opening this bill will replace your current cart. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _navy),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final newCart = <CartLine>[];
    final skippedItems = <String>[];
    for (final item in bill.items) {
      final product = DbService.products.get(item.productId);
      if (product == null) {
        skippedItems.add(item.productName);
        continue;
      }
      final sig = '${product.id}-${item.variation}-${item.addons.join(",")}-${item.memberDiscount}-${item.optInPromoId ?? ""}';
      newCart.add(CartLine(
        signature: sig,
        product: product,
        variation: item.variation,
        addons: item.addons,
        memberDiscount: item.memberDiscount,
        unitPrice: item.unitPrice,
        qty: item.qty,
        optInPromoId: item.optInPromoId,
      ));
    }

    Member? member;
    if (bill.memberId != null) member = DbService.members.get(bill.memberId);

    setState(() {
      _cart
        ..clear()
        ..addAll(newCart);
      _salesType = bill.salesType;
      _selectedMember = member;
      _guestName = bill.guestName;
      _chosenPromoId = bill.chosenPromoId;
    });

    await DbService.deleteHeldBill(bill.id);

    if (!mounted) return;
    if (skippedItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Product not found (may have been deleted): ${skippedItems.join(", ")}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bill${bill.note != null ? ' (${bill.note})' : ''} opened.')),
      );
    }
  }

  void _printBill() {
    if (_cart.isEmpty) return;
    final totals = _totals;
    final draftTx = TransactionRecord(
      id: 'draft',
      items: _cart
          .map((l) => TxItem(
                productId: l.product.id,
                productName: l.product.name,
                price: l.unitPrice,
                qty: l.qty,
                note: _lineDiscountNote(l) != null ? '${l.note} • ${_lineDiscountNote(l)}' : l.note,
              ))
          .toList(),
      total: totals['grandTotal']!,
      createdAt: DateTime.now(),
      memberId: _selectedMember?.id,
      paymentMethod: 'unpaid',
      salesType: _salesType,
      taxAmount: totals['tax']!,
      serviceAmount: totals['service']!,
      discountAmount: totals['discount']!,
      roundingAdjustment: totals['rounding']!,
      guestName: _guestName,
      discountLabel: _discountLabel,
      queueCode: null,
    );
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
                  ReceiptView(tx: draftTx),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _printKitchenOrder() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Text('KITCHEN ORDER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navy, letterSpacing: 1)),
                        Text(DbService.businessName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(_salesType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
                  if (_selectedMember != null)
                    Text('Customer: ${_selectedMember!.name}', style: const TextStyle(fontSize: 12, color: Colors.grey))
                  else if (_guestName != null)
                    Text('Customer: $_guestName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  ..._cart.map((l) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${l.qty}x', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
                                  Text(l.note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                  const Center(child: Text('— For Kitchen, not a customer receipt —', style: TextStyle(fontSize: 10, color: Colors.grey))),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkout(String paymentMethod, {int? cashReceived, int? changeAmount}) async {
    if (_cart.isEmpty) return;
    final totals = _totals;
    final items = _cart
        .map((l) => TxItem(
              productId: l.product.id,
              productName: l.product.name,
              price: l.unitPrice,
              qty: l.qty,
              note: _lineDiscountNote(l) != null ? '${l.note} • ${_lineDiscountNote(l)}' : l.note,
            ))
        .toList();

    final prefillPhone = _selectedMember?.phone ?? '';
    final discountLabel = _discountLabel;

    final tx = await DbService.saveTransaction(
      items: items,
      paymentMethod: paymentMethod,
      memberId: _selectedMember?.id,
      salesType: _salesType,
      taxAmount: totals['tax']!,
      serviceAmount: totals['service']!,
      discountAmount: totals['discount']!,
      roundingAdjustment: totals['rounding']!,
      guestName: _guestName,
      discountLabel: discountLabel,
      cashReceived: cashReceived,
      changeAmount: changeAmount,
    );

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
      _guestName = null;
      _chosenPromoId = null;
    });

    await _showPostPaymentPage(tx, prefillPhone);
  }

  Future<void> _showPostPaymentPage(TransactionRecord tx, String prefillPhone) async {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: prefillPhone);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 56),
                  const SizedBox(height: 8),
                  const Center(child: Text('Payment Successful!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: _navy))),
                  const SizedBox(height: 4),
                  Center(child: Text(currency.format(tx.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy))),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => _showReceiptDialog(tx),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Print / View Receipt'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Send receipt via Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(hintText: 'email@example.com', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _navy),
                        onPressed: () {
                          if (emailCtrl.text.trim().isEmpty) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Receipt will be sent to ${emailCtrl.text.trim()} (needs an email service connected on the backend)')),
                          );
                        },
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Send receipt via SMS/WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(hintText: '08xxxxxxxxxx', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _navy),
                        onPressed: () {
                          if (phoneCtrl.text.trim().isEmpty) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Receipt will be sent to ${phoneCtrl.text.trim()} (needs an SMS/WhatsApp service connected on the backend)')),
                          );
                        },
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReceiptDialog(TransactionRecord tx) {
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
                  ReceiptView(tx: tx),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
              'Ask the customer to scan the QRIS at the counter, then confirm once payment is received.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () {
              Navigator.pop(ctx);
              _checkout('qris_manual');
            },
            child: const Text('Payment Received'),
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
                      _checkout('cash', cashReceived: a, changeAmount: a - total);
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
                        labelText: 'Other amount',
                        hintText: 'Enter cash amount',
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
                          const SnackBar(content: Text('Amount is less than the total due')),
                        );
                        return;
                      }
                      final change = amount - total;
                      Navigator.pop(ctx);
                      _checkout('cash', cashReceived: amount, changeAmount: change);
                      if (change > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Kembalian: ${_currency.format(change)}')),
                        );
                      }
                    },
                    child: const Text('Pay'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('QRIS (Manual, without Midtrans)', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openManualQrisDialog(total);
                },
                icon: const Icon(Icons.qr_code, size: 18),
                label: const Text('Show QRIS Code'),
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
              const Text('EDC / Card', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
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
  void dispose() {
    _pageController.dispose();
    _customCashController.dispose();
    super.dispose();
  }

  Widget _buildProductCard(Product p, {required Key key}) {
    final outOfStock = p.stock <= 0;
    return Material(
      key: key,
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
                      child: p.imageBase64 != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Opacity(
                                opacity: outOfStock ? 0.4 : 1,
                                child: Image.memory(base64Decode(p.imageBase64!), fit: BoxFit.cover, width: double.infinity),
                              ),
                            )
                          : Icon(Icons.local_cafe_outlined, color: _navy.withValues(alpha: outOfStock ? 0.3 : 1), size: 32),
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
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Icon(Icons.drag_indicator, size: 16, color: _navy.withValues(alpha: 0.35)),
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
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = DbService.products.values.where((p) => p.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final categoryNames = DbService.categories.where((c) => allProducts.any((p) => p.category == c)).toList();
    final pages = <String?>[null, ...categoryNames]; // null = "Semua"
    if (_categoryIndex >= pages.length) _categoryIndex = 0;
    final totals = _totals;

    return Scaffold(
      backgroundColor: _grey,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 90,
        backgroundColor: _grey,
        title: Image.asset('assets/logo.png', height: 72),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: ValueListenableBuilder(
                valueListenable: DbService.heldBills.listenable(),
                builder: (context, box, _) {
                  final count = DbService.heldBills.length;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: _openHeldBillsList,
                        icon: const Icon(Icons.receipt_long_outlined, color: _navy),
                        tooltip: 'Saved Bills',
                      ),
                      if (count > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: IconButton(
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add_shopping_cart, color: _navy),
                tooltip: 'Custom Item',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShiftScreen())).then((_) => setState(() {})),
                borderRadius: BorderRadius.circular(20),
                child: Builder(builder: (context) {
                  final openShift = DbService.currentOpenShift;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: openShift != null ? Colors.green.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: openShift != null ? Colors.green : _navy, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale, size: 16, color: openShift != null ? Colors.green.shade800 : _navy),
                        const SizedBox(width: 6),
                        Text(
                          openShift != null ? 'Shift Active' : 'Start Shift',
                          style: TextStyle(fontSize: 12, color: openShift != null ? Colors.green.shade800 : _navy, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: InkWell(
                onTap: _openCashierLogin,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _navy, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person, size: 16, color: _navy),
                      const SizedBox(width: 6),
                      Text(
                        DbService.currentCashierName.isEmpty ? 'Set Cashier' : DbService.currentCashierName,
                        style: const TextStyle(fontSize: 12, color: _navy, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                if (pages.length > 1)
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: pages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final selected = i == _categoryIndex;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _categoryIndex = i);
                            _pageController.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? _navy : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _navy, width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              pages[i] ?? 'All',
                              style: TextStyle(color: selected ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _categoryIndex = i),
                    itemBuilder: (ctx, pageIndex) {
                      final category = pages[pageIndex]; // null = semua
                      final pageProducts = category == null
                          ? allProducts
                          : allProducts.where((p) => p.category == category).toList();
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: ReorderableGridView.count(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          onReorder: (oldIndex, newIndex) async {
                            final reordered = List<Product>.from(pageProducts);
                            final moved = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, moved);
                            if (category == null) {
                              await DbService.reorderAll(reordered.map((p) => p.id).toList());
                            } else {
                              await DbService.reorderWithinCategory(category, reordered.map((p) => p.id).toList());
                            }
                            if (mounted) setState(() {});
                          },
                          children: [
                            for (final p in pageProducts)
                              _buildProductCard(p, key: ValueKey(p.id)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
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
                            : (_guestName != null ? _guestName! : '+ Add Customer'),
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
                        ? const Center(child: Text('No items yet', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _cart.length,
                            itemBuilder: (ctx, i) {
                              final l = _cart[i];
                              final promoNote = _lineDiscountNote(l);
                              return ListTile(
                                title: Text(l.product.name, style: const TextStyle(color: _navy, fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    if (promoNote != null)
                                      Text(promoNote, style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(_currency.format(l.subtotal), style: const TextStyle(color: _navy)),
                                        Text('x${l.qty}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                                      tooltip: 'Cancel item (PIN required)',
                                      onPressed: () => _confirmRemoveLine(l),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  if (DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals).isNotEmpty) _buildPromoBanner(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      children: [
                        _totalRow('Sub-Total', _subtotal),
                        if (DbService.showZeroAmountRows || totals['tax']! != 0) _totalRow('Tax', totals['tax']!),
                        if (DbService.showZeroAmountRows || totals['service']! != 0) _totalRow('Service', totals['service']!),
                        if (totals['discount']! > 0)
                          _totalRow(
                            _discountLabel.isNotEmpty ? 'Discount (${_discountLabel})' : 'Discount',
                            -totals['discount']!,
                          ),
                        if (DbService.showZeroAmountRows || totals['rounding']! != 0) _totalRow('Rounding', totals['rounding']!),
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
                            child: Text('Save Bill', style: const TextStyle(color: _navy, fontSize: 12)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _printKitchenOrder,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: const Color(0xFFE0E0E0),
                            alignment: Alignment.center,
                            child: Text('Kitchen Order', style: const TextStyle(color: _navy, fontSize: 12)),
                          ),
                        ),
                      ),
                      if (DbService.printCheckEnabled)
                        Expanded(
                          child: InkWell(
                            onTap: _printBill,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: _grey,
                              alignment: Alignment.center,
                              child: Text('Print Check', style: const TextStyle(color: _navy, fontSize: 12)),
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
                        '${'Charge'} ${_currency.format(_grandTotal)}',
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

  Widget _buildPromoBanner() {
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals);
    final resolved = _resolveDiscount();
    final applied = resolved.promo != null;
    final pending = !applied && valid.length > 1 && _chosenPromoId != 'NONE';

    return InkWell(
      onTap: _openPromoPicker,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: applied ? Colors.green.shade50 : (pending ? Colors.amber.shade50 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: applied ? Colors.green : (pending ? Colors.amber.shade700 : Colors.grey)),
        ),
        child: Row(
          children: [
            Icon(Icons.local_offer, size: 16, color: _navy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                applied
                    ? 'Promo: ${resolved.label}${resolved.promo!.scope == 'item' ? ' (check per item when added)' : ''}'
                    : (pending ? '${valid.length} promos available — pick one' : 'No promo'),
                style: const TextStyle(fontSize: 12, color: _navy, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _navy),
          ],
        ),
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
CASHIEREOF

cat > lib/screens/settings_screen.dart << 'SETEOF'
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
        title: const Text('Dashboard Connection', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL Server Sync')),
            const SizedBox(height: 8),
            TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'API Code')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
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
SETEOF

cat > lib/screens/shift_screen.dart << 'SHIFTEOF'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shift.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';

const _navy = Color(0xFF092762);

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');

  Future<void> _startShift() async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Shift', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cashier: ${DbService.currentCashierName.isEmpty ? "(not set)" : DbService.currentCashierName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Starting Cash (Rp)'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Shift'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final startingCash = int.tryParse(ctrl.text) ?? 0;
      await DbService.startShift(startingCash: startingCash);
      setState(() {});
    }
  }

  Future<void> _endShift(Shift shift) async {
    final expected = DbService.expectedCashForShift(shift);
    final countedCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final counted = int.tryParse(countedCtrl.text);
          final diff = counted != null ? counted - expected : null;
          return AlertDialog(
            title: const Text('End Shift & Settlement', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Starting Cash', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  const Divider(),
                  _summaryRow('Expected Cash in Drawer', expected, bold: true),
                  const SizedBox(height: 12),
                  TextField(
                    controller: countedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Actual Cash Counted (Rp)'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      diff == 0
                          ? 'Spot on! No difference.'
                          : diff > 0
                              ? 'Over Rp${_currency.format(diff).replaceFirst("Rp ", "")}'
                              : 'Short Rp${_currency.format(diff.abs()).replaceFirst("Rp ", "")}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: counted == null
                    ? null
                    : () async {
                        await DbService.endShift(endingCashCounted: counted, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
                child: const Text('Close Shift'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _viewShiftDetail(Shift shift) {
    final expected = shift.status == 'closed' ? DbService.expectedCashForShift(shift) : null;
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
                  Text(shift.cashierName.isEmpty ? 'Cashier' : shift.cashierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                  Text('Started: ${_dateFmt.format(shift.startTime)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (shift.endTime != null) Text('Ended: ${_dateFmt.format(shift.endTime!)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  _summaryRow('Starting Cash', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  if (expected != null) ...[
                    const Divider(),
                    _summaryRow('Expected Cash', expected, bold: true),
                    _summaryRow('Cash Counted', shift.endingCashCounted ?? 0, bold: true),
                    _summaryRow('Difference', (shift.endingCashCounted ?? 0) - expected, bold: true),
                  ],
                  if (shift.note != null && shift.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Note: ${shift.note}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(color: _navy, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 14 : 13);
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

  @override
  Widget build(BuildContext context) {
    final open = DbService.currentOpenShift;
    final history = DbService.shiftHistory.where((s) => s.status == 'closed').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Shift')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (open == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No Active Shift', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                    const SizedBox(height: 8),
                    const Text('Start a shift to record starting cash and settle up later.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: _startShift,
                      child: const Text('Start Shift'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.play_circle_fill, color: Colors.green, size: 20),
                        const SizedBox(width: 6),
                        const Text('Active Shift', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Cashier: ${open.cashierName.isEmpty ? "-" : open.cashierName}', style: const TextStyle(fontSize: 13)),
                    Text('Started: ${_dateFmt.format(open.startTime)}', style: const TextStyle(fontSize: 13)),
                    Text('Starting Cash: ${_currency.format(open.startingCash)}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    const Text('Sales so far:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                    ...DbService.salesDuringShift(open).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: () => _endShift(open),
                      child: const Text('End Shift & Settlement'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Shift History', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text('No completed shifts yet.', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ...history.map((s) {
              final expected = DbService.expectedCashForShift(s);
              final diff = (s.endingCashCounted ?? 0) - expected;
              return ListTile(
                dense: true,
                onTap: () => _viewShiftDetail(s),
                title: Text('${s.cashierName.isEmpty ? "Cashier" : s.cashierName} • ${_dateFmt.format(s.startTime)}'),
                subtitle: Text(diff == 0 ? 'Spot on' : (diff > 0 ? 'Over ${_currency.format(diff)}' : 'Short ${_currency.format(diff.abs())}')),
                trailing: Icon(Icons.circle, size: 10, color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red)),
              );
            }),
        ],
      ),
    );
  }
}
SHIFTEOF

cat > lib/screens/promo_screen.dart << 'PROMOEOF'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/promo.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  final _uuid = const Uuid();
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Future<void> _editPromo({Promo? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(text: existing != null ? existing.value.toStringAsFixed(existing.discountType == 'percentage' ? 1 : 0) : '');
    final minPurchaseCtrl = TextEditingController(text: '${existing?.minPurchase ?? 0}');
    String discountType = existing?.discountType ?? 'percentage';
    String scope = existing?.scope ?? 'cart';
    final selectedProductIds = <String>{...(existing?.productIds ?? [])};
    DateTime? startDate = existing?.startDate;
    DateTime? endDate = existing?.endDate;
    bool active = existing?.active ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'New Promo' : 'Edit Promo', style: const TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Promo name', hintText: 'mis. Promo Ramadan')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Persen (%)', style: TextStyle(fontSize: 13)),
                          value: 'percentage',
                          groupValue: discountType,
                          onChanged: (v) => setDialogState(() => discountType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Nominal (Rp)', style: TextStyle(fontSize: 13)),
                          value: 'fixed',
                          groupValue: discountType,
                          onChanged: (v) => setDialogState(() => discountType = v!),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: discountType == 'percentage' ? 'Discount amount (%)' : 'Discount amount (Rp)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minPurchaseCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minimum pembelian (Rp, 0 = tanpa minimum)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setDialogState(() => startDate = picked);
                          },
                          child: Text(startDate == null ? 'Start date' : _dateFmt.format(startDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setDialogState(() => endDate = picked);
                          },
                          child: Text(endDate == null ? 'End date' : _dateFmt.format(endDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const Text('Leave dates blank to run indefinitely.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 12),
                  const Text('APPLIES TO', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entire Receipt', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Discount calculated from total spend', style: TextStyle(fontSize: 11)),
                    value: 'cart',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Specific Products (preset)', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Automatically applied when checked products are in the cart', style: TextStyle(fontSize: 11)),
                    value: 'product',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Per Item (optional at checkout)', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Cashier checks it manually per product when adding to cart, e.g. discount for bringing your own tumbler', style: TextStyle(fontSize: 11)),
                    value: 'item',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  if (scope == 'product' || scope == 'item') ...[
                    const SizedBox(height: 4),
                    Text(
                      scope == 'item' ? 'Limit to specific products (optional, leave blank = applies to all products):' : 'Select products:',
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: ListView(
                        shrinkWrap: true,
                        children: DbService.products.values.map((p) {
                          final checked = selectedProductIds.contains(p.id);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            activeColor: _navy,
                            title: Text(p.name, style: const TextStyle(fontSize: 13)),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedProductIds.add(p.id);
                              } else {
                                selectedProductIds.remove(p.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                    if (scope == 'product' && selectedProductIds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Select at least 1 product.', style: TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: _navy,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  if (scope == 'product' && selectedProductIds.isEmpty) return;
                  final promo = Promo(
                    id: existing?.id ?? _uuid.v4(),
                    name: nameCtrl.text.trim(),
                    discountType: discountType,
                    value: double.tryParse(valueCtrl.text) ?? 0,
                    startDate: startDate,
                    endDate: endDate,
                    minPurchase: int.tryParse(minPurchaseCtrl.text) ?? 0,
                    active: active,
                    scope: scope,
                    productIds: selectedProductIds.toList(),
                  );
                  await DbService.savePromo(promo);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePromo(Promo p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Promo?'),
        content: Text('Are you sure you want to delete "${p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await DbService.deletePromo(p.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final promos = DbService.promos.values.toList()
      ..sort((a, b) => b.active == a.active ? 0 : (b.active ? 1 : -1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promo'),
        actions: [IconButton(onPressed: () => _editPromo(), icon: const Icon(Icons.add))],
      ),
      body: promos.isEmpty
          ? const Center(child: Text('No promos yet. Tap + to create one.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: promos.length,
              itemBuilder: (ctx, i) {
                final p = promos[i];
                final valueLabel = p.discountType == 'percentage' ? '${p.value.toStringAsFixed(0)}%' : _currency.format(p.value.round());
                final dateLabel = (p.startDate != null || p.endDate != null)
                    ? '${p.startDate != null ? _dateFmt.format(p.startDate!) : 'kapan aja'} — ${p.endDate != null ? _dateFmt.format(p.endDate!) : 'seterusnya'}'
                    : 'Runs indefinitely';
                return ListTile(
                  leading: Icon(Icons.local_offer, color: p.active ? _navy : Colors.grey),
                  title: Text(p.name, style: TextStyle(color: p.active ? _navy : Colors.grey, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Discount $valueLabel${p.minPurchase > 0 ? ' • min. ${_currency.format(p.minPurchase)}' : ''}'
                    '${p.scope == 'product' ? ' • ${p.productIds.length} products (preset)' : p.scope == 'item' ? ' • per item${p.productIds.isNotEmpty ? ' (${p.productIds.length} products)' : ' (all products)'}' : ' • entire receipt'}\n$dateLabel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!p.active) const Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editPromo(existing: p)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deletePromo(p)),
                    ],
                  ),
                  onTap: () => _editPromo(existing: p),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: () => _editPromo(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
PROMOEOF

cat > lib/screens/home_screen.dart << 'HOMEEOF'
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'cashier_screen.dart';
import 'membership_screen.dart';
import 'report_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

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
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
    final nameCtrl = TextEditingController(text: DbService.currentCashierName);
    final emailCtrl = TextEditingController(text: DbService.currentCashierEmail);
    final cashCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Shift', style: TextStyle(color: _navy)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Cashier Name')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Cashier Email'), keyboardType: TextInputType.emailAddress),
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
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Start Shift'),
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
                  style: TextStyle(color: Colors.grey),
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
              NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Laporan'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}
HOMEEOF

echo 'Selesai. Jalankan: flutter clean && flutter pub get && flutter run -d web-server --web-port 8081 --release'
