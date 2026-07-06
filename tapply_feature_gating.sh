cat > lib/services/db_service.dart << 'DBEOF'
import 'dart:convert';
import 'package:crypto/crypto.dart';
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
import '../models/staff_member.dart';

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
  static const staffBox = 'staff';
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
    Hive.registerAdapter(StaffMemberAdapter());

    await Hive.openBox<Product>(productBox);
    await Hive.openBox<Member>(memberBox);
    await Hive.openBox<TransactionRecord>(txBox);
    await Hive.openBox(settingsBox);
    await Hive.openBox<Promo>(promoBox);
    await Hive.openBox<Variation>(variationBox);
    await Hive.openBox<Addon>(addonBox);
    await Hive.openBox<Shift>(shiftBox);
    await Hive.openBox<HeldBill>(heldBillBox);
    await Hive.openBox<StaffMember>(staffBox);
    await Hive.openBox(syncQueueBox);

    await _seedProductsIfEmpty();
    // Varian & tambahan sekarang dikelola dari dashboard doang (gak di-seed
    // lokal lagi), biar gak ada data "bawaan" yang nyangkut kalau dashboard
    // udah punya versi sendiri.

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
      'sku': p.sku,
      'volume': p.volume,
      'labelSize': p.labelSize,
      'showPriceOnLabel': p.showPriceOnLabel,
      'labelVariant': p.labelVariant,
      'labelAddons': p.labelAddons,
      'expiryDate': p.expiryDate?.toIso8601String(),
      'productionDate': p.productionDate?.toIso8601String(),
      'onlinePrice': p.onlinePrice,
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
      'birthDate': m.birthDate?.toIso8601String(),
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

  /// PIN gak lagi disimpen/dibandingin sebagai teks polos — di-hash pakai
  /// SHA-256 + pepper tetap, sama persis kayak yang dipakai di dashboard web
  /// (lib/hash.ts), biar hasil hash-nya identik dan bisa dibandingin.
  static const String _pinPepper = 'tapply-pin-pepper-v1';
  static String hashPin(String pin) {
    final bytes = utf8.encode(pin + _pinPepper);
    return sha256.convert(bytes).toString();
  }
  static bool get pinRequiredForCancel => settings.get('pinRequiredForCancel', defaultValue: true);
  static Future<void> setPinRequiredForCancel(bool v) async => settings.put('pinRequiredForCancel', v);
  static String get language => settings.get('language', defaultValue: 'id');
  static Future<void> setLanguage(String lang) async => settings.put('language', lang);

  static int get pointsRedemptionValue => settings.get('pointsRedemptionValue', defaultValue: 100);
  static Future<void> setPointsRedemptionValue(int value) async => settings.put('pointsRedemptionValue', value);

  static int get pointsRedemptionMultiple => settings.get('pointsRedemptionMultiple', defaultValue: 300);
  static Future<void> setPointsRedemptionMultiple(int value) async => settings.put('pointsRedemptionMultiple', value);

  /// Rp per 1 poin yang DIDAPAT dari belanja (beda dari pointsRedemptionValue
  /// yang itu nilai TUKAR poin). Default 1000 = tiap Rp1.000 belanja = 1 poin.
  static int get pointsEarnRate => settings.get('pointsEarnRate', defaultValue: 1000);
  static Future<void> setPointsEarnRate(int value) async => settings.put('pointsEarnRate', value);

  // ---- Paket langganan (trial/starter/pro/multi_outlet), dikontrol dari dashboard ----
  static String get businessPlan => settings.get('businessPlan', defaultValue: 'trial');
  static Future<void> setBusinessPlan(String plan) async => settings.put('businessPlan', plan);
  static DateTime? get planExpiresAt {
    final raw = settings.get('planExpiresAt');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> setPlanExpiresAt(String? iso) async {
    if (iso == null) {
      await settings.delete('planExpiresAt');
    } else {
      await settings.put('planExpiresAt', iso);
    }
  }

  /// Trial dianggap "Pro" sampai tanggal expired-nya.
  static bool get isProActive {
    if (businessPlan == 'pro' || businessPlan == 'multi_outlet') return true;
    if (businessPlan == 'trial') {
      final exp = planExpiresAt;
      if (exp == null) return false;
      return DateTime.now().isBefore(exp);
    }
    return false;
  }

  // ---- Sinkronisasi ke dashboard web (satu arah: app -> cloud) ----
  static bool get syncEnabled => syncServerUrl.isNotEmpty && syncApiKey.isNotEmpty;
  static bool get isPaired => syncEnabled;
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
      'id': tx.id,
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
    String? businessLogoBase64,
  }) async {
    if (businessName != null) await settings.put('businessName', businessName);
    if (businessAddress != null) await settings.put('businessAddress', businessAddress);
    if (businessPhone != null) await settings.put('businessPhone', businessPhone);
    if (receiptFooterText != null) await settings.put('receiptFooterText', receiptFooterText);
    if (businessLogoBase64 != null) await settings.put('businessLogoBase64', businessLogoBase64);
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
      'triggerType': p.triggerType,
      'triggerMonthDay': p.triggerMonthDay,
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
  static List<Promo> validPromosFor({required int cartSubtotal, Map<String, int>? productSubtotals, Member? selectedMember}) {
    final now = DateTime.now();
    final todayMonthDay = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return promos.values.where((p) {
      if (!p.active) return false;
      if (p.startDate != null && now.isBefore(p.startDate!)) return false;
      if (p.endDate != null && now.isAfter(p.endDate!)) return false;

      if (p.triggerType == 'birthday') {
        if (selectedMember?.birthDate == null) return false;
        final b = selectedMember!.birthDate!;
        final memberMonthDay = '${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';
        if (memberMonthDay != todayMonthDay) return false;
      } else if (p.triggerType == 'specific_date') {
        if (p.triggerMonthDay == null || p.triggerMonthDay != todayMonthDay) return false;
      }

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

  // ---- Staff (nama, role, PIN — dikelola dari dashboard) ----
  static Box<StaffMember> get staffBoxRef => Hive.box<StaffMember>(staffBox);
  static List<StaffMember> get staffList => staffBoxRef.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  static StaffMember? findStaffByPin(String pin) {
    final hashed = hashPin(pin);
    try {
      return staffBoxRef.values.firstWhere((s) => s.pin == hashed);
    } catch (_) {
      return null;
    }
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
          existing.sku = raw['sku'] ?? existing.sku;
          existing.volume = raw['volume'] ?? existing.volume;
          existing.labelSize = raw['labelSize'] ?? existing.labelSize;
          existing.showPriceOnLabel = raw['showPriceOnLabel'] ?? existing.showPriceOnLabel;
          existing.labelVariant = raw['labelVariant'] ?? existing.labelVariant;
          existing.labelAddons = (raw['labelAddons'] as List?)?.map((e) => e.toString()).toList() ?? existing.labelAddons;
          existing.expiryDate = raw['expiryDate'] != null ? DateTime.tryParse(raw['expiryDate']) : existing.expiryDate;
          existing.productionDate = raw['productionDate'] != null ? DateTime.tryParse(raw['productionDate']) : existing.productionDate;
          if (raw['imageBase64'] != null) existing.imageBase64 = raw['imageBase64'];
          existing.onlinePrice = raw['onlinePrice'];
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
              sku: raw['sku'] ?? '',
              volume: raw['volume'],
              labelSize: raw['labelSize'] ?? '60x40mm',
              showPriceOnLabel: raw['showPriceOnLabel'] ?? true,
              labelVariant: raw['labelVariant'],
              labelAddons: (raw['labelAddons'] as List?)?.map((e) => e.toString()).toList(),
              expiryDate: raw['expiryDate'] != null ? DateTime.tryParse(raw['expiryDate']) : null,
              productionDate: raw['productionDate'] != null ? DateTime.tryParse(raw['productionDate']) : null,
              imageBase64: raw['imageBase64'],
              onlinePrice: raw['onlinePrice'],
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
          existing.birthDate = raw['birthDate'] != null ? DateTime.tryParse(raw['birthDate']) : existing.birthDate;
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
              birthDate: raw['birthDate'] != null ? DateTime.tryParse(raw['birthDate']) : null,
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
          triggerType: raw['triggerType'] ?? 'always',
          triggerMonthDay: raw['triggerMonthDay'],
        );
        await promos.put(id, promo);
        promoCount++;
      }

      // Pengaturan bisnis (tax/service/dst) sekarang cuma bisa diedit dari
      // dashboard — app nurut aja ke apa yang ke-pull di sini.
      //
      // Varian, tambahan, dan staff di-CLEAR dulu terus diisi ulang persis
      // sama isi dashboard (bukan cuma ditambahin) — biar kalau kamu hapus
      // sesuatu di dashboard, otomatis ikut kehapus juga di app, gak nyangkut
      // jadi data "bawaan" yang duplikat.
      await variationsBox.clear();
      for (final raw in (data['variations'] as List? ?? [])) {
        final id = raw['id'] as String;
        await variationsBox.put(id, Variation(id: id, name: raw['name'], sortOrder: raw['sortOrder'] ?? 0, price: raw['price'] ?? 0, onlinePrice: raw['onlinePrice']));
      }

      await addonsBox.clear();
      for (final raw in (data['addons'] as List? ?? [])) {
        final id = raw['id'] as String;
        await addonsBox.put(id, Addon(id: id, name: raw['name'], price: raw['price'] ?? 0, sortOrder: raw['sortOrder'] ?? 0, onlinePrice: raw['onlinePrice']));
      }

      await staffBoxRef.clear();
      for (final raw in (data['staff'] as List? ?? [])) {
        final id = raw['id'] as String;
        await staffBoxRef.put(id, StaffMember(id: id, name: raw['name'], role: raw['role'] ?? 'cashier', pin: raw['pin'] ?? ''));
      }

      final business = data['business'] as Map<String, dynamic>?;
      if (business != null) {
        await updateBusinessProfile(
          businessName: business['name'],
          businessAddress: business['address'],
          businessPhone: business['phone'],
          receiptFooterText: business['footerText'],
          businessLogoBase64: business['logoBase64'],
        );
        await updateSettings(
          taxEnabled: (business['taxPercent'] ?? 0) > 0,
          taxPercent: (business['taxPercent'] as num?)?.toDouble(),
          serviceEnabled: (business['servicePercent'] ?? 0) > 0,
          servicePercent: (business['servicePercent'] as num?)?.toDouble(),
          discountEnabled: (business['discountPercent'] ?? 0) > 0,
          discountPercent: (business['discountPercent'] as num?)?.toDouble(),
          roundingEnabled: business['roundingEnabled'],
          roundingNearest: business['roundingNearest'],
        );
        if (business['managerPin'] != null) await setManagerPin(business['managerPin']);
        if (business['pinRequiredForCancel'] != null) await setPinRequiredForCancel(business['pinRequiredForCancel']);
        if (business['printCheckEnabled'] != null) await setPrintCheckEnabled(business['printCheckEnabled']);
        if (business['queueNumberEnabled'] != null) await setQueueNumberEnabled(business['queueNumberEnabled']);
        if (business['queueStartNumber'] != null) await setQueueStartNumber(business['queueStartNumber']);
        if (business['pointsRedemptionValue'] != null) await setPointsRedemptionValue(business['pointsRedemptionValue']);
        if (business['pointsRedemptionMultiple'] != null) await setPointsRedemptionMultiple(business['pointsRedemptionMultiple']);
        if (business['pointsEarnRate'] != null) await setPointsEarnRate(business['pointsEarnRate']);
        if (business['plan'] != null) await setBusinessPlan(business['plan']);
        await setPlanExpiresAt(business['planExpiresAt']);
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
        if (pointsEarnRate > 0) member.points += (grandTotal / pointsEarnRate).floor();
        await member.save();
      }
    }
    return tx;
  }

  // ---- Reports ----
  static Future<void> voidTransaction(String txId) async {
    final tx = transactions.get(txId);
    if (tx == null) return;
    tx.status = 'void';
    await tx.save();
    _pushTransactionToCloud(tx);
  }

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

cat > lib/screens/membership_screen.dart << 'MEMSCREOF'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    DateTime? birthDate;
    final dateFmt = DateFormat('dd MMM yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Register New Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      birthDate == null ? 'Birthday (optional)' : 'Birthday: ${dateFmt.format(birthDate!)}',
                      style: const TextStyle(fontSize: 13, color: _navy),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1930),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => birthDate = picked);
                    },
                    child: const Text('Pick'),
                  ),
                ],
              ),
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
      ),
    );

    if (ok == true && nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
      final member = Member(
        id: _uuid.v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        joinedAt: DateTime.now(),
        birthDate: birthDate,
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
    if (!DbService.isProActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Member')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: _navy),
                const SizedBox(height: 16),
                const Text('Member Accounts is a Pro Feature', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                const SizedBox(height: 8),
                const Text(
                  'Upgrade your plan from the dashboard to unlock member accounts and loyalty points.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
MEMSCREOF

cat > lib/screens/inventory_screen.dart << 'INVEOF'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'dart:convert';
import '../models/product.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF092762);

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
            if (p.sku.isNotEmpty) Text('SKU: ${p.sku}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              style: TextStyle(fontSize: 11, color: Colors.grey),
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
                ? const Center(child: Text('No matching products.', style: TextStyle(color: Colors.grey)))
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
                                color: low ? Colors.red.shade50 : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: low ? Colors.red : Colors.green),
                              ),
                              child: Text(
                                'Stock: ${p.stock}',
                                style: TextStyle(
                                  color: low ? Colors.red.shade800 : Colors.green.shade800,
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
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
                child: Center(child: Text('Set the options above, then tap Generate.', style: TextStyle(color: Colors.grey))),
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
      if (p.labelVariant != null) p.labelVariant!,
      ...p.labelAddons,
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
INVEOF

cat > lib/screens/settings_screen.dart << 'SETSCREOF'
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
    final plan = DbService.businessPlan;
    final isPro = DbService.isProActive;
    final expires = DbService.planExpiresAt;
    String planLabel;
    if (plan == 'trial') {
      planLabel = isPro ? 'Trial (Pro features)' : 'Trial Expired';
    } else if (plan == 'pro') {
      planLabel = 'Pro';
    } else if (plan == 'multi_outlet') {
      planLabel = 'Multi-Outlet';
    } else {
      planLabel = 'Starter';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isPro ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isPro ? Colors.green : Colors.orange),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan: $planLabel', style: TextStyle(fontWeight: FontWeight.bold, color: isPro ? Colors.green.shade800 : Colors.orange.shade800)),
                    if (expires != null)
                      Text(
                        '${plan == 'trial' ? 'Trial ends' : 'Expires'} ${expires.day}/${expires.month}/${expires.year}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                Icon(isPro ? Icons.check_circle : Icons.error_outline, color: isPro ? Colors.green : Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
SETSCREOF

cat > server/index.js << 'SRVEOF'
// Backend proxy kecil buat Tapply — nyimpen Midtrans Server Key dengan aman.
// Jalankan: cd server && npm install && node index.js
// Deploy ke Railway/Render/Fly.io/VPS. JANGAN commit .env ke git.

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const midtransClient = require('midtrans-client');
const { createClient } = require('@supabase/supabase-js');

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

// Service Role Key -> akses penuh ke Supabase, TAPI cuma dipegang server ini,
// gak pernah dikirim ke app Flutter. Itu yang bikin app bisa "nulis" data
// biar aman walau app-nya sendiri gak login ke Supabase.
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const snap = new midtransClient.Snap({
  isProduction: false, // ganti true kalau sudah live
  serverKey: process.env.MIDTRANS_SERVER_KEY,
  clientKey: process.env.MIDTRANS_CLIENT_KEY,
});

app.post('/create-transaction', async (req, res) => {
  try {
    const { order_id, gross_amount, customer_name } = req.body;
    const parameter = {
      transaction_details: {
        order_id,
        gross_amount,
      },
      customer_details: {
        first_name: customer_name || 'Pelanggan',
      },
      enabled_payments: ['gopay', 'qris', 'other_qris', 'bank_transfer'],
    };
    const transaction = await snap.createTransaction(parameter);
    res.json(transaction); // berisi token & redirect_url
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/status/:orderId', async (req, res) => {
  try {
    const apiClient = new midtransClient.CoreApi({
      isProduction: false,
      serverKey: process.env.MIDTRANS_SERVER_KEY,
      clientKey: process.env.MIDTRANS_CLIENT_KEY,
    });
    const status = await apiClient.transaction.status(req.params.orderId);
    res.json(status);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// Webhook notifikasi dari Midtrans (set URL ini di dashboard Midtrans)
app.post('/midtrans-webhook', async (req, res) => {
  console.log('Notifikasi Midtrans masuk:', req.body);
  // TODO: update status transaksi di database kamu berdasarkan req.body
  res.sendStatus(200);
});

// ---- Sinkronisasi transaksi dari app kasir (Flutter) ke dashboard web ----
// App Flutter kirim: header 'x-api-key' (dari Setelan > Sinkronisasi di dashboard)
// + body JSON transaksi. Server ini yang cari tau business_id-nya, terus nulis
// ke Supabase pakai Service Role Key (bukan app-nya langsung).
app.post('/sync/transaction', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) {
      return res.status(401).json({ error: 'x-api-key header kosong' });
    }

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();

    if (businessError || !business) {
      return res.status(401).json({ error: 'API key gak valid' });
    }

    const tx = req.body;
    const { error: insertError } = await supabaseAdmin.from('transactions').upsert({
      id: tx.id,
      business_id: business.id,
      items: tx.items,
      total: tx.total,
      tax_amount: tx.taxAmount,
      service_amount: tx.serviceAmount,
      discount_amount: tx.discountAmount,
      discount_label: tx.discountLabel,
      rounding_adjustment: tx.roundingAdjustment,
      payment_method: tx.paymentMethod,
      sales_type: tx.salesType,
      guest_name: tx.guestName,
      cashier_name: tx.cashierName,
      cashier_email: tx.cashierEmail,
      receipt_number: tx.receiptNumber,
      queue_code: tx.queueCode,
      status: tx.status,
      created_at: tx.createdAt,
    });

    if (insertError) {
      console.error(insertError);
      return res.status(500).json({ error: 'Gagal simpan ke database' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi member (upsert berdasarkan id lokal dari app) ----
app.post('/sync/member', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const m = req.body;
    const { error: upsertError } = await supabaseAdmin.from('members').upsert({
      id: m.id,
      business_id: business.id,
      name: m.name,
      phone: m.phone,
      points: m.points,
      birth_date: m.birthDate ? m.birthDate.substring(0, 10) : null,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan member' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi promo (upsert berdasarkan id lokal dari app) ----
app.post('/sync/promo', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const p = req.body;
    const { error: upsertError } = await supabaseAdmin.from('promos').upsert({
      id: p.id,
      business_id: business.id,
      name: p.name,
      discount_type: p.discountType,
      value: p.value,
      scope: p.scope,
      product_ids: p.productIds ?? [],
      start_date: p.startDate ? p.startDate.substring(0, 10) : null,
      end_date: p.endDate ? p.endDate.substring(0, 10) : null,
      min_purchase: p.minPurchase,
      active: p.active,
      trigger_type: p.triggerType ?? 'always',
      trigger_month_day: p.triggerMonthDay ?? null,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan promo' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi produk (upsert berdasarkan id lokal dari app) ----
// Foto produk sengaja gak dikirim di sini (base64 kebesaran) — cuma data teks.
app.post('/sync/product', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const p = req.body;
    const { error: upsertError } = await supabaseAdmin.from('products').upsert({
      id: p.id,
      business_id: business.id,
      name: p.name,
      price: p.price,
      category: p.category,
      stock: p.stock,
      sort_order: p.sortOrder,
      is_active: p.isActive,
      sku: p.sku,
      volume: p.volume,
      label_size: p.labelSize,
      show_price_on_label: p.showPriceOnLabel,
      label_variant: p.labelVariant,
      label_addons: p.labelAddons || [],
      expiry_date: p.expiryDate ? p.expiryDate.substring(0, 10) : null,
      production_date: p.productionDate ? p.productionDate.substring(0, 10) : null,
      online_price: p.onlinePrice,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan produk' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi shift (upsert berdasarkan id lokal dari app) ----
app.post('/sync/shift', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const s = req.body;
    const { error: upsertError } = await supabaseAdmin.from('shifts').upsert({
      id: s.id,
      business_id: business.id,
      cashier_name: s.cashierName,
      cashier_email: s.cashierEmail,
      start_time: s.startTime,
      starting_cash: s.startingCash,
      end_time: s.endTime,
      ending_cash_counted: s.endingCashCounted,
      status: s.status,
      note: s.note,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan shift' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Tarik data dari cloud ke app (bagian dari sync dua arah) ----
// App manggil ini pas cashier klik "Tarik Data dari Dashboard" di Setelan.
app.get('/sync/pull', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: businessFull, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('*')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !businessFull) return res.status(401).json({ error: 'API key gak valid' });
    const business = businessFull;

    const [{ data: products }, { data: members }, { data: promos }, { data: variations }, { data: addons }, { data: staff }] = await Promise.all([
      supabaseAdmin.from('products').select('*').eq('business_id', business.id),
      supabaseAdmin.from('members').select('*').eq('business_id', business.id),
      supabaseAdmin.from('promos').select('*').eq('business_id', business.id),
      supabaseAdmin.from('variations').select('*').eq('business_id', business.id),
      supabaseAdmin.from('addons').select('*').eq('business_id', business.id),
      supabaseAdmin.from('staff').select('*').eq('business_id', business.id).eq('active', true),
    ]);

    res.json({
      products: (products || []).map((p) => ({
        id: p.id,
        name: p.name,
        price: p.price,
        category: p.category,
        stock: p.stock,
        sortOrder: p.sort_order,
        isActive: p.is_active,
        sku: p.sku,
        volume: p.volume,
        labelSize: p.label_size,
        showPriceOnLabel: p.show_price_on_label,
        labelVariant: p.label_variant,
        labelAddons: p.label_addons || [],
        expiryDate: p.expiry_date,
        productionDate: p.production_date,
        imageBase64: p.image_base64,
        onlinePrice: p.online_price,
      })),
      members: (members || []).map((m) => ({
        id: m.id,
        name: m.name,
        phone: m.phone,
        points: m.points,
        birthDate: m.birth_date,
      })),
      promos: (promos || []).map((p) => ({
        id: p.id,
        name: p.name,
        discountType: p.discount_type,
        value: p.value,
        scope: p.scope,
        productIds: p.product_ids || [],
        startDate: p.start_date,
        endDate: p.end_date,
        minPurchase: p.min_purchase,
        active: p.active,
        triggerType: p.trigger_type,
        triggerMonthDay: p.trigger_month_day,
      })),
      variations: (variations || []).map((v) => ({
        id: v.id,
        name: v.name,
        sortOrder: v.sort_order,
        price: v.price,
        onlinePrice: v.online_price,
      })),
      addons: (addons || []).map((a) => ({
        id: a.id,
        name: a.name,
        price: a.price,
        sortOrder: a.sort_order,
        onlinePrice: a.online_price,
      })),
      staff: (staff || []).map((s) => ({
        id: s.id,
        name: s.name,
        role: s.role,
        pin: s.pin,
      })),
      business: {
        name: business.name,
        address: business.address,
        phone: business.phone,
        footerText: business.footer_text,
        taxPercent: business.tax_percent,
        servicePercent: business.service_percent,
        discountPercent: business.discount_percent,
        roundingEnabled: business.rounding_enabled,
        roundingNearest: business.rounding_nearest,
        managerPin: business.manager_pin,
        pinRequiredForCancel: business.pin_required_for_cancel,
        printCheckEnabled: business.print_check_enabled,
        queueNumberEnabled: business.queue_number_enabled,
        queueStartNumber: business.queue_start_number,
        pointsRedemptionValue: business.points_redemption_value,
        pointsRedemptionMultiple: business.points_redemption_multiple,
        pointsEarnRate: business.points_earn_rate,
        plan: business.plan,
        planExpiresAt: business.plan_expires_at,
        logoBase64: business.logo_base64,
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Tapply backend jalan di port ${PORT}`));
SRVEOF

echo 'Selesai. Jalankan: flutter clean && flutter pub get && flutter run -d web-server --web-port 8081 --release'
