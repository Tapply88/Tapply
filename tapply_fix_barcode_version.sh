cat > pubspec.yaml << 'PUBEOF'
name: tapply
description: Tapply - POS Kasir + Membership untuk bisnis F&B
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  http: ^1.2.1
  intl: ^0.19.0
  uuid: ^4.4.0
  provider: ^6.1.2
  fl_chart: ^0.68.0
  image_picker: ^1.1.2
  reorderable_grid_view: ^2.2.8
  qr_flutter: ^4.1.0
  barcode_widget: ^2.0.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  hive_generator: ^2.0.1
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/
PUBEOF

echo 'Selesai. Sekarang jalankan:'
echo 'flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter run -d web-server --web-port 8081 --release'
