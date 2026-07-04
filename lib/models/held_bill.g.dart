// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'held_bill.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HeldBillItemAdapter extends TypeAdapter<HeldBillItem> {
  @override
  final int typeId = 8;

  @override
  HeldBillItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HeldBillItem(
      productId: fields[0] as String,
      productName: fields[1] as String,
      unitPrice: fields[2] as int,
      qty: fields[3] as int,
      variation: fields[4] as String,
      addons: (fields[5] as List).cast<String>(),
      memberDiscount: fields[6] as bool,
      optInPromoId: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HeldBillItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.unitPrice)
      ..writeByte(3)
      ..write(obj.qty)
      ..writeByte(4)
      ..write(obj.variation)
      ..writeByte(5)
      ..write(obj.addons)
      ..writeByte(6)
      ..write(obj.memberDiscount)
      ..writeByte(7)
      ..write(obj.optInPromoId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeldBillItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HeldBillAdapter extends TypeAdapter<HeldBill> {
  @override
  final int typeId = 9;

  @override
  HeldBill read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HeldBill(
      id: fields[0] as String,
      createdAt: fields[1] as DateTime,
      items: (fields[2] as List).cast<HeldBillItem>(),
      salesType: fields[3] as String,
      memberId: fields[4] as String?,
      guestName: fields[5] as String?,
      note: fields[6] as String?,
      chosenPromoId: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HeldBill obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.items)
      ..writeByte(3)
      ..write(obj.salesType)
      ..writeByte(4)
      ..write(obj.memberId)
      ..writeByte(5)
      ..write(obj.guestName)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.chosenPromoId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeldBillAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
