#!/usr/bin/env bash
set -euo pipefail

# Usage: ./create_release_build.sh
# Interactive helper to create an upload keystore, write .env, update .gitignore,
# build signed release APK and AAB, verify signing, and optionally install APK.
#
# This script does NOT store your passwords in the script. It will prompt you
# securely for the keystore store password and key password and write them to
# a .env file for the Gradle Secrets plugin to read.

# Defaults (edit if you want a different keystore path)
KEYSTORE_PATH="./my-upload-key.jks"
KEY_ALIAS="upload"
BUILD_AAB=true   # set to false to skip bundleRelease
GRADLEW="./gradlew"

# Distinguished Name fields (filled with your provided values)
CN="SHAMSU AUWAL HARUNA"
OU="Mobile"
O="NAIRA AFRICA"
L="Kano"
S="Kano"
C="NG"

echo "== Naira Africa: release build helper =="

# Prompt for passwords (hidden)
read -rp "Enter keystore path (default: ${KEYSTORE_PATH}): " input_keystore
if [ -n "$input_keystore" ]; then
  KEYSTORE_PATH="$input_keystore"
fi

read -rsp "Enter STORE_PASSWORD for keystore: " STORE_PASSWORD
echo
read -rsp "Enter KEY_PASSWORD for key alias (press Enter to use same as STORE_PASSWORD): " KEY_PASSWORD
echo
if [ -z "$KEY_PASSWORD" ]; then
  KEY_PASSWORD="$STORE_PASSWORD"
fi

# 1) Create keystore if it doesn't exist
if [ -f "$KEYSTORE_PATH" ]; then
  echo "Keystore already exists at $KEYSTORE_PATH"
else
  echo "Creating keystore at $KEYSTORE_PATH"
  keytool -genkeypair -v \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=${CN}, OU=${OU}, O=${O}, L=${L}, S=${S}, C=${C}"
  echo "Keystore created at $KEYSTORE_PATH"
fi

# 2) Write .env (Secrets Gradle plugin reads this)
ENV_FILE=".env"
cat > "$ENV_FILE" <<EOF
KEYSTORE_PATH=$KEYSTORE_PATH
STORE_PASSWORD=$STORE_PASSWORD
KEY_PASSWORD=$KEY_PASSWORD
EOF
chmod 600 "$ENV_FILE"
echo ".env written at project root (permissions set to 600)."

# 3) Update .gitignore to avoid committing secrets (append if missing)
GITIGNORE=".gitignore"
if [ ! -f "$GITIGNORE" ]; then
  touch "$GITIGNORE"
fi
grep -qxF ".env" "$GITIGNORE" || echo ".env" >> "$GITIGNORE"
grep -qxF "*.jks" "$GITIGNORE" || echo "*.jks" >> "$GITIGNORE"
echo ".gitignore ensured to ignore .env and keystore files."

# 4) Build signed release APK and AAB
echo "Running Gradle clean..."
$GRADLEW clean

echo "Building release APK (assembleRelease)..."
$GRADLEW assembleRelease

if [ "$BUILD_AAB" = true ] ; then
  echo "Building release AAB (bundleRelease)..."
  $GRADLEW bundleRelease
fi

APK_PATH="app/build/outputs/apk/release/app-release.apk"
AAB_PATH="app/build/outputs/bundle/release/app-release.aab"

echo
if [ -f "$APK_PATH" ]; then
  echo "APK: $APK_PATH"
else
  echo "APK not found at $APK_PATH"
fi
if [ -f "$AAB_PATH" ]; then
  echo "AAB: $AAB_PATH"
else
  echo "AAB not found at $AAB_PATH"
fi

# 5) Verify APK signing (if apksigner available)
if command -v apksigner >/dev/null 2>&1 && [ -f "$APK_PATH" ]; then
  echo
  echo "Verifying APK signature with apksigner..."
  apksigner verify --print-certs "$APK_PATH" || echo "apksigner verification failed"
else
  echo "apksigner not found or APK missing; skipping signature verification."
fi

# 6) Print SHA-1 of the upload key (useful for Firebase/Play)
echo
echo "Upload key certificate fingerprint (SHA-1):"
# keytool will print the SHA1; suppress passphrase prompt by passing storepass
keytool -list -v -keystore "$KEYSTORE_PATH" -alias "$KEY_ALIAS" -storepass "$STORE_PASSWORD" | grep "SHA1:" || true

# 7) Optionally install APK to connected device
read -rp "Install the release APK on a connected device now? (y/N): " install_now
if [[ "$install_now" =~ ^[Yy] ]]; then
  if command -v adb >/dev/null 2>&1 && [ -f "$APK_PATH" ]; then
    echo "Installing $APK_PATH via adb..."
    adb install -r "$APK_PATH"
    echo "Installed. Check device."
  else
    echo "adb not found or APK missing. Install platform-tools and ensure adb is available."
  fi
else
  echo "Skipping install."
fi

# 8) Wrap up
echo "Release build helper finished. Keep your keystore backed up in a secure place."
