import 'package:hive/hive.dart';

part 'shift.g.dart';

@HiveType(typeId: 7)
class Shift extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String cashierName;

  @HiveField(2)
  String cashierEmail;

  @HiveField(3)
  DateTime startTime;

  @HiveField(4)
  int startingCash;

  @HiveField(5)
  DateTime? endTime;

  @HiveField(6)
  int? endingCashCounted;

  @HiveField(7)
  String status; // 'open' or 'closed'

  @HiveField(8)
  String? note;

  Shift({
    required this.id,
    required this.cashierName,
    required this.cashierEmail,
    required this.startTime,
    required this.startingCash,
    this.endTime,
    this.endingCashCounted,
    this.status = 'open',
    this.note,
  });
}
