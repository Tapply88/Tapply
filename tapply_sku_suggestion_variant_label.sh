cat > lib/services/db_service.dart << 'DBEOF'
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/member.dart';
import '../models/transaction.dart';
import '../models/promo.dart';
import '../models/variation.dart';
import '../models/addon.dart';
import '../models/shift.dart';
import '../models/held_bill.dart';

class DbService {
  static const productBox = 'products';
  static const memberBox = 'members';
  static const txBox = 'transactions';
  static const settingsBox = 'settings';
  static const promoBox = 'promos';
  static const variationBox = 'variations';
  static const addonBox = 'addons';
  static const shiftBox = 'shifts';
  static const syncQueueBox = 'syncQueue';
  static const heldBillBox = 'heldBills';
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
    Hive.registerAdapter(HeldBillItemAdapter());
    Hive.registerAdapter(HeldBillAdapter());

    await Hive.openBox<Product>(productBox);
    await Hive.openBox<Member>(memberBox);
    await Hive.openBox<TransactionRecord>(txBox);
    await Hive.openBox(settingsBox);
    await Hive.openBox<Promo>(promoBox);
    await Hive.openBox<Variation>(variationBox);
    await Hive.openBox<Addon>(addonBox);
    await Hive.openBox<Shift>(shiftBox);
    await Hive.openBox<HeldBill>(heldBillBox);
    await Hive.openBox(syncQueueBox);

    await _seedProductsIfEmpty();
    await _seedVariantsIfEmpty();

