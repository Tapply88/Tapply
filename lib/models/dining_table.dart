import 'package:hive/hive.dart';

part 'dining_table.g.dart';

@HiveType(typeId: 13)
class DiningTable extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int sortOrder;

  DiningTable({
    required this.id,
    required this.name,
    this.sortOrder = 0,
  });
}
