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
import '../models/ingredient.dart';
import '../models/recipe_item.dart';

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
  static const ingredientBox = 'ingredients';
  static const recipeItemBox = 'recipeItems';
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
    Hive.registerAdapter(IngredientAdapter());
    Hive.registerAdapter(RecipeItemAdapter());

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
    await Hive.openBox<Ingredient>(ingredientBox);
    await Hive.openBox<RecipeItem>(recipeItemBox);
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

  static Future<void> deductIngredientsForSale(String productId, int qtySold) async {
    final recipe = recipeItemsForProduct(productId);
    if (recipe.isEmpty) return;
    final deductions = <Map<String, dynamic>>[];
    for (final r in recipe) {
      final ing = ingredientsBoxRef.get(r.ingredientId);
      if (ing == null) continue;
      final amount = r.quantity * qtySold;
      ing.stock = ing.stock - amount;
      await ing.save();
      deductions.add({'ingredientId': r.ingredientId, 'amount': amount});
    }
    if (deductions.isNotEmpty) {
      _pushIngredientDeductions(deductions);
    }
  }

  static Future<void> _pushIngredientDeductions(List<Map<String, dynamic>> deductions) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    final payload = {'deductions': deductions};
    try {
      final response = await http
          .post(
            Uri.parse('$syncServerUrl/sync/ingredient-deduct'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) await _queueForRetry('/sync/ingredient-deduct', payload);
    } catch (_) {
      await _queueForRetry('/sync/ingredient-deduct', payload);
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

  static Box<Ingredient> get ingredientsBoxRef => Hive.box<Ingredient>(ingredientBox);
  static List<Ingredient> get ingredientsList => ingredientsBoxRef.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  static Box<RecipeItem> get recipeItemsBoxRef => Hive.box<RecipeItem>(recipeItemBox);
  static List<RecipeItem> recipeItemsForProduct(String productId) =>
      recipeItemsBoxRef.values.where((r) => r.productId == productId).toList();
  static bool productHasRecipe(String productId) => recipeItemsForProduct(productId).isNotEmpty;
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

      int ingredientCount = 0;
      for (final raw in (data['ingredients'] as List? ?? [])) {
        final id = raw['id'] as String;
        final existing = ingredientsBoxRef.get(id);
        if (existing != null) {
          existing.name = raw['name'];
          existing.unit = raw['unit'] ?? existing.unit;
          existing.stock = (raw['stock'] as num?)?.toDouble() ?? existing.stock;
          existing.lowStockThreshold = (raw['lowStockThreshold'] as num?)?.toDouble() ?? existing.lowStockThreshold;
          existing.save();
        } else {
          ingredientsBoxRef.put(
            id,
            Ingredient(
              id: id,
              name: raw['name'],
              unit: raw['unit'] ?? 'gram',
              stock: (raw['stock'] as num?)?.toDouble() ?? 0,
              lowStockThreshold: (raw['lowStockThreshold'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
        ingredientCount++;
      }
      int recipeCount = 0;
      recipeItemsBoxRef.clear();
      for (final raw in (data['recipeItems'] as List? ?? [])) {
        final id = raw['id'] as String;
        recipeItemsBoxRef.put(
          id,
          RecipeItem(
            id: id,
            productId: raw['productId'],
            ingredientId: raw['ingredientId'],
            quantity: (raw['quantity'] as num?)?.toDouble() ?? 0,
          ),
        );
        recipeCount++;
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
        message: 'Berhasil: $productCount produk, $memberCount member, $promoCount promo, $ingredientCount bahan, $recipeCount resep.',
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
        if (productHasRecipe(item.productId)) {
          await deductIngredientsForSale(item.productId, item.qty);
        } else {
          await adjustStock(item.productId, -item.qty);
        }
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
