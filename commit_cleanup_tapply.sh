#!/bin/bash
set -e

echo "=== Add semua perubahan (source code + cleanup + gitignore) ==="
git add -A

echo ""
echo "=== Commit ==="
git commit -m "Clean up scratch scripts from root, update .gitignore

Also includes: table management (DiningTable model, table grid UI),
member email field, WA/Email receipt sending via Fonnte/Resend backend,
split bill member auto-detect, cart layout fix, landscape lock."

echo ""
echo "=== Push ==="
git push

echo ""
echo "=== SELESAI. Repo Tapply udah bersih. ==="
git status
