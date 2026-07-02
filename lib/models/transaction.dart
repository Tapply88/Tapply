import 'package:hive/hive.dart';

part 'transaction.g.dart';

@HiveType(typeId: 2)
class TxItem {
  @HiveField(0)
  String productId;

  @HiveField(1)
  String productName;

  @HiveField(2)
  int price;

  @HiveField(3)
  int qty;

  @HiveField(4)
  String? note; // e.g. "Hangat • Extra Madu"

  TxItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.qty,
    this.note,
  });

  int get subtotal => price * qty;
}

@HiveType(typeId: 3)
class TransactionRecord extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  List<TxItem> items;

  @HiveField(2)
  int total;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  String? memberId; // null kalau non-member

  @HiveField(5)
  String paymentMethod; // "cash", "qris_midtrans", dll

  @HiveField(6)
  String status; // "paid", "pending", "failed"

  @HiveField(7)
  String? midtransOrderId;

  @HiveField(8)
  String salesType; // "Dine In", "Take Away", "Online"

  @HiveField(9)
  int taxAmount;

  @HiveField(10)
  int serviceAmount;

  @HiveField(11)
  int discountAmount;

  @HiveField(12)
  int roundingAdjustment;

  TransactionRecord({
    required this.id,
    required this.items,
    required this.total,
    required this.createdAt,
    this.memberId,
    required this.paymentMethod,
    this.status = 'paid',
    this.midtransOrderId,
    this.salesType = 'Dine In',
    this.taxAmount = 0,
    this.serviceAmount = 0,
    this.discountAmount = 0,
    this.roundingAdjustment = 0,
  });

  int get itemsSubtotal => items.fold(0, (s, i) => s + i.subtotal);
}
