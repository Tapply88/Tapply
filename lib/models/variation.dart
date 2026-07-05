import 'package:hive/hive.dart';

part 'variation.g.dart';

@HiveType(typeId: 5)
class Variation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int sortOrder;

  @HiveField(3)
  int price;

  @HiveField(4)
  int? onlinePrice;

  Variation({required this.id, required this.name, this.sortOrder = 0, this.price = 0, this.onlinePrice});
}
