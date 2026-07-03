cat > lib/models/shift.dart << 'SHIFTEOF'
import 'package:hive/hive.dart';

part 'shift.g.dart';

@HiveType(typeId: 7)
class Shift extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String cashierName;

  @HiveField(2)
  String cashierEmail;

  @HiveField(3)
  DateTime startTime;

  @HiveField(4)
  int startingCash;

  @HiveField(5)
  DateTime? endTime;

  @HiveField(6)
  int? endingCashCounted;

  @HiveField(7)
  String status; // 'open' or 'closed'

  @HiveField(8)
  String? note;

  Shift({
    required this.id,
    required this.cashierName,
    required this.cashierEmail,
    required this.startTime,
    required this.startingCash,
    this.endTime,
    this.endingCashCounted,
    this.status = 'open',
    this.note,
  });
}
SHIFTEOF

cat > lib/services/db_service.dart << 'DBEOF'
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../models/promo.dart';
import '../models/variation.dart';
import '../models/addon.dart';
import '../models/shift.dart';

class DbService {
  static const productBox = 'products';
  static const memberBox = 'members';
  static const txBox = 'transactions';
  static const settingsBox = 'settings';
  static const promoBox = 'promos';
  static const variationBox = 'variations';
  static const addonBox = 'addons';
  static const shiftBox = 'shifts';
  static final _uuid = const Uuid();

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(MemberAdapter());
    Hive.registerAdapter(TxItemAdapter());
    Hive.registerAdapter(TransactionRecordAdapter());
    Hive.registerAdapter(PromoAdapter());
    Hive.registerAdapter(VariationAdapter());
    Hive.registerAdapter(AddonAdapter());
    Hive.registerAdapter(ShiftAdapter());

    await Hive.openBox<Product>(productBox);
    await Hive.openBox<Member>(memberBox);
    await Hive.openBox<TransactionRecord>(txBox);
    await Hive.openBox(settingsBox);
    await Hive.openBox<Promo>(promoBox);
    await Hive.openBox<Variation>(variationBox);
    await Hive.openBox<Addon>(addonBox);
    await Hive.openBox<Shift>(shiftBox);

