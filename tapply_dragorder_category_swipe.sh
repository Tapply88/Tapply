cat > pubspec.yaml << 'PUBEOF'
name: tapply
description: Tapply - POS Kasir + Membership untuk bisnis F&B
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  http: ^1.2.1
  intl: ^0.19.0
  uuid: ^4.4.0
  provider: ^6.1.2
  fl_chart: ^0.68.0
  image_picker: ^1.1.2
  reorderable_grid_view: ^2.2.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  hive_generator: ^2.0.1
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/
PUBEOF

cat > lib/models/product.dart << 'PRODEOF'
import 'package:hive/hive.dart';

part 'product.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int price; // in Rupiah

  @HiveField(3)
  String category; // e.g. "Jamu", "Tambahan"

  @HiveField(4)
  bool isActive;

  @HiveField(5)
  int stock;

  @HiveField(6)
  String? imageBase64;

  @HiveField(7)
  int sortOrder;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.isActive = true,
    this.stock = 0,
    this.imageBase64,
    this.sortOrder = 0,
  });
}
PRODEOF

cat > lib/services/db_service.dart << 'DBEOF'
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';

class DbService {
  static const productBox = 'products';
  static const memberBox = 'members';
  static const txBox = 'transactions';
  static const settingsBox = 'settings';
  static final _uuid = const Uuid();

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(MemberAdapter());
    Hive.registerAdapter(TxItemAdapter());
    Hive.registerAdapter(TransactionRecordAdapter());

    await Hive.openBox<Product>(productBox);
    await Hive.openBox<Member>(memberBox);
    await Hive.openBox<TransactionRecord>(txBox);
    await Hive.openBox(settingsBox);

