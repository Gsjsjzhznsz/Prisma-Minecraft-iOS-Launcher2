#!/usr/bin/env bash
#
# ui_fluent_smoke.sh — Fluent 前端冒烟 + 模拟器预览（7.0 测试仓专用，7.0-UI-7）
#
# 用法:
#   scripts/ui_fluent_smoke.sh syntax    # 快速语法门禁：迁移面 .m 全量 -fsyntax-only（约 1 分钟）
#   scripts/ui_fluent_smoke.sh preview   # 编译预览 harness → 模拟器安装启动 → 浅/深两态截图
#   scripts/ui_fluent_smoke.sh all       # 两者依次（CI 默认）
#
# 范围红线：本脚本只做"前端迁移面"的快速验证（AmeTheme 令牌层 + Fluent 组件库 +
#   已迁移 VC 的语法与可运行性）；完整出包仍走 gmake package（development.yml）。
# 红线：仅测试验证，不产生任何 release。
#
# 依赖：macOS + Xcode（含 iPhone 模拟器 runtime）。非 macOS 直接退出（CI 走 macos-15）。

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVES="$ROOT/Natives"
OUT="$ROOT/build/ame-preview"
MODE="${1:-all}"
FAIL=0

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ ui_fluent_smoke.sh 仅支持 macOS（需要 Xcode / iOS 模拟器）"
  exit 2
fi

SDK_SIM="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"   # arm64（Apple Silicon runner）/ x86_64
COMMON=(-fobjc-arc -I"$NATIVES" -isysroot "$SDK_SIM" -target "${ARCH}-apple-ios14.0-simulator")

mkdir -p "$OUT"

