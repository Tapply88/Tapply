cat > lib/services/app_strings.dart << 'APPSTREOF'
import 'db_service.dart';

/// Dictionary terjemahan UI app (BUKAN nama menu/produk atau nama promo — itu tetap
/// apa adanya sesuai input user). Panggil AppStrings.t('key') buat ambil teks sesuai
/// bahasa yang aktif di Setelan.
class AppStrings {
  static const Map<String, Map<String, String>> _strings = {
    // Bottom nav
    'nav_kasir': {'id': 'Kasir', 'en': 'Cashier'},
    'nav_member': {'id': 'Member', 'en': 'Member'},
    'nav_inventory': {'id': 'Inventory', 'en': 'Inventory'},
    'nav_laporan': {'id': 'Laporan', 'en': 'Report'},
    'nav_setelan': {'id': 'Setelan', 'en': 'Settings'},
    // Shift gate
    'mulai_shift': {'id': 'Mulai Shift', 'en': 'Start Shift'},
    'nama_kasir': {'id': 'Nama Kasir', 'en': 'Cashier Name'},
    'email_kasir': {'id': 'Email Kasir', 'en': 'Cashier Email'},
    'modal_awal': {'id': 'Modal Awal (Rp)', 'en': 'Starting Cash'},
    // Cashier action buttons
    'save_bill': {'id': 'Save Bill', 'en': 'Save Bill'},
    'order_dapur': {'id': 'Order Dapur', 'en': 'Kitchen Order'},
    'print_check': {'id': 'Print Check', 'en': 'Print Check'},
    'charge': {'id': 'Charge', 'en': 'Charge'},
    'tambah_pelanggan': {'id': '+ Tambah Pelanggan', 'en': '+ Add Customer'},
    'item_custom': {'id': 'Item Custom', 'en': 'Custom Item'},
    // Settings
    'bahasa': {'id': 'Bahasa', 'en': 'Language'},
    'keamanan': {'id': 'Keamanan', 'en': 'Security'},
    'pin_manager': {'id': 'PIN Manager (buat cancel item)', 'en': 'Manager PIN (for canceling items)'},
    // Common actions
    'simpan': {'id': 'Simpan', 'en': 'Save'},
    'batal': {'id': 'Batal', 'en': 'Cancel'},
    'tutup': {'id': 'Tutup', 'en': 'Close'},
    'hapus': {'id': 'Hapus', 'en': 'Delete'},
    'cari': {'id': 'Cari', 'en': 'Search'},
  };

  static String t(String key) {
    final lang = DbService.language;
    return _strings[key]?[lang] ?? key;
  }
}
APPSTREOF

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
  static String get managerPin => settings.get('managerPin', defaultValue: '1234');
  static Future<void> setManagerPin(String pin) async => settings.put('managerPin', pin);
  static String get language => settings.get('language', defaultValue: 'id');
  static Future<void> setLanguage(String lang) async => settings.put('language', lang);

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

