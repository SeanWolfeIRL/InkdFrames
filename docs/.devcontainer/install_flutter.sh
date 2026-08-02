#!/usr/bin/env bash

set -euo pipefail

FLUTTER_DIR="/opt/flutter"

if command -v flutter >/dev/null 2>&1; then
  echo "Flutter is already installed."
    flutter --version
      exit 0
      fi

      echo "Installing Flutter..."

      sudo apt-get update
      sudo apt-get install -y \
        curl \
          git \
            unzip \
              xz-utils \
                zip \
                  libglu1-mesa

                  sudo git clone \
                    --depth 1 \
                      --branch stable \
                        https://github.com/flutter/flutter.git \
                          "$FLUTTER_DIR"

                          sudo chown -R vscode:vscode "$FLUTTER_DIR"

                          echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$HOME/.bashrc"
                          echo 'export PATH="/opt/flutter/bin:$PATH"' >> "$HOME/.profile"

                          export PATH="/opt/flutter/bin:$PATH"

                          flutter config --no-analytics
                          flutter precache --web
                          flutter doctor