#!/usr/bin/env bash
set -euo pipefail

if [ -d "$HOME/flutter" ]; then
  echo "Flutter already installed at $HOME/flutter"
  exit 0
fi

sudo apt-get update
sudo apt-get install -y curl git unzip xz-utils

cd "$HOME"
if [ -d flutter ]; then
  rm -rf flutter
fi

git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter

export PATH="$HOME/flutter/bin:$PATH"

# Accept Android licenses if Android SDK is present
if command -v flutter >/dev/null 2>&1; then
  flutter doctor --android-licenses || true
  flutter doctor
fi
