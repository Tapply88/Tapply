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

const _navy = Color(0xFF623609);
const _grey = Color(0xFFD6CFC6);

class CartLine {
  final String signature;
  final Product product;
  final String variation;
  final List<String> addons;
  final bool memberDiscount;
  final int unitPrice;
  int qty;
  final String? optInPromoId; // promo scope 'item' yang di-opt-in khusus baris ini
  String? splitGroup; // buat split bill: 'A', 'B', dst. null = belum di-assign.

  CartLine({
    required this.signature,
    required this.product,
    required this.variation,
    required this.addons,
    required this.memberDiscount,
    required this.unitPrice,
    required this.qty,
    this.optInPromoId,
    this.splitGroup,
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
  int _pointsToRedeem = 0;
  String? _guestName;
  String _salesType = 'Dine In';

  int _basePriceFor(Product p) {
    if (_salesType.startsWith('Online') && p.onlinePrice != null) return p.onlinePrice!;
    return p.price;
  }
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
              style: TextStyle(fontSize: 12, color: const Color(0xFF623609)),
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
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals, selectedMember: _selectedMember);

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

  int get _pointsRedemptionDiscount => _pointsToRedeem * DbService.pointsRedemptionValue;

  Map<String, int> get _totals =>
      DbService.computeTotals(_subtotal, discountAmount: _resolveDiscount().amount + _pointsRedemptionDiscount);
  int get _grandTotal => _totals['grandTotal']!;
  String get _discountLabel {
    final promoLabel = _resolveDiscount().label;
    if (_pointsToRedeem > 0) {
      final pointsLabel = '$_pointsToRedeem pts redeemed';
      return promoLabel.isNotEmpty ? '$promoLabel + $pointsLabel' : pointsLabel;
    }
    return promoLabel;
  }

  Future<void> _openPromoPicker() async {
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals, selectedMember: _selectedMember);
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
              style: TextStyle(fontSize: 12, color: const Color(0xFF623609)),
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
              if (DbService.hashPin(pinCtrl.text) == DbService.managerPin) {
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
    final isOnlineOrder = _salesType.startsWith('Online');
    final addonPriceMap = {
      for (final a in availableAddons) a.name: (isOnlineOrder && a.onlinePrice != null) ? a.onlinePrice! : a.price,
    };
    final variationPriceMap = {
      for (final v in availableVariations) v.name: (isOnlineOrder && v.onlinePrice != null) ? v.onlinePrice! : v.price,
    };

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
          final variationPrice = variationPriceMap[variation] ?? 0;
          int unit = _basePriceFor(p) + variationPrice + addonTotal;
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
                      const Text('VARIATION | CHOOSE ONE', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availableVariations.map((v) {
                          final selected = variation == v.name;
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected ? _navy : Colors.transparent,
                              foregroundColor: selected ? Colors.white : _navy,
                              side: const BorderSide(color: _navy),
                            ),
                            onPressed: () => setDialogState(() => variation = v.name),
                            child: Text(variationPriceMap[v.name]! > 0 ? '${v.name} (+${_currency.format(variationPriceMap[v.name]!)})' : v.name),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (availableAddons.isNotEmpty) ...[
                      const Text('ADD-ONS | CHOOSE MULTIPLE', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availableAddons.map((addon) {
                          final selected = addons.contains(addon.name);
                          final priceLabel = addonPriceMap[addon.name]! > 0 ? ' (+${_currency.format(addonPriceMap[addon.name]!)})' : '';
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
                    const Text('QUANTITY', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
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
                        activeThumbColor: const Color(0xFF623609),
                        title: Text(
                          itemPromo.name,
                          style: const TextStyle(fontSize: 13, color: _navy, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          itemPromo.discountType == 'fixed'
                              ? '-${_currency.format(itemPromo.value.round())} per item'
                              : '-${itemPromo.value.toStringAsFixed(0)}% per item',
                          style: const TextStyle(fontSize: 11, color: const Color(0xFF623609)),
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
      final variationPrice = variationPriceMap[variation] ?? 0;
      int unit = _basePriceFor(p) + variationPrice + addonTotal;
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

  Future<void> _openRedeemPointsDialog() async {
    final member = _selectedMember;
    if (member == null) return;
    final multiple = DbService.pointsRedemptionMultiple;
    final maxByPoints = member.points;
    final maxBySubtotal = DbService.pointsRedemptionValue > 0 ? (_subtotal / DbService.pointsRedemptionValue).floor() : 0;
    final rawMax = maxByPoints < maxBySubtotal ? maxByPoints : maxBySubtotal;
    final maxRedeemable = multiple > 0 ? (rawMax ~/ multiple) * multiple : rawMax;
    final ctrl = TextEditingController(text: _pointsToRedeem > 0 ? '$_pointsToRedeem' : '');

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final entered = int.tryParse(ctrl.text) ?? 0;
          final value = entered * DbService.pointsRedemptionValue;
          return AlertDialog(
            title: const Text('Redeem Points', style: TextStyle(color: _navy)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${member.name} has ${member.points} points.', style: const TextStyle(fontSize: 13)),
                Text(
                  'Rate: ${_currency.format(DbService.pointsRedemptionValue)} per point. Redeem in multiples of $multiple. Max now: $maxRedeemable pts.',
                  style: const TextStyle(fontSize: 11, color: const Color(0xFF623609)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(labelText: 'Points to redeem (multiples of $multiple)'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (entered > 0) ...[
                  const SizedBox(height: 8),
                  Text('= ${_currency.format(value)} discount', style: const TextStyle(fontSize: 13, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
                ],
                if (maxRedeemable >= multiple)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (int q = multiple; q <= maxRedeemable; q += multiple)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy, padding: const EdgeInsets.symmetric(horizontal: 10)),
                            onPressed: () => setDialogState(() => ctrl.text = '$q'),
                            child: Text('$q', style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              if (_pointsToRedeem > 0)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 0),
                  child: const Text('Clear', style: TextStyle(color: Colors.red)),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () {
                  if (entered < 0 || entered > maxRedeemable) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Enter a number between 0 and $maxRedeemable')));
                    return;
                  }
                  if (multiple > 0 && entered % multiple != 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Must be a multiple of $multiple')));
                    return;
                  }
                  Navigator.pop(ctx, entered);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) setState(() => _pointsToRedeem = result);
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
            const Text('FIND MEMBER (PHONE NO.)', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
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
                      _pointsToRedeem = 0;
                      _guestName = null;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('OR GUEST NAME (NON-MEMBER)', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
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
      _pointsToRedeem = 0;
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
                  const Text('ONLINE ORDER', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
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
      _pointsToRedeem = 0;
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
                  child: Text('No saved bills yet.', style: TextStyle(color: const Color(0xFF623609))),
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
      _pointsToRedeem = 0;
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
                        Text(DbService.businessName, style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 11, color: const Color(0xFF623609))),
                  Text(_salesType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
                  if (_selectedMember != null)
                    Text('Customer: ${_selectedMember!.name}', style: const TextStyle(fontSize: 12, color: const Color(0xFF623609)))
                  else if (_guestName != null)
                    Text('Customer: $_guestName', style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
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
                                  Text(l.note, style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                  const Center(child: Text('— For Kitchen, not a customer receipt —', style: TextStyle(fontSize: 10, color: const Color(0xFF623609)))),
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

    if (_selectedMember != null && _pointsToRedeem > 0) {
      final member = _selectedMember!;
      member.points -= _pointsToRedeem;
      await DbService.saveMember(member);
    }

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
      _pointsToRedeem = 0;
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
                  const Icon(Icons.check_circle, color: const Color(0xFF623609), size: 56),
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
              style: TextStyle(fontSize: 13, color: const Color(0xFF623609)),
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
              const SizedBox(height: 20),
              const Text('Online Order Platform', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['GoFood', 'GrabFood', 'ShopeeFood'].map((p) {
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkout(p.toLowerCase());
                    },
                    child: Text(p),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text('Other', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkout('bank_transfer');
                    },
                    child: const Text('Bank Transfer'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final customCtrl = TextEditingController();
                      final label = await showDialog<String>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Other Payment Method', style: TextStyle(color: _navy)),
                          content: TextField(
                            controller: customCtrl,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Method name', hintText: 'e.g. Company Invoice'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: _navy),
                              onPressed: () => Navigator.pop(dctx, customCtrl.text.trim()),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      );
                      if (label != null && label.isNotEmpty) {
                        _checkout('other_$label');
                      }
                    },
                    child: const Text('Other (specify)'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }


  Future<void> _startSplitPayment(List<List<CartLine>> groups) async {
    final queue = List<List<CartLine>>.from(groups);
    while (queue.isNotEmpty) {
      final currentGroupItems = queue.removeAt(0);
      setState(() {
        _cart
          ..clear()
          ..addAll(currentGroupItems);
      });
      await _openPaymentSheet();
      if (_cart.isNotEmpty) {
        setState(() {
          _cart.addAll(queue.expand((g) => g));
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Split payment cancelled. Remaining items are back in the cart.')),
          );
        }
        return;
      }
    }
  }

  Future<void> _openSplitBillDialog() async {
    if (_cart.isEmpty) return;
    final Map<String, String?> assignments = {for (final l in _cart) l.signature: l.splitGroup};
    List<String> people = [];
    for (final v in assignments.values) {
      if (v != null && !people.contains(v)) people.add(v);
    }
    if (people.isEmpty) people = ['A', 'B'];
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void addPerson() {
            final nextLetter = String.fromCharCode('A'.codeUnitAt(0) + people.length);
            setDialogState(() => people.add(nextLetter));
          }

          return AlertDialog(
            title: const Text('Split Bill', style: TextStyle(color: _navy)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tap a letter to assign each item to a person.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    ..._cart.map((line) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${line.product.name} x${line.qty}', style: const TextStyle(fontSize: 13)),
                            ),
                            Wrap(
                              spacing: 6,
                              children: people.map((p) {
                                final selected = assignments[line.signature] == p;
                                return ChoiceChip(
                                  label: Text(p, style: TextStyle(color: selected ? Colors.white : _navy)),
                                  selected: selected,
                                  selectedColor: _navy,
                                  backgroundColor: Colors.transparent,
                                  side: const BorderSide(color: _navy),
                                  onSelected: (_) {
                                    setDialogState(() => assignments[line.signature] = p);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: addPerson,
                      icon: const Icon(Icons.person_add_alt, size: 16, color: _navy),
                      label: const Text('Add Person', style: TextStyle(color: _navy)),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () {
                  final unassigned = assignments.values.where((v) => v == null).length;
                  final distinctUsed = assignments.values.whereType<String>().toSet().length;
                  if (unassigned > 0) {
                    setDialogState(() => errorText = 'Assign all items before splitting.');
                    return;
                  }
                  if (distinctUsed < 2) {
                    setDialogState(() => errorText = 'Split needs at least 2 people.');
                    return;
                  }
                  for (final line in _cart) {
                    line.splitGroup = assignments[line.signature];
                  }
                  final groups = <String, List<CartLine>>{};
                  for (final line in _cart) {
                    groups.putIfAbsent(line.splitGroup!, () => []).add(line);
                  }
                  Navigator.pop(ctx);
                  _startSplitPayment(groups.values.toList());
                },
                child: const Text('Start Split Payment'),
              ),
            ],
          );
        },
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
                          outOfStock ? 'Out of Stock' : 'Stock ${p.stock}',
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: outOfStock ? const Color(0xFF623609) : _navy)),
                    Text(_currency.format(_basePriceFor(p)), style: TextStyle(fontSize: 12, color: outOfStock ? const Color(0xFF623609) : _navy)),
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
                      color: openShift != null ? const Color(0xFFEFECE5) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: openShift != null ? const Color(0xFF623609) : _navy, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale, size: 16, color: openShift != null ? const Color(0xFF623609) : _navy),
                        const SizedBox(width: 6),
                        Text(
                          openShift != null ? 'Shift Active' : 'Start Shift',
                          style: TextStyle(fontSize: 12, color: openShift != null ? const Color(0xFF623609) : _navy, fontWeight: FontWeight.bold),
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
                  if (_cart.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openSplitBillDialog,
                          icon: const Icon(Icons.call_split, size: 16, color: _navy),
                          label: const Text('Split Bill', style: TextStyle(color: _navy, fontSize: 12)),
                        ),
                      ),
                    ),
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
                  if (_selectedMember != null && _selectedMember!.points > 0)
                    InkWell(
                      onTap: _openRedeemPointsDialog,
                      child: Container(
                        width: double.infinity,
                        color: _pointsToRedeem > 0 ? const Color(0xFFEFECE5) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _pointsToRedeem > 0
                                  ? '$_pointsToRedeem pts redeemed (-${_currency.format(_pointsRedemptionDiscount)})'
                                  : 'Redeem Points',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _pointsToRedeem > 0 ? const Color(0xFF623609) : _navy,
                              ),
                            ),
                            Icon(Icons.card_giftcard, size: 16, color: _pointsToRedeem > 0 ? const Color(0xFF623609) : _navy),
                          ],
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
                        ? const Center(child: Text('No items yet', style: TextStyle(color: const Color(0xFF623609))))
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
                                    Text(l.note, style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
                                    if (promoNote != null)
                                      Text(promoNote, style: const TextStyle(fontSize: 12, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
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
                                        Text('x${l.qty}', style: const TextStyle(fontSize: 12, color: const Color(0xFF623609))),
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
                  if (DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals, selectedMember: _selectedMember).isNotEmpty) _buildPromoBanner(),
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
                            color: const Color(0xFFEFECE5),
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
                      color: _cart.isEmpty ? const Color(0xFF623609) : _navy,
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
    final valid = DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals, selectedMember: _selectedMember);
    final resolved = _resolveDiscount();
    final applied = resolved.promo != null;
    final pending = !applied && valid.length > 1 && _chosenPromoId != 'NONE';

    return InkWell(
      onTap: _openPromoPicker,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: applied ? const Color(0xFFEFECE5) : (pending ? Colors.amber.shade50 : const Color(0xFF623609)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: applied ? const Color(0xFF623609) : (pending ? Colors.amber.shade700 : const Color(0xFF623609))),
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