    await _seedProductsIfEmpty();
    await _seedVariantsIfEmpty();
  }

  static Future<void> _seedVariantsIfEmpty() async {
    if (variations.isEmpty) {
      await addVariation('Hangat');
      await addVariation('Dingin');
    }
    if (addons.isEmpty) {
      await addAddon(name: 'Extra Madu', price: 3000);
      await addAddon(name: 'Extra Jahe', price: 2000);
      await addAddon(name: 'Kurang Gula', price: 0);
    }
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

  // ---- Categories (managed list, chosen when adding/editing products) ----
  static List<String> get categories {
    final stored = settings.get('categories', defaultValue: <String>['Jamu']);
    return List<String>.from(stored);
  }

  static Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = categories;
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await settings.put('categories', list);
    }
  }

  /// Simpan urutan baru untuk SEMUA produk (dipakai saat drag-reorder di halaman "Semua").
  static Future<void> reorderAll(List<String> orderedProductIds) async {
    for (var i = 0; i < orderedProductIds.length; i++) {
      final p = products.get(orderedProductIds[i]);
      if (p != null) {
        p.sortOrder = i;
        await p.save();
      }
    }
  }

  /// Simpan urutan baru untuk produk DALAM satu kategori saja, tanpa mengacak
  /// posisi produk kategori lain di urutan global.
  static Future<void> reorderWithinCategory(String category, List<String> newCategoryOrderIds) async {
    final all = products.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final positions = <int>[];
    for (var i = 0; i < all.length; i++) {
      if (all[i].category == category) positions.add(i);
    }
    final byId = {for (final p in all) p.id: p};
    for (var i = 0; i < positions.length && i < newCategoryOrderIds.length; i++) {
      final replacement = byId[newCategoryOrderIds[i]];
      if (replacement != null) all[positions[i]] = replacement;
    }
    for (var i = 0; i < all.length; i++) {
      all[i].sortOrder = i;
      await all[i].save();
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
  static bool get showZeroAmountRows => settings.get('showZeroAmountRows', defaultValue: false);
  static Future<void> setShowZeroAmountRows(bool v) async => settings.put('showZeroAmountRows', v);
  static bool get printCheckEnabled => settings.get('printCheckEnabled', defaultValue: true);
  static Future<void> setPrintCheckEnabled(bool v) async => settings.put('printCheckEnabled', v);

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

  /// Hitung rincian total dari subtotal item + diskon yang SUDAH ditentukan (bukan nebak sendiri).
  static Map<String, int> computeTotals(int subtotal, {int discountAmount = 0}) {
    final tax = taxEnabled ? (subtotal * taxPercent / 100).round() : 0;
    final service = serviceEnabled ? (subtotal * servicePercent / 100).round() : 0;
    final preRounding = subtotal + tax + service - discountAmount;
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
      'discount': discountAmount,
      'rounding': rounding,
      'grandTotal': grandTotal,
    };
  }

  // ---- Promos ----
  static Box<Promo> get promos => Hive.box<Promo>(promoBox);

  static Future<void> savePromo(Promo promo) async {
    await promos.put(promo.id, promo);
  }

  static Future<void> deletePromo(String promoId) async {
    await promos.delete(promoId);
  }

  static int promoDiscountAmount(Promo p, {required int cartSubtotal, Map<String, int>? productSubtotals, Map<String, int>? productQuantities}) {
    if (p.scope == 'product') {
      if (p.discountType == 'fixed') {
        final eligibleQty = p.productIds.fold<int>(0, (s, id) => s + (productQuantities?[id] ?? 0));
        return (p.value * eligibleQty).round();
      }
      final eligible = p.productIds.fold<int>(0, (s, id) => s + (productSubtotals?[id] ?? 0));
      return (eligible * p.value / 100).round();
    }
    return p.discountType == 'percentage' ? (cartSubtotal * p.value / 100).round() : p.value.round();
  }

  /// Semua promo yang aktif, dalam rentang tanggal, dan memenuhi minimum pembelian
  /// (dicek terhadap subtotal seluruh struk, atau subtotal produk terkait kalau scope
  /// promonya per-produk) — dipakai buat nampilin pilihan ke kasir.
  static List<Promo> validPromosFor({required int cartSubtotal, Map<String, int>? productSubtotals}) {
    final now = DateTime.now();
    return promos.values.where((p) {
      if (!p.active) return false;
      if (p.startDate != null && now.isBefore(p.startDate!)) return false;
      if (p.endDate != null && now.isAfter(p.endDate!)) return false;
      if (p.scope == 'product') {
        final eligible = p.productIds.fold<int>(0, (s, id) => s + (productSubtotals?[id] ?? 0));
        if (eligible <= 0) return false;
        if (eligible < p.minPurchase) return false;
      } else {
        if (cartSubtotal < p.minPurchase) return false;
      }
      return true;
    }).toList();
  }

  // ---- Variations & Add-ons (bisa diedit, bukan hardcode) ----
  static Box<Variation> get variationsBox => Hive.box<Variation>(variationBox);
  static Box<Addon> get addonsBox => Hive.box<Addon>(addonBox);

  static List<Variation> get variations => variationsBox.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  static List<Addon> get addons => addonsBox.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  static Future<void> addVariation(String name) async {
    final maxOrder = variationsBox.values.isEmpty ? 0 : variationsBox.values.map((v) => v.sortOrder).reduce((a, b) => a > b ? a : b);
    final v = Variation(id: _uuid.v4(), name: name, sortOrder: maxOrder + 1);
    await variationsBox.put(v.id, v);
  }

  static Future<void> updateVariation(String id, String name) async {
    final v = variationsBox.get(id);
    if (v == null) return;
    v.name = name;
    await v.save();
  }

  static Future<void> deleteVariation(String id) async => variationsBox.delete(id);

  static Future<void> addAddon({required String name, required int price}) async {
    final maxOrder = addonsBox.values.isEmpty ? 0 : addonsBox.values.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b);
    final a = Addon(id: _uuid.v4(), name: name, price: price, sortOrder: maxOrder + 1);
    await addonsBox.put(a.id, a);
  }

  static Future<void> updateAddon(String id, {required String name, required int price}) async {
    final a = addonsBox.get(id);
    if (a == null) return;
    a.name = name;
    a.price = price;
    await a.save();
  }

  static Future<void> deleteAddon(String id) async => addonsBox.delete(id);

  // ---- Cashier session (versi sederhana, per-device) ----
  static String get currentCashierName => settings.get('currentCashierName', defaultValue: '');
  static String get currentCashierEmail => settings.get('currentCashierEmail', defaultValue: '');

  static Future<void> setCurrentCashier({required String name, required String email}) async {
    await settings.put('currentCashierName', name);
    await settings.put('currentCashierEmail', email);
  }

  // ---- Shift (modal awal, end shift, settlement) ----
  static Box<Shift> get shifts => Hive.box<Shift>(shiftBox);

  static Shift? get currentOpenShift {
    try {
      return shifts.values.firstWhere((s) => s.status == 'open');
    } catch (_) {
      return null;
    }
  }

  static List<Shift> get shiftHistory => shifts.values.toList()..sort((a, b) => b.startTime.compareTo(a.startTime));

  static Future<Shift> startShift({required int startingCash}) async {
    final shift = Shift(
      id: _uuid.v4(),
      cashierName: currentCashierName,
      cashierEmail: currentCashierEmail,
      startTime: DateTime.now(),
      startingCash: startingCash,
    );
    await shifts.put(shift.id, shift);
    return shift;
  }

  static Future<void> endShift({required int endingCashCounted, String? note}) async {
    final shift = currentOpenShift;
    if (shift == null) return;
    shift.endTime = DateTime.now();
    shift.endingCashCounted = endingCashCounted;
    shift.status = 'closed';
    shift.note = note;
    await shift.save();
  }

  /// Rincian penjualan (per metode bayar) selama shift berjalan (dari startTime s/d sekarang atau endTime).
  static Map<String, int> salesDuringShift(Shift shift) {
    final to = shift.endTime ?? DateTime.now();
    return salesByPaymentMethod(from: shift.startTime, to: to);
  }

  /// Total cash yang seharusnya ada di laci: modal awal + total penjualan cash selama shift.
  static int expectedCashForShift(Shift shift) {
    final bySales = salesDuringShift(shift);
    final cashSales = bySales['cash'] ?? 0;
    return shift.startingCash + cashSales;
  }

  // ---- Receipt & queue numbering ----
  static bool get queueNumberEnabled => settings.get('queueNumberEnabled', defaultValue: false);
  static Future<void> setQueueNumberEnabled(bool enabled) async => settings.put('queueNumberEnabled', enabled);

  /// Nomor mulai buat antrian tiap hari (dipakai pas tanggal berganti / hari baru).
  static int get queueStartNumber => settings.get('queueStartNumber', defaultValue: 1);
  static Future<void> setQueueStartNumber(int n) async => settings.put('queueStartNumber', n);

  /// Paksa nomor antrian HARI INI mulai/lanjut dari angka tertentu sekarang juga.
  static Future<void> resetQueueCounterToday(int nextNumber) async {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    await settings.put('queueDate', todayKey);
    await settings.put('queueCounter', nextNumber - 1);
  }

  static String _nextReceiptNumber() {
    final next = (settings.get('receiptCounter', defaultValue: 0) as int) + 1;
    settings.put('receiptCounter', next);
    return 'TPL-${next.toString().padLeft(6, '0')}';
  }

  static String _nextQueueCode() {
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    final storedDate = settings.get('queueDate', defaultValue: '');
    int counter = settings.get('queueCounter', defaultValue: 0);
    if (storedDate != todayKey) {
      counter = queueStartNumber - 1;
      settings.put('queueDate', todayKey);
    }
    counter += 1;
    settings.put('queueCounter', counter);
    return '$counter';
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
    String? discountLabel,
    String? manualQueueCode,
  }) async {
    final subtotal = items.fold<int>(0, (sum, i) => sum + i.subtotal);
    final grandTotal = subtotal + taxAmount + serviceAmount - discountAmount + roundingAdjustment;
    String? queueCode;
    if (manualQueueCode != null && manualQueueCode.trim().isNotEmpty) {
      queueCode = manualQueueCode.trim();
    } else if (queueNumberEnabled) {
      queueCode = _nextQueueCode();
    }
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
      discountLabel: discountLabel,
      receiptNumber: _nextReceiptNumber(),
      cashierName: currentCashierName.isEmpty ? null : currentCashierName,
      cashierEmail: currentCashierEmail.isEmpty ? null : currentCashierEmail,
      queueCode: queueCode,
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

  static Map<String, int> salesByPaymentMethod({DateTime? from, DateTime? to}) {
    final result = <String, int>{};
    for (final t in transactions.values.where((t) => t.status == 'paid')) {
      if (from != null && t.createdAt.isBefore(from)) continue;
      if (to != null && t.createdAt.isAfter(to)) continue;
      result[t.paymentMethod] = (result[t.paymentMethod] ?? 0) + t.total;
    }
    return result;
  }
}
DBEOF