    await _seedProductsIfEmpty();
  }

  static Future<void> _seedProductsIfEmpty() async {
    final box = Hive.box<Product>(productBox);
    if (box.isNotEmpty) return;
    final seed = [
      Product(id: _uuid.v4(), name: 'Kunyit Asam', price: 12000, category: 'Jamu', stock: 30, sortOrder: 0),
      Product(id: _uuid.v4(), name: 'Beras Kencur', price: 12000, category: 'Jamu', stock: 30, sortOrder: 1),
      Product(id: _uuid.v4(), name: 'Temulawak', price: 13000, category: 'Jamu', stock: 30, sortOrder: 2),
      Product(id: _uuid.v4(), name: 'Sinom', price: 12000, category: 'Jamu', stock: 30, sortOrder: 3),
      Product(id: _uuid.v4(), name: 'Wedang Uwuh', price: 15000, category: 'Jamu', stock: 30, sortOrder: 4),
      Product(id: _uuid.v4(), name: 'Jahe Merah', price: 13000, category: 'Jamu', stock: 30, sortOrder: 5),
    ];
    for (final p in seed) {
      await box.put(p.id, p);
    }
  }

  // ---- Products ----
  static Box<Product> get products => Hive.box<Product>(productBox);

  static Future<void> adjustStock(String productId, int delta) async {
    final p = products.get(productId);
    if (p == null) return;
    p.stock = (p.stock + delta).clamp(0, 1 << 30);
    await p.save();
  }

  static Future<void> setStock(String productId, int newStock) async {
    final p = products.get(productId);
    if (p == null) return;
    p.stock = newStock.clamp(0, 1 << 30);
    await p.save();
  }

  static Future<void> addProduct({
    required String name,
    required int price,
    required String category,
    int stock = 0,
    String? imageBase64,
  }) async {
    final maxOrder = products.values.isEmpty ? 0 : products.values.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b);
    final p = Product(
      id: _uuid.v4(),
      name: name,
      price: price,
      category: category,
      stock: stock,
      imageBase64: imageBase64,
      sortOrder: maxOrder + 1,
    );
    await products.put(p.id, p);
  }

  static Future<void> setProductCategory(String productId, String category) async {
    final p = products.get(productId);
    if (p == null) return;
    p.category = category;
    await p.save();
  }

  static Future<void> setProductName(String productId, String name) async {
    final p = products.get(productId);
    if (p == null) return;
    p.name = name;
    await p.save();
  }

  /// Simpan urutan baru hasil drag-reorder untuk produk-produk dalam satu kategori.
  static Future<void> reorderCategory(List<String> orderedProductIds) async {
    for (var i = 0; i < orderedProductIds.length; i++) {
      final p = products.get(orderedProductIds[i]);
      if (p != null) {
        p.sortOrder = i;
        await p.save();
      }
    }
  }

  static Future<void> setProductImage(String productId, String? base64Data) async {
    final p = products.get(productId);
    if (p == null) return;
    p.imageBase64 = base64Data;
    await p.save();
  }

  // ---- Members ----
  static Box<Member> get members => Hive.box<Member>(memberBox);

  static Member? findMemberByPhone(String phone) {
    try {
      return members.values.firstWhere((m) => m.phone == phone);
    } catch (_) {
      return null;
    }
  }

  // ---- Settings (business profile + tax, service, discount, rounding) ----
  static Box get settings => Hive.box(settingsBox);

  static String get businessName => settings.get('businessName', defaultValue: 'Tapply');
  static String get businessAddress => settings.get('businessAddress', defaultValue: '');
  static String get businessPhone => settings.get('businessPhone', defaultValue: '');
  static String get receiptFooterText => settings.get('receiptFooterText', defaultValue: 'Terima kasih!');
  static String? get businessLogoBase64 => settings.get('businessLogoBase64', defaultValue: null);

  static Future<void> setBusinessLogo(String? base64Data) async {
    if (base64Data == null) {
      await settings.delete('businessLogoBase64');
    } else {
      await settings.put('businessLogoBase64', base64Data);
    }
  }

  static bool get taxEnabled => settings.get('taxEnabled', defaultValue: false);
  static double get taxPercent => settings.get('taxPercent', defaultValue: 11.0);
  static bool get serviceEnabled => settings.get('serviceEnabled', defaultValue: false);
  static double get servicePercent => settings.get('servicePercent', defaultValue: 5.0);
  static bool get discountEnabled => settings.get('discountEnabled', defaultValue: false);
  static double get discountPercent => settings.get('discountPercent', defaultValue: 0.0);
  static String get discountPromoName => settings.get('discountPromoName', defaultValue: '');
  static bool get roundingEnabled => settings.get('roundingEnabled', defaultValue: false);
  static int get roundingNearest => settings.get('roundingNearest', defaultValue: 100);

  static Future<void> updateBusinessProfile({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? receiptFooterText,
  }) async {
    if (businessName != null) await settings.put('businessName', businessName);
    if (businessAddress != null) await settings.put('businessAddress', businessAddress);
    if (businessPhone != null) await settings.put('businessPhone', businessPhone);
    if (receiptFooterText != null) await settings.put('receiptFooterText', receiptFooterText);
  }

  static Future<void> updateSettings({
    bool? taxEnabled,
    double? taxPercent,
    bool? serviceEnabled,
    double? servicePercent,
    bool? discountEnabled,
    double? discountPercent,
    String? discountPromoName,
    bool? roundingEnabled,
    int? roundingNearest,
  }) async {
    if (taxEnabled != null) await settings.put('taxEnabled', taxEnabled);
    if (taxPercent != null) await settings.put('taxPercent', taxPercent);
    if (serviceEnabled != null) await settings.put('serviceEnabled', serviceEnabled);
    if (servicePercent != null) await settings.put('servicePercent', servicePercent);
    if (discountEnabled != null) await settings.put('discountEnabled', discountEnabled);
    if (discountPercent != null) await settings.put('discountPercent', discountPercent);
    if (discountPromoName != null) await settings.put('discountPromoName', discountPromoName);
    if (roundingEnabled != null) await settings.put('roundingEnabled', roundingEnabled);
    if (roundingNearest != null) await settings.put('roundingNearest', roundingNearest);
  }

  /// Hitung rincian total dari subtotal item: {tax, service, discount, rounding, grandTotal}
  static Map<String, int> computeTotals(int subtotal) {
    final tax = taxEnabled ? (subtotal * taxPercent / 100).round() : 0;
    final service = serviceEnabled ? (subtotal * servicePercent / 100).round() : 0;
    final discount = discountEnabled ? (subtotal * discountPercent / 100).round() : 0;
    final preRounding = subtotal + tax + service - discount;
    int rounding = 0;
    int grandTotal = preRounding;
    if (roundingEnabled && roundingNearest > 0) {
      final rounded = (preRounding / roundingNearest).round() * roundingNearest;
      rounding = rounded - preRounding;
      grandTotal = rounded;
    }
    return {
      'tax': tax,
      'service': service,
      'discount': discount,
      'rounding': rounding,
      'grandTotal': grandTotal,
    };
  }

  // ---- Transactions ----
  static Box<TransactionRecord> get transactions => Hive.box<TransactionRecord>(txBox);

  static Future<TransactionRecord> saveTransaction({
    required List<TxItem> items,
    required String paymentMethod,
    String? memberId,
    String status = 'paid',
    String? midtransOrderId,
    String salesType = 'Dine In',
    int taxAmount = 0,
    int serviceAmount = 0,
    int discountAmount = 0,
    int roundingAdjustment = 0,
    String? guestName,
  }) async {
    final subtotal = items.fold<int>(0, (sum, i) => sum + i.subtotal);
    final grandTotal = subtotal + taxAmount + serviceAmount - discountAmount + roundingAdjustment;
    final tx = TransactionRecord(
      id: _uuid.v4(),
      items: items,
      total: grandTotal,
      createdAt: DateTime.now(),
      memberId: memberId,
      paymentMethod: paymentMethod,
      status: status,
      midtransOrderId: midtransOrderId,
      salesType: salesType,
      taxAmount: taxAmount,
      serviceAmount: serviceAmount,
      discountAmount: discountAmount,
      roundingAdjustment: roundingAdjustment,
      guestName: guestName,
    );
    await transactions.put(tx.id, tx);

    if (status == 'paid') {
      for (final item in items) {
        await adjustStock(item.productId, -item.qty);
      }
    }

    if (memberId != null && status == 'paid') {
      final member = members.get(memberId);
      if (member != null) {
        member.points += Member.pointsFromAmount(grandTotal);
        await member.save();
      }
    }
    return tx;
  }

  // ---- Reports ----
  static int totalSalesToday() {
    final now = DateTime.now();
    return transactions.values
        .where((t) =>
            t.status == 'paid' &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month &&
            t.createdAt.day == now.day)
        .fold(0, (sum, t) => sum + t.total);
  }

  static Map<String, int> salesByProduct({DateTime? from, DateTime? to}) {
    final result = <String, int>{};
    for (final t in transactions.values.where((t) => t.status == 'paid')) {
      if (from != null && t.createdAt.isBefore(from)) continue;
      if (to != null && t.createdAt.isAfter(to)) continue;
      for (final item in t.items) {
        result[item.productName] = (result[item.productName] ?? 0) + item.qty;
      }
    }
    return result;
  }
}
DBEOF

