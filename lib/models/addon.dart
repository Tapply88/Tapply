import 'package:hive/hive.dart';

part 'addon.g.dart';

@HiveType(typeId: 6)
class Addon extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int price;

  @HiveField(3)
  int sortOrder;

  Addon({required this.id, required this.name, required this.price, this.sortOrder = 0});
}
