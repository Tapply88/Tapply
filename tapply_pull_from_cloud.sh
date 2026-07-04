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
    _pushProductToCloud(p);
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
    try {
      await http
          .post(
            Uri.parse('$syncServerUrl/sync/product'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode({
              'id': p.id,
              'name': p.name,
              'price': p.price,
              'category': p.category,
              'stock': p.stock,
              'sortOrder': p.sortOrder,
              'isActive': p.isActive,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline itu wajar, gak apa-apa — data tetep aman lokal.
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
    try {
      await http
          .post(
            Uri.parse('$syncServerUrl/sync/member'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode({
              'id': m.id,
              'name': m.name,
              'phone': m.phone,
              'points': m.points,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline itu wajar, gak apa-apa — data tetep aman lokal.
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

  // ---- Sinkronisasi ke dashboard web (satu arah: app -> cloud) ----
  static bool get syncEnabled => settings.get('syncEnabled', defaultValue: false);
  static Future<void> setSyncEnabled(bool v) async => settings.put('syncEnabled', v);
  static String get syncServerUrl => settings.get('syncServerUrl', defaultValue: '');
  static Future<void> setSyncServerUrl(String url) async => settings.put('syncServerUrl', url);
  static String get syncApiKey => settings.get('syncApiKey', defaultValue: '');
  static Future<void> setSyncApiKey(String key) async => settings.put('syncApiKey', key);

  /// Kirim satu transaksi ke dashboard web. Gak nge-block, gak nge-throw —
  /// kalau lagi offline atau server-nya mati, transaksi tetap aman di Hive
  /// lokal, cuma gak ke-push ke cloud (belum ada retry queue di versi ini).
  static Future<void> _pushTransactionToCloud(TransactionRecord tx) async {
    if (!syncEnabled || syncServerUrl.isEmpty || syncApiKey.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$syncServerUrl/sync/transaction'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': syncApiKey,
            },
            body: jsonEncode({
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
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Sengaja diem — offline itu hal normal buat POS, jangan sampai
      // gagal sync bikin transaksi kasir ikut gagal.
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
    try {
      await http
          .post(
            Uri.parse('$syncServerUrl/sync/promo'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode({
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
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline itu wajar, gak apa-apa — data tetep aman lokal.
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
    try {
      await http
          .post(
            Uri.parse('$syncServerUrl/sync/shift'),
            headers: {'Content-Type': 'application/json', 'x-api-key': syncApiKey},
            body: jsonEncode({
              'id': s.id,
              'cashierName': s.cashierName,
              'cashierEmail': s.cashierEmail,
              'startTime': s.startTime.toIso8601String(),
              'startingCash': s.startingCash,
              'endTime': s.endTime?.toIso8601String(),
              'endingCashCounted': s.endingCashCounted,
              'status': s.status,
              'note': s.note,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline itu wajar, gak apa-apa — data tetep aman lokal.
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
  late bool _syncEnabled;
  late final TextEditingController _syncUrlCtrl;
  late final TextEditingController _syncKeyCtrl;
  bool _pulling = false;

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
    _syncEnabled = DbService.syncEnabled;
    _syncUrlCtrl = TextEditingController(text: DbService.syncServerUrl);
    _syncKeyCtrl = TextEditingController(text: DbService.syncApiKey);
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
          const Divider(height: 40),
          const Text('Sinkronisasi ke Dashboard Web', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Kirim transaksi ke dashboard web (satu arah). Ambil URL server dan kode API dari '
            'dashboard web → Setelan → Sinkronisasi. Kalau lagi offline, transaksi tetap aman '
            'tersimpan lokal, cuma belum ke-kirim (belum ada retry otomatis di versi ini).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Aktifkan Sinkronisasi'),
            value: _syncEnabled,
            onChanged: (v) => setState(() => _syncEnabled = v),
          ),
          if (_syncEnabled) ...[
            TextField(
              controller: _syncUrlCtrl,
              decoration: const InputDecoration(labelText: 'URL Server Sync', hintText: 'https://tapply-server.example.com'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _syncKeyCtrl,
              decoration: const InputDecoration(labelText: 'Kode API (dari dashboard web)'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () async {
              await DbService.setSyncEnabled(_syncEnabled);
              await DbService.setSyncServerUrl(_syncUrlCtrl.text.trim());
              await DbService.setSyncApiKey(_syncKeyCtrl.text.trim());
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan sinkronisasi disimpan')));
            },
            child: const Text('Simpan Sinkronisasi'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: _pulling
                ? null
                : () async {
                    setState(() => _pulling = true);
                    final result = await DbService.pullFromCloud();
                    setState(() => _pulling = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
                    }
                  },
            child: Text(_pulling ? 'Menarik data...' : 'Tarik Data dari Dashboard'),
          ),
          const Text(
            'Ambil Produk/Member/Promo terbaru yang diedit dari dashboard web. Kalau ada '
            'yang bentrok, versi dari dashboard yang dipakai (belum ada gabung otomatis pintar).',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
SETEOF

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
    const { error: insertError } = await supabaseAdmin.from('transactions').insert({
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

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const [{ data: products }, { data: members }, { data: promos }] = await Promise.all([
      supabaseAdmin.from('products').select('*').eq('business_id', business.id),
      supabaseAdmin.from('members').select('*').eq('business_id', business.id),
      supabaseAdmin.from('promos').select('*').eq('business_id', business.id),
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
      })),
      members: (members || []).map((m) => ({
        id: m.id,
        name: m.name,
        phone: m.phone,
        points: m.points,
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
      })),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Tapply backend jalan di port ${PORT}`));
SRVEOF

echo 'Selesai. Untuk app: flutter clean && flutter pub get && flutter run -d web-server --web-port 8081 --release'
echo 'Untuk server/: git add . && git commit -m "two-way sync: pull from cloud" && git push (Railway auto-redeploy)'