cat > lib/screens/inventory_screen.dart << 'INVEOF'
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
    final nameCtrl = TextEditingController(text: p.name);
    final categoryCtrl = TextEditingController(text: p.category);
    final stockCtrl = TextEditingController(text: '${p.stock}');
    String? imageBase64 = p.imageBase64;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
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
                  TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategori', hintText: 'mis. Jamu, Minuman, Tambahan')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stok saat ini'),
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
                  await DbService.setProductCategory(p.id, categoryCtrl.text.trim().isEmpty ? p.category : categoryCtrl.text.trim());
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
    final categoryCtrl = TextEditingController(text: 'Jamu');
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    String? imageBase64;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
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
                  TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategori', hintText: 'mis. Jamu, Minuman, Tambahan')),
                  const SizedBox(height: 8),
                  TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)')),
                  const SizedBox(height: 8),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok awal')),
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
        category: categoryCtrl.text.trim().isEmpty ? 'Jamu' : categoryCtrl.text.trim(),
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
            subtitle: Text('${p.category} • ${_currency.format(p.price)}'),
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
INVEOF

cat > lib/screens/cashier_screen.dart << 'CASHIEREOF'
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';

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
  String? _guestName;
  String _salesType = 'Dine In';
  final _pageController = PageController();
  int _categoryIndex = 0;
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
    final guestController = TextEditingController(text: _guestName ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pelanggan', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CARI MEMBER (NO. HP)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                        const SnackBar(content: Text('Member tidak ditemukan. Daftarkan dulu di tab Member.')),
                      );
                      return;
                    }
                    setState(() {
                      _selectedMember = m;
                      _guestName = null;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cari'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('ATAU NAMA TAMU (NON-MEMBER)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: guestController,
                    decoration: const InputDecoration(hintText: 'Nama pelanggan', isDense: true),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
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
            title: const Text('Pilih Jenis Penjualan', style: TextStyle(color: _navy)),
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
                            labelText: 'Platform lain',
                            hintText: 'Isi manual',
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

  void _saveBillDraft() {
    if (_cart.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill disimpan sebagai draft (fitur simpan permanen menyusul)')),
    );
  }

  void _printBill() {
    if (_cart.isEmpty) return;
    final totals = _totals;
    final draftTx = TransactionRecord(
      id: 'draft',
      items: _cart
          .map((l) => TxItem(productId: l.product.id, productName: l.product.name, price: l.unitPrice, qty: l.qty, note: l.note))
          .toList(),
      total: totals['grandTotal']!,
      createdAt: DateTime.now(),
      memberId: _selectedMember?.id,
      paymentMethod: 'belum dibayar',
      salesType: _salesType,
      taxAmount: totals['tax']!,
      serviceAmount: totals['service']!,
      discountAmount: totals['discount']!,
      roundingAdjustment: totals['rounding']!,
      guestName: _guestName,
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

    final prefillPhone = _selectedMember?.phone ?? '';

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
    );

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
      _guestName = null;
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
                  const Center(child: Text('Pembayaran Berhasil!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: _navy))),
                  const SizedBox(height: 4),
                  Center(child: Text(currency.format(tx.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy))),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                    onPressed: () => _showReceiptDialog(tx),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Cetak / Lihat Struk'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Kirim struk via Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(hintText: 'email@contoh.com', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _navy),
                        onPressed: () {
                          if (emailCtrl.text.trim().isEmpty) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Struk akan dikirim ke ${emailCtrl.text.trim()} (perlu sambungkan layanan email di backend)')),
                          );
                        },
                        child: const Text('Kirim'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Kirim struk via SMS/WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
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
                            SnackBar(content: Text('Struk akan dikirim ke ${phoneCtrl.text.trim()} (perlu sambungkan layanan SMS/WA di backend)')),
                          );
                        },
                        child: const Text('Kirim'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _navy),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Selesai'),
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
    final categories = <String>[];
    for (final p in allProducts) {
      if (!categories.contains(p.category)) categories.add(p.category);
    }
    if (_categoryIndex >= categories.length) _categoryIndex = 0;
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
            child: Column(
              children: [
                if (categories.length > 1)
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: categories.length,
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
                              categories[i],
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
                    itemCount: categories.isEmpty ? 1 : categories.length,
                    onPageChanged: (i) => setState(() => _categoryIndex = i),
                    itemBuilder: (ctx, pageIndex) {
                      final category = categories.isEmpty ? null : categories[pageIndex];
                      final categoryProducts = category == null
                          ? <Product>[]
                          : allProducts.where((p) => p.category == category).toList();
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: ReorderableGridView.count(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              final moved = categoryProducts.removeAt(oldIndex);
                              categoryProducts.insert(newIndex, moved);
                            });
                            DbService.reorderCategory(categoryProducts.map((p) => p.id).toList());
                          },
                          children: [
                            for (final p in categoryProducts)
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
                            : (_guestName != null ? _guestName! : '+ Tambah Pelanggan'),
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
                        _totalRow('Tax', totals['tax']!),
                        _totalRow('Service', totals['service']!),
                        if (totals['discount']! > 0)
                          _totalRow(
                            DbService.discountPromoName.isNotEmpty ? 'Discount (${DbService.discountPromoName})' : 'Discount',
                            -totals['discount']!,
                          ),
                        _totalRow('Rounding', totals['rounding']!),
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
CASHIEREOF

echo 'Selesai. Sekarang jalankan:'
echo 'flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter run -d web-server --web-port 8080 --release'
