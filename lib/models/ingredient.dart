import 'package:hive/hive.dart';
part 'ingredient.g.dart';
@HiveType(typeId: 11)
class Ingredient extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String unit; // 'gram' | 'ml' | 'pcs'
  @HiveField(3)
  double stock;
  @HiveField(4)
  double lowStockThreshold;
  Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.lowStockThreshold,
  });
}
