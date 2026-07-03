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

  Variation({required this.id, required this.name, this.sortOrder = 0});
}