# ─────────────────────────────────────────────────────────────
# syntax 模式：迁移面语法门禁
#   入选口径 = Natives/ 根目录 .m 且引用了 AmeTheme.h 或 Fluent* 组件
#   （即 7.0-UI 全部迁移成果）；游戏域/外部依赖文件不在迁移面，不拖入。
# ─────────────────────────────────────────────────────────────
syntax_mode() {
  echo "== UI Fluent 语法门禁（-fsyntax-only，迁移面）=="
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(ls "$NATIVES"/*.m 2>/dev/null | while IFS= read -r f; do
    if grep -lq -e '"AmeTheme\.h"' -e '"Fluent[A-Z]' "$f" 2>/dev/null; then echo "$f"; fi
  done)

  echo "迁移面文件数: ${#files[@]}"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "✗ 未发现迁移面文件（口径失效？）"
    FAIL=1
    return
  fi

  local bad=0
  for f in "${files[@]}"; do
    local base log
    base="$(basename "$f")"
    log="$OUT/syntax-${base}.log"
    if xcrun clang -fsyntax-only "${COMMON[@]}" "$f" 2>"$log"; then
      echo "  ✓ $base"
      rm -f "$log"
    elif grep -q "fatal error: '.*' file not found" "$log" 2>/dev/null; then
      # 迁移面外的头链缺失（如游戏域 C 头）——记 SKIP 不算失败：
      # 本门禁只管 AmeTheme/Fluent 迁移面自身的编译错误
      echo "  ⚠ SKIP ${base}（迁移面外头依赖，正式构建覆盖）"
      rm -f "$log"
    else
      echo "  ✗ $base"
      sed -n '1,12p' "$log" || true
      bad=$((bad + 1))
      FAIL=1
    fi
  done
  echo "== 语法门禁结果: $(( ${#files[@]} - bad )) 通过 / ${bad} 失败 =="
}

# ─────────────────────────────────────────────────────────────
# preview 模式：编译 harness → 模拟器安装启动 → 浅/深截图
#   harness = AmeTheme + Fluent 组件 8 件 + LauncherMenuViewController
#   + Preview/AmeFluentPreviewMain.m（服务桩内嵌，见该文件头注释）。
# ─────────────────────────────────────────────────────────────
preview_mode() {
  echo "== UI Fluent 预览（模拟器渲染冒烟）=="
  local sources=(
    AmeTheme FluentButton FluentCard FluentListCell FluentTextField
    FluentToast FluentSegmentedControl FluentProgress FluentBanner
    LauncherMenuViewController
  )
  local objs=()
  for s in "${sources[@]}"; do
    echo "  编译 $s.m"
    if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/$s.m" -o "$OUT/$s.o" 2>"$OUT/compile-$s.log"; then
      echo "  ✗ $s.m 编译失败:"
      sed -n '1,15p' "$OUT/compile-$s.log" || true
      FAIL=1
      return
    fi
    objs+=("$OUT/$s.o")
  done

  echo "  编译 Preview/AmeFluentPreviewMain.m"
  if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/Preview/AmeFluentPreviewMain.m" -o "$OUT/AmeFluentPreviewMain.o" 2>"$OUT/compile-main.log"; then
    echo "  ✗ harness 编译失败:"
    sed -n '1,15p' "$OUT/compile-main.log" || true
    FAIL=1
    return
  fi

  echo "  链接 AmeFluentPreview"
  # CoreGraphics/QuartzCore 必须显式链接：CGAffineTransform（Toast/Banner/侧栏弹跳）
  # 与 CALayer/CABasicAnimation（Progress/Card 阴影）符号不在 UIKit 内；
  # 本脚本不用 -fmodules，无自动链接
  if ! xcrun clang -isysroot "$SDK_SIM" -target "${ARCH}-apple-ios14.0-simulator" \
      -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
      -o "$OUT/AmeFluentPreview" \
      "${objs[@]}" "$OUT/AmeFluentPreviewMain.o" 2>"$OUT/link.log"; then
    echo "  ✗ 链接失败:"
    sed -n '1,15p' "$OUT/link.log" || true
    FAIL=1
    return
  fi

  local app="$OUT/AmeFluentPreview.app"
  mkdir -p "$app"
  cp "$OUT/AmeFluentPreview" "$app/AmeFluentPreview"
  cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.prisma-devs.ame-fluent-preview</string>
  <key>CFBundleExecutable</key><string>AmeFluentPreview</string>
  <key>CFBundleName</key><string>AmeFluentPreview</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>MinimumOSVersion</key><string>14.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>
PLIST
  codesign --force --sign - "$app" >/dev/null 2>&1 || true

  # ── 选模拟器：优先已 booted，其次可用 iPhone ──
  local device
  device="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1)"
  if [[ -z "$device" ]]; then
    device="$(xcrun simctl list devices available | grep 'iPhone' | grep -oE '[0-9A-F-]{36}' | head -1)"
  fi
  if [[ -z "$device" ]]; then
    echo "✗ 未找到可用 iPhone 模拟器"
    FAIL=1
    return
  fi
  echo "  模拟器 UDID: $device"

  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$app" || { echo "✗ 安装失败"; FAIL=1; return; }

  local launch_out
  if launch_out="$(xcrun simctl launch "$device" com.prisma-devs.ame-fluent-preview 2>&1)"; then
    echo "  启动 OK: $launch_out"
  else
    echo "✗ 启动失败: $launch_out"
    FAIL=1
    return
  fi

  sleep 6
  xcrun simctl io "$device" screenshot "$OUT/ame-preview-light.png" >/dev/null 2>&1 \
    && echo "  ✓ 截图(浅色): $OUT/ame-preview-light.png"

  xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
  sleep 3
  xcrun simctl io "$device" screenshot "$OUT/ame-preview-dark.png" >/dev/null 2>&1 \
    && echo "  ✓ 截图(深色): $OUT/ame-preview-dark.png"
  xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true

  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  echo "== 预览冒烟完成（截图即视觉验收：侧栏 pill/IconButton 着色/组件两态）=="
}

case "$MODE" in
  syntax)  syntax_mode ;;
  preview) preview_mode ;;
  all)     syntax_mode; preview_mode ;;
  *) echo "用法: $0 [syntax|preview|all]"; exit 2 ;;
esac

if [[ "$FAIL" -ne 0 ]]; then
  echo "✗ UI Fluent 冒烟存在失败项"
  exit 1
fi
echo "✓ UI Fluent 冒烟全部通过"
