// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_member.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StaffMemberAdapter extends TypeAdapter<StaffMember> {
  @override
  final int typeId = 10;

  @override
  StaffMember read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StaffMember(
      id: fields[0] as String,
      name: fields[1] as String,
      role: fields[2] as String,
      pin: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, StaffMember obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.pin);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaffMemberAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
