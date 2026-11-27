#!/bin/bash
#
# Inject the host-provided attribution domain into the AlignApps SDK privacy
# manifest before the resource bundle is assembled.
#
# The domain can be provided in either of these ways (first match wins):
#   1. ALIGNAPPS_TRACKING_DOMAIN environment variable / Xcode build setting.
#   2. ios/Flutter/AlignappsPrivacyDomain.txt (recommended, one host per app).
#
# The file is resolved relative to the host app's ios directory:
#   $PODS_ROOT/../Flutter/AlignappsPrivacyDomain.txt
#   $PROJECT_DIR/../Flutter/AlignappsPrivacyDomain.txt
#   $SRCROOT/../Flutter/AlignappsPrivacyDomain.txt
#
# The rendered manifest is patched into the already-built
# alignapps_flutter_privacy.bundle before the app embeds it. If that bundle is
# not found (unexpected integration layout), ios/Classes/PrivacyInfo.xcprivacy
# is updated as a fallback for the next build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/PrivacyInfo.xcprivacy.template"
OUTPUT="${SCRIPT_DIR}/Classes/PrivacyInfo.xcprivacy"

log() {
  printf '[AlignApps] %s\n' "$*"
}

fail() {
  printf '[AlignApps][ERROR] %s\n' "$*" >&2
  exit 1
}

read_domain_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" | awk 'NF { print; exit }'
}

DOMAIN="${ALIGNAPPS_TRACKING_DOMAIN:-}"

if [ -z "$DOMAIN" ]; then
  CANDIDATES=()
  [ -n "${PODS_ROOT:-}" ] && CANDIDATES+=("${PODS_ROOT}/../Flutter/AlignappsPrivacyDomain.txt")
  [ -n "${PROJECT_DIR:-}" ] && CANDIDATES+=("${PROJECT_DIR}/../Flutter/AlignappsPrivacyDomain.txt")
  [ -n "${SRCROOT:-}" ] && CANDIDATES+=("${SRCROOT}/../Flutter/AlignappsPrivacyDomain.txt")
  CANDIDATES+=("${SCRIPT_DIR}/../example/ios/Flutter/AlignappsPrivacyDomain.txt")

  for candidate in "${CANDIDATES[@]}"; do
    value="$(read_domain_file "$candidate")"
    if [ -n "$value" ]; then
      DOMAIN="$value"
      break
    fi
  done
fi

if [ -z "$DOMAIN" ]; then
  fail "缺少归因域名。请在宿主 App 的 ios/Flutter/AlignappsPrivacyDomain.txt 写入（例如 trk.example.com），或设置 ALIGNAPPS_TRACKING_DOMAIN。"
fi

DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN%%/*}"

case "$DOMAIN" in
  *" "*|*:*)
    fail "归因域名格式不合法：$DOMAIN。只填写 host，例如 trk.example.com。"
    ;;
esac

if ! printf '%s' "$DOMAIN" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'; then
  fail "归因域名格式不合法：$DOMAIN。只填写 host，例如 trk.example.com。"
fi

[ -f "$TEMPLATE" ] || fail "找不到模板：$TEMPLATE"

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/alignapps-privacy.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

sed "s/__ALIGNAPPS_TRACKING_DOMAIN__/${DOMAIN}/g" "$TEMPLATE" > "$TMP_FILE"

if ! plutil -lint "$TMP_FILE" >/dev/null 2>&1; then
  fail "生成的 PrivacyInfo.xcprivacy 不是合法的 plist"
fi

# The resource bundle target builds before this framework target, so the
# manifest in the built bundle may still be the generic fallback. Patch the
# already-built bundle(s) in place so the app embeds the injected manifest on
# this build.
BUILT_BUNDLES=()
for root in "${CONFIGURATION_BUILD_DIR:-}" "${BUILT_PRODUCTS_DIR:-}"; do
  [ -n "$root" ] || continue
  for dir in "$root"/*/alignapps_flutter_privacy.bundle "$root"/alignapps_flutter_privacy.bundle; do
    if [ -d "$dir" ]; then
      BUILT_BUNDLES+=("$dir")
    fi
  done
done

if [ ${#BUILT_BUNDLES[@]} -eq 0 ]; then
  # Unexpected integration layout. Update the source manifest so the next build
  # can pick it up, and surface the situation in the build log.
  if [ -f "$OUTPUT" ] && cmp -s "$TMP_FILE" "$OUTPUT"; then
    log "未找到已构建的 alignapps_flutter_privacy.bundle，源清单已包含 ${DOMAIN}"
  else
    mkdir -p "$(dirname "$OUTPUT")"
    cp "$TMP_FILE" "$OUTPUT"
    log "未找到已构建的 alignapps_flutter_privacy.bundle，已更新源清单：${DOMAIN} -> ${OUTPUT}"
  fi
else
  for bundle in "${BUILT_BUNDLES[@]}"; do
    target="$bundle/PrivacyInfo.xcprivacy"
    if [ -f "$target" ] && cmp -s "$TMP_FILE" "$target"; then
      log "已构建清单已包含归因域名 ${DOMAIN}：$target"
    else
      cp "$TMP_FILE" "$target"
      log "已注入已构建清单：${DOMAIN} -> $target"
    fi
  done
fi
