import 'package:hive/hive.dart';
part 'recipe_item.g.dart';
@HiveType(typeId: 12)
class RecipeItem extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String productId;
  @HiveField(2)
  String ingredientId;
  @HiveField(3)
  double quantity;
  RecipeItem({
    required this.id,
    required this.productId,
    required this.ingredientId,
    required this.quantity,
  });
}
