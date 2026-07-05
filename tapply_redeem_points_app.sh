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

  static int get pointsRedemptionValue => settings.get('pointsRedemptionValue', defaultValue: 1000);
  static Future<void> setPointsRedemptionValue(int value) async => settings.put('pointsRedemptionValue', value);

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
                      const Text('VARIATION | CHOOSE ONE', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                      const Text('ADD-ONS | CHOOSE MULTIPLE', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
    final maxByPoints = member.points;
    final maxBySubtotal = DbService.pointsRedemptionValue > 0 ? (_subtotal / DbService.pointsRedemptionValue).floor() : 0;
    final maxRedeemable = maxByPoints < maxBySubtotal ? maxByPoints : maxBySubtotal;
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
                  'Rate: ${_currency.format(DbService.pointsRedemptionValue)} per point. Max redeemable now: $maxRedeemable pts.',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Points to redeem'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (entered > 0) ...[
                  const SizedBox(height: 8),
                  Text('= ${_currency.format(value)} discount', style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold)),
                ],
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
                    Text(_currency.format(_basePriceFor(p)), style: TextStyle(fontSize: 12, color: outOfStock ? Colors.grey : _navy)),
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
                  if (_selectedMember != null && _selectedMember!.points > 0)
                    InkWell(
                      onTap: _openRedeemPointsDialog,
                      child: Container(
                        width: double.infinity,
                        color: _pointsToRedeem > 0 ? Colors.green.shade50 : Colors.white,
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
                                color: _pointsToRedeem > 0 ? Colors.green.shade800 : _navy,
                              ),
                            ),
                            Icon(Icons.card_giftcard, size: 16, color: _pointsToRedeem > 0 ? Colors.green.shade800 : _navy),
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
