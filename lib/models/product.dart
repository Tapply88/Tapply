import 'package:hive/hive.dart';

part 'product.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int price; // in Rupiah

  @HiveField(3)
  String category; // e.g. "Jamu", "Tambahan"

  @HiveField(4)
  bool isActive;

  @HiveField(5)
  int stock;

  @HiveField(6)
  String? imageBase64;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.isActive = true,
    this.stock = 0,
    this.imageBase64,
  });
}
