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

  Promo({
    required this.id,
    required this.name,
    required this.discountType,
    required this.value,
    this.startDate,
    this.endDate,
    this.minPurchase = 0,
    this.active = true,
  });
}
