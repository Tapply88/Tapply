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

  @HiveField(7)
  int sortOrder;

  @HiveField(8)
  String sku;

  @HiveField(9)
  DateTime? expiryDate;

  @HiveField(10)
  String? volume;

  @HiveField(11)
  DateTime? productionDate;

  @HiveField(12)
  String labelSize;

  @HiveField(13)
  bool showPriceOnLabel;

  @HiveField(14)
  String? labelVariant;

  @HiveField(15)
  List<String> labelAddons;

  @HiveField(16)
  int? onlinePrice;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.isActive = true,
    this.stock = 0,
    this.imageBase64,
    this.sortOrder = 0,
    this.sku = '',
    this.expiryDate,
    this.volume,
    this.productionDate,
    this.labelSize = '60x40mm',
    this.showPriceOnLabel = true,
    this.labelVariant,
    List<String>? labelAddons,
    this.onlinePrice,
  }) : labelAddons = labelAddons ?? [];
}
