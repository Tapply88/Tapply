// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PromoAdapter extends TypeAdapter<Promo> {
  @override
  final int typeId = 4;

  @override
  Promo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Promo(
      id: fields[0] as String,
      name: fields[1] as String,
      discountType: fields[2] as String,
      value: fields[3] as double,
      startDate: fields[4] as DateTime?,
      endDate: fields[5] as DateTime?,
      minPurchase: fields[6] as int,
      active: fields[7] as bool,
      scope: fields[8] as String,
      productIds: (fields[9] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Promo obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.discountType)
      ..writeByte(3)
      ..write(obj.value)
      ..writeByte(4)
      ..write(obj.startDate)
      ..writeByte(5)
      ..write(obj.endDate)
      ..writeByte(6)
      ..write(obj.minPurchase)
      ..writeByte(7)
      ..write(obj.active)
      ..writeByte(8)
      ..write(obj.scope)
      ..writeByte(9)
      ..write(obj.productIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PromoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
