import 'package:hive/hive.dart';

part 'staff_member.g.dart';

@HiveType(typeId: 10)
class StaffMember extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String role; // 'cashier' | 'supervisor'

  @HiveField(3)
  String pin;

  StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.pin,
  });
}
