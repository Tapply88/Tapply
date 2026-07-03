// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'addon.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AddonAdapter extends TypeAdapter<Addon> {
  @override
  final int typeId = 6;

  @override
  Addon read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Addon(
      id: fields[0] as String,
      name: fields[1] as String,
      price: fields[2] as int,
      sortOrder: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Addon obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