cat > lib/screens/settings_screen.dart << 'SETEOF'
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/db_service.dart';
import 'promo_screen.dart';
import 'variants_screen.dart';
import '../services/app_strings.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _pinCtrl;
  late String _language;
  String? _logoBase64;

  late bool _taxEnabled;
  late final TextEditingController _taxCtrl;
  late bool _serviceEnabled;
  late final TextEditingController _serviceCtrl;
  late bool _discountEnabled;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _promoNameCtrl;
  late bool _roundingEnabled;
  late int _roundingNearest;
  late bool _queueNumberEnabled;
  late final TextEditingController _queueStartCtrl;
  final _queueTodayCtrl = TextEditingController();
  late bool _showZeroAmountRows;
  late bool _printCheckEnabled;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: DbService.businessName);
    _addressCtrl = TextEditingController(text: DbService.businessAddress);
    _phoneCtrl = TextEditingController(text: DbService.businessPhone);
    _footerCtrl = TextEditingController(text: DbService.receiptFooterText);
    _pinCtrl = TextEditingController(text: DbService.managerPin);
    _language = DbService.language;
    _logoBase64 = DbService.businessLogoBase64;

    _taxEnabled = DbService.taxEnabled;
    _taxCtrl = TextEditingController(text: DbService.taxPercent.toStringAsFixed(1));
    _serviceEnabled = DbService.serviceEnabled;
    _serviceCtrl = TextEditingController(text: DbService.servicePercent.toStringAsFixed(1));
    _discountEnabled = DbService.discountEnabled;
    _discountCtrl = TextEditingController(text: DbService.discountPercent.toStringAsFixed(1));
    _promoNameCtrl = TextEditingController(text: DbService.discountPromoName);
    _roundingEnabled = DbService.roundingEnabled;
    _roundingNearest = DbService.roundingNearest;
    _queueNumberEnabled = DbService.queueNumberEnabled;
    _queueStartCtrl = TextEditingController(text: '${DbService.queueStartNumber}');
    _showZeroAmountRows = DbService.showZeroAmountRows;
    _printCheckEnabled = DbService.printCheckEnabled;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    await DbService.setBusinessLogo(b64);
    setState(() => _logoBase64 = b64);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo bisnis disimpan')));
  }

  Future<void> _removeLogo() async {
    await DbService.setBusinessLogo(null);
    setState(() => _logoBase64 = null);
  }

  Future<void> _saveBusinessProfile() async {
    await DbService.updateBusinessProfile(
      businessName: _nameCtrl.text.trim(),
      businessAddress: _addressCtrl.text.trim(),
      businessPhone: _phoneCtrl.text.trim(),
      receiptFooterText: _footerCtrl.text.trim().isEmpty ? 'Terima kasih!' : _footerCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil bisnis disimpan')));
  }

  Future<void> _saveTaxSettings() async {
    await DbService.updateSettings(
      taxEnabled: _taxEnabled,
      taxPercent: double.tryParse(_taxCtrl.text) ?? 0,
      serviceEnabled: _serviceEnabled,
      servicePercent: double.tryParse(_serviceCtrl.text) ?? 0,
      discountEnabled: _discountEnabled,
      discountPercent: double.tryParse(_discountCtrl.text) ?? 0,
      discountPromoName: _promoNameCtrl.text.trim(),
      roundingEnabled: _roundingEnabled,
      roundingNearest: _roundingNearest,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan total disimpan')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setelan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Profil Bisnis', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Muncul di bagian atas struk (logo, nama, alamat, no. telp).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: _navy, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  color: _grey.withValues(alpha: 0.3),
                ),
                child: _logoBase64 != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(base64Decode(_logoBase64!), fit: BoxFit.contain),
                      )
                    : const Icon(Icons.storefront, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                      onPressed: _pickLogo,
                      child: Text(_logoBase64 != null ? 'Ganti Logo' : 'Upload Logo Bisnis'),
                    ),
                    if (_logoBase64 != null)
                      TextButton(
                        onPressed: _removeLogo,
                        child: const Text('Hapus logo', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nama bisnis')),
          const SizedBox(height: 8),
          TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Alamat'), maxLines: 2),
          const SizedBox(height: 8),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'No. Telepon'), keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          TextField(controller: _footerCtrl, decoration: const InputDecoration(labelText: 'Teks penutup struk', hintText: 'Terima kasih!')),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: _saveBusinessProfile,
            child: const Text('Simpan Profil Bisnis'),
          ),
          const Divider(height: 40),
          const Text('Varian & Tambahan', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Atur pilihan varian (mis. Hangat/Dingin) dan tambahan (mis. Extra Madu) yang muncul di kasir, termasuk harganya.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VariantsScreen())),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Kelola Varian & Tambahan'),
          ),
          const Divider(height: 40),
          const Text('Promo', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Bikin promo dengan tanggal berlaku, jenis diskon (persen/nominal), dan minimum pembelian. '
            'Kalau ada promo yang valid saat checkout, itu dipakai otomatis (yang diskonnya paling besar kalau ada beberapa).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromoScreen())),
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Kelola Promo'),
          ),
          const Divider(height: 40),
          const Text('Tax, Service, Diskon Manual & Pembulatan', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Diskon manual di bawah ini dipakai kalau TIDAK ada promo bertanggal yang sedang valid.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Tax'),
            value: _taxEnabled,
            onChanged: (v) => setState(() => _taxEnabled = v),
          ),
          if (_taxEnabled)
            TextField(
              controller: _taxCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Persentase Tax (%)'),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Service Charge'),
            value: _serviceEnabled,
            onChanged: (v) => setState(() => _serviceEnabled = v),
          ),
          if (_serviceEnabled)
            TextField(
              controller: _serviceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Persentase Service (%)'),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Automatic Discount'),
            value: _discountEnabled,
            onChanged: (v) => setState(() => _discountEnabled = v),
          ),
          if (_discountEnabled) ...[
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount percentage (%)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promoNameCtrl,
              decoration: const InputDecoration(labelText: 'Promo name (optional)', hintText: 'e.g. Ramadan Promo'),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Total Rounding'),
            value: _roundingEnabled,
            onChanged: (v) => setState(() => _roundingEnabled = v),
          ),
          if (_roundingEnabled)
            DropdownButtonFormField<int>(
              initialValue: _roundingNearest,
              decoration: const InputDecoration(labelText: 'Round to nearest'),
              items: const [100, 500, 1000]
                  .map((v) => DropdownMenuItem(value: v, child: Text('Rp $v')))
                  .toList(),
              onChanged: (v) => setState(() => _roundingNearest = v ?? 100),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Nomor Antrian di Struk'),
            subtitle: const Text('Opsional — nomor urut harian di bagian paling atas struk', style: TextStyle(fontSize: 11)),
            value: _queueNumberEnabled,
            onChanged: (v) async {
              setState(() => _queueNumberEnabled = v);
              await DbService.setQueueNumberEnabled(v);
            },
          ),
          if (_queueNumberEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queueStartCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mulai dari (tiap hari baru)', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: () async {
                    final n = int.tryParse(_queueStartCtrl.text) ?? 1;
                    await DbService.setQueueStartNumber(n);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nomor mulai harian disimpan')));
                  },
                  child: const Text('Simpan'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queueTodayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Set nomor antrian HARI INI sekarang ke', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                  onPressed: () async {
                    final n = int.tryParse(_queueTodayCtrl.text);
                    if (n == null) return;
                    await DbService.resetQueueCounterToday(n);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nomor antrian berikutnya: $n')));
                  },
                  child: const Text('Terapkan'),
                ),
              ],
            ),
            const Text(
              'Bisa juga isi manual per transaksi (kode custom) langsung di kasir — gak harus angka urut.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Selalu Tampilkan Tax/Service/Rounding'),
            subtitle: const Text('Kalau dimatikan, baris itu disembunyikan waktu nilainya Rp0', style: TextStyle(fontSize: 11)),
            value: _showZeroAmountRows,
            onChanged: (v) async {
              setState(() => _showZeroAmountRows = v);
              await DbService.setShowZeroAmountRows(v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Tombol Print Check'),
            subtitle: const Text('Opsional — preview bill sebelum bayar (beda dari struk final setelah bayar)', style: TextStyle(fontSize: 11)),
            value: _printCheckEnabled,
            onChanged: (v) async {
              setState(() => _printCheckEnabled = v);
              await DbService.setPrintCheckEnabled(v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: _saveTaxSettings,
            child: const Text('Simpan Pengaturan Total'),
          ),
          const Divider(height: 40),
          Text(AppStrings.t('keamanan'), style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'PIN ini diminta setiap kali kasir mau cancel/hapus item dari keranjang.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: AppStrings.t('pin_manager')),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () async {
              await DbService.setManagerPin(_pinCtrl.text.trim().isEmpty ? '1234' : _pinCtrl.text.trim());
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN disimpan')));
            },
            child: const Text('Simpan PIN'),
          ),
          const Divider(height: 40),
          Text(AppStrings.t('bahasa'), style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Bahasa tampilan aplikasi. Nama menu/produk dan nama promo TIDAK ikut diterjemahkan '
            '(tetap sesuai yang kamu ketik). Fitur ini masih tahap awal — belum semua layar diterjemahkan.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _language == 'id' ? _navy : Colors.transparent,
                    foregroundColor: _language == 'id' ? Colors.white : _navy,
                    side: const BorderSide(color: _navy),
                  ),
                  onPressed: () async {
                    setState(() => _language = 'id');
                    await DbService.setLanguage('id');
                  },
                  child: const Text('Bahasa Indonesia'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _language == 'en' ? _navy : Colors.transparent,
                    foregroundColor: _language == 'en' ? Colors.white : _navy,
                    side: const BorderSide(color: _navy),
                  ),
                  onPressed: () async {
                    setState(() => _language = 'en');
                    await DbService.setLanguage('en');
                  },
                  child: const Text('English'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
SETEOF

cat > lib/screens/home_screen.dart << 'HOMEEOF'
import 'package:flutter/material.dart';
import 'cashier_screen.dart';
import 'membership_screen.dart';
import 'report_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';
import '../services/db_service.dart';
import '../services/app_strings.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [
    CashierScreen(),
    MembershipScreen(),
    InventoryScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  Future<void> _openStartShiftForm() async {
    final nameCtrl = TextEditingController(text: DbService.currentCashierName);
    final emailCtrl = TextEditingController(text: DbService.currentCashierEmail);
    final cashCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('mulai_shift'), style: const TextStyle(color: _navy)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('nama_kasir'))),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: InputDecoration(labelText: AppStrings.t('email_kasir')), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 8),
              TextField(
                controller: cashCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: AppStrings.t('modal_awal')),
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
            child: Text(AppStrings.t('mulai_shift')),
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
                  child: Text(AppStrings.t('mulai_shift'), style: const TextStyle(fontSize: 16)),
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.point_of_sale), label: AppStrings.t('nav_kasir')),
          NavigationDestination(icon: const Icon(Icons.card_membership), label: AppStrings.t('nav_member')),
          NavigationDestination(icon: const Icon(Icons.inventory_2), label: AppStrings.t('nav_inventory')),
          NavigationDestination(icon: const Icon(Icons.bar_chart), label: AppStrings.t('nav_laporan')),
          NavigationDestination(icon: const Icon(Icons.settings), label: AppStrings.t('nav_setelan')),
        ],
      ),
    );
  }
}
HOMEEOF

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
import '../services/app_strings.dart';

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

  Future<void> _addCustomItem() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Item Custom', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Buat item yang gak ada di menu, mis. biaya jasa, item pesanan khusus, dll.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama item')),
            const SizedBox(height: 8),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)')),
            const SizedBox(height: 8),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tambah'),
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
          const SnackBar(content: Text('Isi nama, harga, dan jumlah yang valid dulu')),
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
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Cancel', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Masukkan PIN buat cancel "${line.product.name}"'),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (pinCtrl.text == DbService.managerPin) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('PIN salah')));
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
              child: IconButton(
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add_shopping_cart, color: _navy),
                tooltip: AppStrings.t('item_custom'),
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
                            : (_guestName != null ? _guestName! : AppStrings.t('tambah_pelanggan')),
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
                                      tooltip: 'Cancel item (perlu PIN)',
                                      onPressed: () => _confirmRemoveLine(l),
                                    ),
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
                            child: Text(AppStrings.t('save_bill'), style: const TextStyle(color: _navy, fontSize: 12)),
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
                            child: Text(AppStrings.t('order_dapur'), style: const TextStyle(color: _navy, fontSize: 12)),
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
                              child: Text(AppStrings.t('print_check'), style: const TextStyle(color: _navy, fontSize: 12)),
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
                        '${AppStrings.t('charge')} ${_currency.format(_grandTotal)}',
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

echo 'Selesai. Jalankan: flutter clean && flutter pub get && flutter run -d web-server --web-port 8080 --release'
