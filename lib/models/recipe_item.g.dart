// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecipeItemAdapter extends TypeAdapter<RecipeItem> {
  @override
  final int typeId = 12;

  @override
  RecipeItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecipeItem(
      id: fields[0] as String,
      productId: fields[1] as String,
      ingredientId: fields[2] as String,
      quantity: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, RecipeItem obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.ingredientId)
      ..writeByte(3)
      ..write(obj.quantity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
