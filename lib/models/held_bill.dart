import 'package:hive/hive.dart';

part 'held_bill.g.dart';

@HiveType(typeId: 8)
class HeldBillItem {
  @HiveField(0)
  String productId;

  @HiveField(1)
  String productName;

  @HiveField(2)
  int unitPrice;

  @HiveField(3)
  int qty;

  @HiveField(4)
  String variation;

  @HiveField(5)
  List<String> addons;

  @HiveField(6)
  bool memberDiscount;

  @HiveField(7)
  String? optInPromoId;

  HeldBillItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    required this.variation,
    required this.addons,
    required this.memberDiscount,
    this.optInPromoId,
  });
}

@HiveType(typeId: 9)
class HeldBill extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime createdAt;

  @HiveField(2)
  List<HeldBillItem> items;

  @HiveField(3)
  String salesType;

  @HiveField(4)
  String? memberId;

  @HiveField(5)
  String? guestName;

  @HiveField(6)
  String? note;

  @HiveField(7)
  String? chosenPromoId;

  @HiveField(8)
  String? tableId;

  HeldBill({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.salesType,
    this.memberId,
    this.guestName,
    this.note,
    this.chosenPromoId,
    this.tableId,
  });
}
