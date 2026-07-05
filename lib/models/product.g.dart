// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      name: fields[1] as String,
      price: fields[2] as int,
      category: fields[3] as String,
      isActive: fields[4] as bool,
      stock: fields[5] as int,
      imageBase64: fields[6] as String?,
      sortOrder: fields[7] as int,
      sku: fields[8] as String,
      expiryDate: fields[9] as DateTime?,
      volume: fields[10] as String?,
      productionDate: fields[11] as DateTime?,
      labelSize: fields[12] as String,
      showPriceOnLabel: fields[13] as bool,
      labelVariant: fields[14] as String?,
      labelAddons: (fields[15] as List?)?.cast<String>(),
      onlinePrice: fields[16] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.isActive)
      ..writeByte(5)
      ..write(obj.stock)
      ..writeByte(6)
      ..write(obj.imageBase64)
      ..writeByte(7)
      ..write(obj.sortOrder)
      ..writeByte(8)
      ..write(obj.sku)
      ..writeByte(9)
      ..write(obj.expiryDate)
      ..writeByte(10)
      ..write(obj.volume)
      ..writeByte(11)
      ..write(obj.productionDate)
      ..writeByte(12)
      ..write(obj.labelSize)
      ..writeByte(13)
      ..write(obj.showPriceOnLabel)
      ..writeByte(14)
      ..write(obj.labelVariant)
      ..writeByte(15)
      ..write(obj.labelAddons)
      ..writeByte(16)
      ..write(obj.onlinePrice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