    // Coba kirim ulang antrian sync yang gagal sebelumnya (misal pas offline).
    // Fire-and-forget — gak nunggu, biar app tetep cepet kebuka.
    retryPendingSyncs();
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
    _pushProductToCloud(p);
  }

  static Future<void> addProduct({
    required String name,
    required int price,
    required String category,
    int stock = 0,
    String? imageBase64,
    String? sku,
    DateTime? expiryDate,
    String? volume,
    DateTime? productionDate,
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
      sku: (sku == null || sku.trim().isEmpty) ? _nextSku() : sku.trim(),
      expiryDate: expiryDate,
      volume: volume,
      productionDate: productionDate,
    );
    await products.put(p.id, p);
    _pushProductToCloud(p);
  }

  static String _nextSku() {
    final next = (settings.get('skuCounter', defaultValue: 0) as int) + 1;
    settings.put('skuCounter', next);
    return 'SKU-${next.toString().padLeft(5, '0')}';
  }

  /// Saran SKU berdasarkan nama produk, mis. "Kunyit Asam" -> "KA-001".
  /// Otomatis nambah angka kalau kode itu udah kepake produk lain.
  static String suggestSkuForName(String name) {
    final cleaned = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z ]'), '');
    final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
    String prefix;
    if (words.length >= 2) {
      prefix = words.take(2).map((w) => w.substring(0, 1)).join();
    } else if (words.isNotEmpty) {
      prefix = words.first.substring(0, words.first.length < 3 ? words.first.length : 3);
    } else {
      prefix = 'PRD';
    }
    final existingSkus = products.values.map((p) => p.sku).toSet();
    int n = 1;
    String candidate = '$prefix-${n.toString().padLeft(3, '0')}';
    while (existingSkus.contains(candidate)) {
      n++;
      candidate = '$prefix-${n.toString().padLeft(3, '0')}';
    }
    return candidate;
  }

  static Future<void> setProductSku(String productId, String sku) async {
    final p = products.get(productId);
    if (p == null) return;
    p.sku = sku.trim().isEmpty ? _nextSku() : sku.trim();
    await p.save();
    _pushProductToCloud(p);
  }

  static Future<void> setProductExpiry(String productId, DateTime? expiryDate) async {
    final p = products.get(productId);
    if (p == null) return;
    p.expiryDate = expiryDate;
    await p.save();
    _pushProductToCloud(p);
  }

  static Future<void> setProductVolume(String productId, String? volume) async {
    final p = products.get(productId);
    if (p == null) return;
    p.volume = volume;
    await p.save();
    _pushProductToCloud(p);
  }

  static Future<void> setProductProductionDate(String productId, DateTime? productionDate) async {
    final p = products.get(productId);
    if (p == null) return;
    p.productionDate = productionDate;
    await p.save();
    _pushProductToCloud(p);
  }

  static Future<void> setProductCategory(String productId, String category) async {
    final p = products.get(productId);
    if (p == null) return;
    p.category = category;
    await p.save();
    _pushProductToCloud(p);
  }

  static Future<void> setProductName(String productId, String name) async {
    final p = products.get(productId);
    if (p == null) return;
    p.name = name;
    await p.save();
    _pushProductToCloud(p);
  }

  /// Kirim satu produk ke dashboard web (satu arah, best-effort). Foto produk
  /// (imageBase64) SENGAJA gak dikirim — kebesaran buat sync ringan kayak gini,
  /// itu butuh sistem upload gambar terpisah (belum ada di versi ini).
  static Future<void> _pushProductToCloud(Product p) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {
      'id': p.id,
      'name': p.name,
      'price': p.price,
      'category': p.category,
      'stock': p.stock,
      'sortOrder': p.sortOrder,
      'isActive': p.isActive,
    };
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/product'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/product', payload);
    } catch (_) {
      await _queueForRetry('/sync/product', payload);
    }
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
        _pushProductToCloud(p);
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
      _pushProductToCloud(all[i]);
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

  static Future<void> saveMember(Member m) async {
    await members.put(m.id, m);
    _pushMemberToCloud(m);
  }

  static Future<void> _pushMemberToCloud(Member m) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {
      'id': m.id,
      'name': m.name,
      'phone': m.phone,
      'points': m.points,
    };
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/member'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/member', payload);
    } catch (_) {
      await _queueForRetry('/sync/member', payload);
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
  static bool get pinRequiredForCancel => settings.get('pinRequiredForCancel', defaultValue: true);
  static Future<void> setPinRequiredForCancel(bool v) async => settings.put('pinRequiredForCancel', v);
  static String get language => settings.get('language', defaultValue: 'id');
  static Future<void> setLanguage(String lang) async => settings.put('language', lang);

  // ---- Sinkronisasi ke dashboard web (satu arah: app -> cloud) ----
  static bool get syncEnabled => settings.get('syncEnabled', defaultValue: false);
  static Future<void> setSyncEnabled(bool v) async => settings.put('syncEnabled', v);
  static String get syncServerUrl => settings.get('syncServerUrl', defaultValue: '');
  static Future<void> setSyncServerUrl(String url) async => settings.put('syncServerUrl', url);
  static String get syncApiKey => settings.get('syncApiKey', defaultValue: '');
  static Future<void> setSyncApiKey(String key) async => settings.put('syncApiKey', key);

  // ---- Antrian retry buat sync yang gagal (misal pas offline) ----
  static Box get syncQueue => Hive.box(syncQueueBox);
  static int get pendingSyncCount => syncQueue.length;

  static Future<void> _queueForRetry(String endpoint, Map<String, dynamic> payload) async {
    final key = _uuid.v4();
    await syncQueue.put(key, jsonEncode({'endpoint': endpoint, 'payload': payload}));
  }

  /// Coba kirim ulang semua yang ada di antrian. Yang berhasil langsung dibuang
  /// dari antrian; yang masih gagal (masih offline, dll) dibiarin buat dicoba
  /// lagi lain kali. Return jumlah yang berhasil dikirim.
  static Future<int> retryPendingSyncs() async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return 0;
    int successCount = 0;
    final keys = syncQueue.keys.toList();
    for (final key in keys) {
      try {
        final raw = syncQueue.get(key);
        if (raw == null) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final endpoint = decoded['endpoint'] as String;
        final payload = decoded['payload'] as Map<String, dynamic>;

        final response = await http
            .post(
              Uri.parse('$syncServerUrl$endpoint'),
              headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          await syncQueue.delete(key);
          successCount++;
        }
      } catch (_) {
        // Masih gagal (kemungkinan masih offline) — biarin di antrian, coba lagi lain kali.
      }
    }
    return successCount;
  }

  /// Kirim satu transaksi ke dashboard web. Gak nge-block, gak nge-throw —
  /// kalau lagi offline atau server-nya mati, transaksi tetap aman di Hive
  /// lokal, cuma gak ke-push ke cloud (belum ada retry queue di versi ini).
  static Future<void> _pushTransactionToCloud(TransactionRecord tx) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {
      'items': tx.items
          .map((i) => {
                'productId': i.productId,
                'productName': i.productName,
                'price': i.price,
                'qty': i.qty,
                'note': i.note,
              })
          .toList(),
      'total': tx.total,
      'taxAmount': tx.taxAmount,
      'serviceAmount': tx.serviceAmount,
      'discountAmount': tx.discountAmount,
      'discountLabel': tx.discountLabel,
      'roundingAdjustment': tx.roundingAdjustment,
      'paymentMethod': tx.paymentMethod,
      'salesType': tx.salesType,
      'guestName': tx.guestName,
      'cashierName': tx.cashierName,
      'cashierEmail': tx.cashierEmail,
      'receiptNumber': tx.receiptNumber,
      'queueCode': tx.queueCode,
      'status': tx.status,
      'createdAt': tx.createdAt.toIso8601String(),
    };
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/transaction'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': syncApiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/transaction', payload);
    } catch (_) {
      // Offline itu hal normal buat POS — antre dulu, gak boleh gagalin transaksi kasir.
      await _queueForRetry('/sync/transaction', payload);
    }
  }

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
    _pushPromoToCloud(promo);
  }

  static Future<void> _pushPromoToCloud(Promo p) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {
      'id': p.id,
      'name': p.name,
      'discountType': p.discountType,
      'value': p.value,
      'scope': p.scope,
      'productIds': p.productIds,
      'startDate': p.startDate?.toIso8601String(),
      'endDate': p.endDate?.toIso8601String(),
      'minPurchase': p.minPurchase,
      'active': p.active,
    };
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/promo'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/promo', payload);
    } catch (_) {
      await _queueForRetry('/sync/promo', payload);
    }
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

  // ---- Bill Tersimpan (buat dine-in yang belum bayar, disimpan dulu) ----
  static Box<HeldBill> get heldBills => Hive.box<HeldBill>(heldBillBox);

  static Future<void> saveHeldBill(HeldBill bill) async {
    await heldBills.put(bill.id, bill);
  }

  static Future<void> deleteHeldBill(String id) async {
    await heldBills.delete(id);
  }

  static List<HeldBill> get heldBillsSorted =>
      heldBills.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
    _pushShiftToCloud(shift);
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
    _pushShiftToCloud(shift);
  }

  static Future<void> _pushShiftToCloud(Shift s) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {
      'id': s.id,
      'cashierName': s.cashierName,
      'cashierEmail': s.cashierEmail,
      'startTime': s.startTime.toIso8601String(),
      'startingCash': s.startingCash,
      'endTime': s.endTime?.toIso8601String(),
      'endingCashCounted': s.endingCashCounted,
      'status': s.status,
      'note': s.note,
    };
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/shift'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/shift', payload);
    } catch (_) {
      await _queueForRetry('/sync/shift', payload);
    }
  }

  /// Tarik data terbaru dari dashboard web (Produk, Member, Promo) dan gabungin
  /// ke penyimpanan lokal. Kalau ID-nya udah ada lokal, di-update (foto produk
  /// lokal TETAP dipertahankan, gak ke-timpa null). Kalau belum ada, dibikin baru.
  /// PENTING: belum ada resolusi konflik pintar — versi dari cloud yang menang
  /// buat field yang di-sync (bukan foto).
  static Future<({bool success, String message})> pullFromCloud() async {
    if (syncServerUrl.isEmpty || syncApiKey.isEmpty) {
      return (success: false, message: 'Isi URL Server & Kode API dulu.');
    }
    try {
      final response = await http.get(
        Uri.parse('$syncServerUrl/sync/pull'),
        headers: {'x-api-key': syncApiKey},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        return (success: false, message: 'Kode API gak valid.');
      }
      if (response.statusCode != 200) {
        return (success: false, message: 'Gagal narik data (status ${response.statusCode}).');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      int productCount = 0;
      for (final raw in (data['products'] as List? ?? [])) {
        final id = raw['id'] as String;
        final existing = products.get(id);
        if (existing != null) {
          existing.name = raw['name'];
          existing.price = raw['price'];
          existing.category = raw['category'];
          existing.stock = raw['stock'];
          existing.sortOrder = raw['sortOrder'] ?? existing.sortOrder;
          existing.isActive = raw['isActive'] ?? true;
          await existing.save();
        } else {
          await products.put(
            id,
            Product(
              id: id,
              name: raw['name'],
              price: raw['price'],
              category: raw['category'] ?? 'Umum',
              stock: raw['stock'] ?? 0,
              sortOrder: raw['sortOrder'] ?? 0,
              isActive: raw['isActive'] ?? true,
            ),
          );
        }
        productCount++;
      }

      int memberCount = 0;
      for (final raw in (data['members'] as List? ?? [])) {
        final id = raw['id'] as String;
        final existing = members.get(id);
        if (existing != null) {
          existing.name = raw['name'];
          existing.phone = raw['phone'];
          existing.points = raw['points'] ?? existing.points;
          await existing.save();
        } else {
          await members.put(
            id,
            Member(
              id: id,
              name: raw['name'],
              phone: raw['phone'],
              points: raw['points'] ?? 0,
              joinedAt: DateTime.now(),
            ),
          );
        }
        memberCount++;
      }

      int promoCount = 0;
      for (final raw in (data['promos'] as List? ?? [])) {
        final id = raw['id'] as String;
        final promo = Promo(
          id: id,
          name: raw['name'],
          discountType: raw['discountType'] ?? 'percentage',
          value: (raw['value'] as num?)?.toDouble() ?? 0,
          scope: raw['scope'] ?? 'cart',
          productIds: (raw['productIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
          startDate: raw['startDate'] != null ? DateTime.tryParse(raw['startDate']) : null,
          endDate: raw['endDate'] != null ? DateTime.tryParse(raw['endDate']) : null,
          minPurchase: raw['minPurchase'] ?? 0,
          active: raw['active'] ?? true,
        );
        await promos.put(id, promo);
        promoCount++;
      }

      return (
        success: true,
        message: 'Berhasil: $productCount produk, $memberCount member, $promoCount promo.',
      );
    } catch (e) {
      return (success: false, message: 'Gagal narik data — cek koneksi internet.');
    }
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
    int? cashReceived,
    int? changeAmount,
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
      cashReceived: cashReceived,
      changeAmount: changeAmount,
    );
    await transactions.put(tx.id, tx);

    // Sinkronisasi ke dashboard web — best-effort, gak nunggu (biar checkout
    // tetep instan) dan gak bikin transaksi gagal kalau lagi offline/gagal kirim.
    _pushTransactionToCloud(tx);

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

cat > lib/screens/inventory_screen.dart << 'INVEOF'
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
INVEOF

echo 'Selesai. Jalankan: flutter clean && flutter pub get && flutter run -d web-server --web-port 8081 --release'
