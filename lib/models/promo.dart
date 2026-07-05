import 'package:hive/hive.dart';

part 'promo.g.dart';

@HiveType(typeId: 4)
class Promo extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String discountType; // 'percentage' or 'fixed'

  @HiveField(3)
  double value; // percentage (0-100) or fixed Rupiah amount

  @HiveField(4)
  DateTime? startDate;

  @HiveField(5)
  DateTime? endDate;

  @HiveField(6)
  int minPurchase;

  @HiveField(7)
  bool active;

  @HiveField(8)
  String scope; // 'cart' (seluruh struk) or 'product' (produk tertentu)

  @HiveField(9)
  List<String> productIds; // dipakai kalau scope == 'product'

  @HiveField(10)
  String triggerType; // 'always' | 'birthday' | 'specific_date'

  @HiveField(11)
  String? triggerMonthDay; // format 'MM-DD', dipakai buat 'specific_date' (dan dicek ulang buat 'birthday' vs member.birthDate)

  Promo({
    required this.id,
    required this.name,
    required this.discountType,
    required this.value,
    this.startDate,
    this.endDate,
    this.minPurchase = 0,
    this.active = true,
    this.scope = 'cart',
    List<String>? productIds,
    this.triggerType = 'always',
    this.triggerMonthDay,
  }) : productIds = productIds ?? [];
}
