#!/bin/bash
set -e

echo "=== flutter pub get ==="
flutter pub get

echo ""
echo "=== Build APK release ==="
flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
  echo "APK tidak ditemukan di $APK_PATH — build kemungkinan gagal, cek log di atas."
  exit 1
fi

echo ""
echo "=== APK berhasil dibuild: $APK_PATH ==="
ls -lh "$APK_PATH"

echo ""
echo "=== Cari tag release terakhir ==="
LATEST_TAG=$(gh release list --limit 50 2>/dev/null | grep -oE 'v[0-9]+' | sort -t v -k2 -n | tail -1 || true)

if [ -z "$LATEST_TAG" ]; then
  NEXT_NUM=1
else
  LATEST_NUM=$(echo "$LATEST_TAG" | tr -d 'v')
  NEXT_NUM=$((LATEST_NUM + 1))
fi

NEXT_TAG="v${NEXT_NUM}"
echo "Tag terakhir: ${LATEST_TAG:-tidak ada}. Tag baru: $NEXT_TAG"

echo ""
echo "=== Rename APK & buat GitHub Release ==="
RENAMED_APK="Tapply-${NEXT_TAG}.apk"
cp "$APK_PATH" "$RENAMED_APK"

gh release create "$NEXT_TAG" "$RENAMED_APK" \
  --title "Tapply $NEXT_TAG" \
  --notes "Fix: cart items list gak muncul/kegencet di panel POS pada layar pendek (scrollable cart panel, tombol footer tetap dipin di bawah)."

echo ""
echo "=== SELESAI. Release $NEXT_TAG berhasil dibuat dengan APK terlampir. ==="
gh release view "$NEXT_TAG"
