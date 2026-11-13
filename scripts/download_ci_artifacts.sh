#!/usr/bin/env bash
set -eo pipefail

TAG="v1.1.0"
REPO="Zenmisan/Cycle"
DEST_DIR="Releases"

mkdir -p "$DEST_DIR"

echo "Downloading official release assets for $TAG into $DEST_DIR/..."
gh release download "$TAG" --repo "$REPO" --dir "$DEST_DIR" --clobber

echo "All artifacts downloaded to $DEST_DIR/"
ls -lh "$DEST_DIR"