cat > lib/screens/shift_screen.dart << 'SHIFTSCREOF'
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
        title: const Text('Mulai Shift', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kasir: ${DbService.currentCashierName.isEmpty ? "(belum diisi)" : DbService.currentCashierName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Modal Awal (Rp)'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai Shift'),
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
            title: const Text('Akhiri Shift & Settlement', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Modal Awal', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  const Divider(),
                  _summaryRow('Cash Seharusnya di Laci', expected, bold: true),
                  const SizedBox(height: 12),
                  TextField(
                    controller: countedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cash Aktual Dihitung (Rp)'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      diff == 0
                          ? 'Pas! Gak ada selisih.'
                          : diff > 0
                              ? 'Lebih Rp${_currency.format(diff).replaceFirst("Rp ", "")}'
                              : 'Kurang Rp${_currency.format(diff.abs()).replaceFirst("Rp ", "")}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: counted == null
                    ? null
                    : () async {
                        await DbService.endShift(endingCashCounted: counted, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
                child: const Text('Tutup Shift'),
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
                  Text(shift.cashierName.isEmpty ? 'Kasir' : shift.cashierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                  Text('Mulai: ${_dateFmt.format(shift.startTime)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (shift.endTime != null) Text('Selesai: ${_dateFmt.format(shift.endTime!)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  _summaryRow('Modal Awal', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  if (expected != null) ...[
                    const Divider(),
                    _summaryRow('Cash Seharusnya', expected, bold: true),
                    _summaryRow('Cash Dihitung', shift.endingCashCounted ?? 0, bold: true),
                    _summaryRow('Selisih', (shift.endingCashCounted ?? 0) - expected, bold: true),
                  ],
                  if (shift.note != null && shift.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Catatan: ${shift.note}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
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
                    const Text('Belum ada shift aktif', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                    const SizedBox(height: 8),
                    const Text('Mulai shift buat catat modal awal dan settlement nanti.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: _startShift,
                      child: const Text('Mulai Shift'),
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
                        const Text('Shift Aktif', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Kasir: ${open.cashierName.isEmpty ? "-" : open.cashierName}', style: const TextStyle(fontSize: 13)),
                    Text('Mulai: ${_dateFmt.format(open.startTime)}', style: const TextStyle(fontSize: 13)),
                    Text('Modal Awal: ${_currency.format(open.startingCash)}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    const Text('Penjualan berjalan:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                    ...DbService.salesDuringShift(open).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: () => _endShift(open),
                      child: const Text('Akhiri Shift & Settlement'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Riwayat Shift', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text('Belum ada shift yang selesai.', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ...history.map((s) {
              final expected = DbService.expectedCashForShift(s);
              final diff = (s.endingCashCounted ?? 0) - expected;
              return ListTile(
                dense: true,
                onTap: () => _viewShiftDetail(s),
                title: Text('${s.cashierName.isEmpty ? "Kasir" : s.cashierName} • ${_dateFmt.format(s.startTime)}'),
                subtitle: Text(diff == 0 ? 'Pas' : (diff > 0 ? 'Lebih ${_currency.format(diff)}' : 'Kurang ${_currency.format(diff.abs())}')),
                trailing: Icon(Icons.circle, size: 10, color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red)),
              );
            }),
        ],
      ),
    );
  }
}
SHIFTSCREOF

cat > lib/screens/cashier_screen.dart << 'CASHIEREOF'
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../models/promo.dart';
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
  String? _chosenPromoId;
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _customCashController = TextEditingController();
  final _manualQueueCodeController = TextEditingController();

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
        title: const Text('Siapa yang jaga kasir?', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nama & email ini muncul di struk sebagai "Dilayani oleh". Versi sederhana — belum tersambung ke login berbasis akun di dashboard web.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir')),
            const SizedBox(height: 8),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Kasir'), keyboardType: TextInputType.emailAddress),
          ],
        ),
        actions: [
          if (DbService.currentCashierName.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await DbService.setCurrentCashier(name: nameCtrl.text.trim(), email: emailCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('Simpan'),
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
            title: const Text('Pilih Promo', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tanpa Promo'),
                    value: 'NONE',
                    groupValue: temp,
                    onChanged: (v) => setDialogState(() => temp = v),
                  ),
                  ...valid.map((p) {
                    final subtitleText = p.scope == 'item'
                        ? '${p.discountType == 'fixed' ? '-${_currency.format(p.value.round())}' : '-${p.value.toStringAsFixed(0)}%'} per item • dicentang saat tambah produk'
                        : '-${_currency.format(DbService.promoDiscountAmount(p, cartSubtotal: _subtotal, productSubtotals: _productSubtotals, productQuantities: _productQuantities))}${p.scope == 'product' ? ' • produk tertentu' : ''}';
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
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
                    if (availableVariations.isNotEmpty) ...[
                      const Text('VARIAN | PILIH SATU', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                      const Text('TAMBAHAN | BOLEH LEBIH DARI SATU', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
      paymentMethod: 'belum dibayar',
      salesType: _salesType,
      taxAmount: totals['tax']!,
      serviceAmount: totals['service']!,
      discountAmount: totals['discount']!,
      roundingAdjustment: totals['rounding']!,
      guestName: _guestName,
      discountLabel: _discountLabel,
      queueCode: _manualQueueCodeController.text.trim().isEmpty ? null : _manualQueueCodeController.text.trim(),
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
                        const Text('ORDER DAPUR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navy, letterSpacing: 1)),
                        Text(DbService.businessName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(_salesType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
                  if (_selectedMember != null)
                    Text('Pelanggan: ${_selectedMember!.name}', style: const TextStyle(fontSize: 12, color: Colors.grey))
                  else if (_guestName != null)
                    Text('Pelanggan: $_guestName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                  const Center(child: Text('— Untuk Dapur, bukan struk pelanggan —', style: TextStyle(fontSize: 10, color: Colors.grey))),
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
              note: _lineDiscountNote(l) != null ? '${l.note} • ${_lineDiscountNote(l)}' : l.note,
            ))
        .toList();

    final prefillPhone = _selectedMember?.phone ?? '';
    final discountLabel = _discountLabel;
    final manualQueueCode = _manualQueueCodeController.text.trim();

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
      manualQueueCode: manualQueueCode.isEmpty ? null : manualQueueCode,
    );

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _selectedMember = null;
      _guestName = null;
      _chosenPromoId = null;
      _manualQueueCodeController.clear();
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
    _manualQueueCodeController.dispose();
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
                          openShift != null ? 'Shift Aktif' : 'Mulai Shift',
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
                        DbService.currentCashierName.isEmpty ? 'Set Kasir' : DbService.currentCashierName,
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
                              pages[i] ?? 'Semua',
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
                  if (DbService.validPromosFor(cartSubtotal: _subtotal, productSubtotals: _productSubtotals).isNotEmpty) _buildPromoBanner(),
                  if (DbService.queueNumberEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        controller: _manualQueueCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Kode antrian (opsional)',
                          hintText: 'Kosongkan buat otomatis, atau isi manual',
                          isDense: true,
                        ),
                      ),
                    ),
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
                            child: const Text('Save Bill', style: TextStyle(color: _navy, fontSize: 12)),
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
                            child: const Text('Order Dapur', style: TextStyle(color: _navy, fontSize: 12)),
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
                              child: const Text('Print Check', style: TextStyle(color: _navy, fontSize: 12)),
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
                    ? 'Promo: ${resolved.label}${resolved.promo!.scope == 'item' ? ' (centang per produk saat ditambah)' : ''}'
                    : (pending ? '${valid.length} promo tersedia — pilih salah satu' : 'Tanpa promo'),
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

echo 'Selesai. Sekarang jalankan:'
echo 'flutter clean && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter run -d web-server --web-port 8080 --release'
