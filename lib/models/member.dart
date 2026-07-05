import 'package:hive/hive.dart';

part 'member.g.dart';

@HiveType(typeId: 1)
class Member extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String phone;

  @HiveField(3)
  int points;

  @HiveField(4)
  DateTime joinedAt;

  @HiveField(5)
  DateTime? birthDate;

  Member({
    required this.id,
    required this.name,
    required this.phone,
    this.points = 0,
    required this.joinedAt,
    this.birthDate,
  });

  // 1 point per Rp10.000 belanja (bisa diubah sesuai kebijakan)
  static int pointsFromAmount(int amount) => (amount / 10000).floor();
}
