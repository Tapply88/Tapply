// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'variation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VariationAdapter extends TypeAdapter<Variation> {
  @override
  final int typeId = 5;

  @override
  Variation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Variation(
      id: fields[0] as String,
      name: fields[1] as String,
      sortOrder: fields[2] as int,
      price: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Variation obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.sortOrder)
      ..writeByte(3)
      ..write(obj.price);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
