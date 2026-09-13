#!/bin/bash
# 在 macOS 上执行：bash package_ipa.sh
# 默认导出未签名 IPA，可交给 AltStore / Sideloadly 使用个人 Apple ID 再签名。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="SmartLedger"
BUILD_DIR="$SCRIPT_DIR/build"
WORK_DIR="/tmp/${PROJECT_NAME}-ipa-source"
ARCHIVE_PATH="/tmp/${PROJECT_NAME}-unsigned.xcarchive"
DERIVED_DATA="/tmp/${PROJECT_NAME}-ipa-derived-data"
PAYLOAD_DIR="/tmp/${PROJECT_NAME}-ipa-payload"
IPA_PATH="$BUILD_DIR/${PROJECT_NAME}-unsigned.ipa"

rm -rf "$WORK_DIR" "$ARCHIVE_PATH" "$DERIVED_DATA" "$PAYLOAD_DIR"
mkdir -p "$BUILD_DIR" "$PAYLOAD_DIR/Payload"

# 共享目录上的 Xcode workspace 偶发无法读取；复制到本机 /tmp 后构建更稳定。
ditto "$SCRIPT_DIR" "$WORK_DIR"

xcodebuild \
  -project "$WORK_DIR/${PROJECT_NAME}.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  archive \
  -archivePath "$ARCHIVE_PATH"

cp -R "$ARCHIVE_PATH/Products/Applications/${PROJECT_NAME}.app" "$PAYLOAD_DIR/Payload/"
rm -f "$IPA_PATH"
(cd "$PAYLOAD_DIR" && /usr/bin/zip -qry "$IPA_PATH" Payload)

echo ""
echo "IPA 已生成：$IPA_PATH"
echo "说明：这是未签名 IPA；真机安装前请使用 AltStore、Sideloadly 或有效开发者证书签名。"
