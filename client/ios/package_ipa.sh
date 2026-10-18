#!/bin/bash
# 在 macOS 上执行：bash package_ipa.sh
# 默认导出未签名 IPA，可交给 AltStore / Sideloadly 使用个人 Apple ID 再签名。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="SmartLedger"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}-ipa.XXXXXX")"
WORK_DIR="$WORK_ROOT/source"
ARCHIVE_PATH="$WORK_ROOT/${PROJECT_NAME}.xcarchive"
DERIVED_DATA="$WORK_ROOT/DerivedData"
PAYLOAD_DIR="$WORK_ROOT/package"
XCODEBUILD_LOG="$WORK_ROOT/xcodebuild.log"
IPA_PATH="$BUILD_DIR/${PROJECT_NAME}-unsigned.ipa"
TEMP_IPA="$WORK_ROOT/${PROJECT_NAME}-unsigned.ipa"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$WORK_DIR" "$PAYLOAD_DIR/Payload"

# 共享目录上的 Xcode workspace 偶发无法读取；只复制源码到独立临时目录，
# 避免把旧 build、缓存和 IPA 再次复制进构建输入。
rsync -a \
  --exclude '/build/' \
  --exclude '/.DS_Store' \
  "$SCRIPT_DIR/" "$WORK_DIR/"

if ! xcodebuild \
  -project "$WORK_DIR/${PROJECT_NAME}.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  archive \
  -archivePath "$ARCHIVE_PATH" >"$XCODEBUILD_LOG" 2>&1; then
  cat "$XCODEBUILD_LOG"
  exit 1
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/${PROJECT_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "归档成功但未找到应用：$APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$PAYLOAD_DIR/Payload/"
(cd "$PAYLOAD_DIR" && /usr/bin/zip -qry "$TEMP_IPA" Payload)
/usr/bin/unzip -tq "$TEMP_IPA"
mv -f "$TEMP_IPA" "$IPA_PATH"

echo ""
echo "IPA 已生成：$IPA_PATH"
echo "说明：这是未签名 IPA；真机安装前请使用 AltStore、Sideloadly 或有效开发者证书签名。"
