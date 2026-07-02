// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TxItemAdapter extends TypeAdapter<TxItem> {
  @override
  final int typeId = 2;

  @override
  TxItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TxItem(
      productId: fields[0] as String,
      productName: fields[1] as String,
      price: fields[2] as int,
      qty: fields[3] as int,
      note: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TxItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.qty)
      ..writeByte(4)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TxItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionRecordAdapter extends TypeAdapter<TransactionRecord> {
  @override
  final int typeId = 3;

  @override
  TransactionRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TransactionRecord(
      id: fields[0] as String,
      items: (fields[1] as List).cast<TxItem>(),
      total: fields[2] as int,
      createdAt: fields[3] as DateTime,
      memberId: fields[4] as String?,
      paymentMethod: fields[5] as String,
      status: fields[6] as String,
      midtransOrderId: fields[7] as String?,
      salesType: fields[8] as String,
      taxAmount: fields[9] as int,
      serviceAmount: fields[10] as int,
      discountAmount: fields[11] as int,
      roundingAdjustment: fields[12] as int,
    );
  }

  @override
  void write(BinaryWriter writer, TransactionRecord obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.items)
      ..writeByte(2)
      ..write(obj.total)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.memberId)
      ..writeByte(5)
      ..write(obj.paymentMethod)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.midtransOrderId)
      ..writeByte(8)
      ..write(obj.salesType)
      ..writeByte(9)
      ..write(obj.taxAmount)
      ..writeByte(10)
      ..write(obj.serviceAmount)
      ..writeByte(11)
      ..write(obj.discountAmount)
      ..writeByte(12)
      ..write(obj.roundingAdjustment);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
