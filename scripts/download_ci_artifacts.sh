#!/usr/bin/env bash
set -eo pipefail

RUN_ID="41541232200"
REPO="Zenmisan/Cycle"
DEST_DIR="Releases"

mkdir -p "$DEST_DIR"

ARTIFACTS=(
  "cycles-1.0.0-windows.exe"
  "cycles-1.0.0-windows-portable.zip"
  "cycles-1.0.0-linux.AppImage"
  "cycles-1.0.0-linux.deb"
  "cycles-1.0.0-linux.rpm"
  "cycles-1.0.0-linux.tar.gz"
  "cycles-1.0.0-android.apk"
  "cycles-1.0.0-macos.dmg"
  "cycles-1.0.0-ios-unsigned.ipa"
)

for art in "${ARTIFACTS[@]}"; do
  if [ -f "$DEST_DIR/$art" ] && [ "$art" = "cycles-1.0.0-linux.AppImage" ]; then
    echo "Already downloaded: $art"
    continue
  fi

  echo "Downloading $art..."
  mkdir -p "$DEST_DIR/temp"
  for attempt in 1 2 3; do
    if gh run download "$RUN_ID" --repo "$REPO" -n "$art" --dir "$DEST_DIR/temp"; then
      find "$DEST_DIR/temp" -type f -exec mv {} "$DEST_DIR/" \;
      rm -rf "$DEST_DIR/temp"
      echo "Successfully downloaded $art"
      break
    else
      echo "Attempt $attempt failed for $art, retrying..."
      sleep 2
    fi
  done
done

echo "All artifacts downloaded to $DEST_DIR/"
ls -lh "$DEST_DIR"
