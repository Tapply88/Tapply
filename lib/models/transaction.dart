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

  TxItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.qty,
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

  TransactionRecord({
    required this.id,
    required this.items,
    required this.total,
    required this.createdAt,
    this.memberId,
    required this.paymentMethod,
    this.status = 'paid',
    this.midtransOrderId,
  });
}
