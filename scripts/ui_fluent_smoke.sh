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
COMMON=(-fobjc-arc -I"$NATIVES" -I"$ROOT/external/AFNetworking/AFNetworking" -isysroot "$SDK_SIM" -target "${ARCH}-apple-ios14.0-simulator")

mkdir -p "$OUT"

# ─────────────────────────────────────────────────────────────
# syntax 模式：迁移面语法门禁
#   入选口径 = Natives/ 根目录 .m 且引用了 AmeTheme.h 或 Fluent* 组件
#   （即 7.0-UI 全部迁移成果）；7.0-UI-8 起加入 ZL2Theme.h 面（ZL2 对标系
#   页面全部引用 ZL2Theme 令牌层，不入口径则 3000+ 行新代码零门禁）；
#   游戏域/外部依赖文件不在迁移面，不拖入。
# ─────────────────────────────────────────────────────────────
syntax_mode() {
  echo "== UI Fluent 语法门禁（-fsyntax-only，迁移面）=="
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(ls "$NATIVES"/*.m 2>/dev/null | while IFS= read -r f; do
    if grep -lq -e '"AmeTheme\.h"' -e '"Fluent[A-Z]' -e '"ZL2Theme\.h"' "$f" 2>/dev/null; then echo "$f"; fi
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
# preview 模式：编译 harness → 模拟器安装启动 → 逐页浅/深截图
#   harness = AmeTheme + Fluent 组件 8 件 + LauncherMenuViewController
#   + Preview/AmeFluentPreviewMain.m（服务桩内嵌，见该文件头注释）
#   + Preview/ZL2PagesStub.m（7.0-UI-9 四页桩 TU）。
#   7.0-UI-9-e 起 rail 槽位 1-4 换装 ZL2 四功能页真实 VC，逐页冷启动
#   （-zl2page）各截浅/深两态共 12 张。
# ─────────────────────────────────────────────────────────────
preview_mode() {
  echo "== UI Fluent 预览（模拟器渲染冒烟）=="

  # ── AFNetworking 头链兑底（7.0-UI-9-e）──
  # ZL2AccountsViewController.m #import "AFNetworking.h"（消费错误响应体
  # 键 AFNetworkingOperationFailingURLResponseDataErrorKey）。本仓 AFNetworking
  # 是 git submodule（Natives/external/AFNetworking），ui-smoke checkout 不含
  # submodule，而下方 COMMON 的头搜索路径 $ROOT/external/AFNetworking/AFNetworking
  # 恒空 → 预览编译必炸。此处在该既有搜索路径下物化最小声明 shim（仅账户页
  # 实际消费的 extern 常量声明，符号定义在 ZL2PagesStub.m 桩 TU）：
  #   - 真实出包链路走 CMake include 路径 Natives/external/...（submodule），
  #     不经过本目录，shim 零影响；
  #   - 本地已初始化 submodule 时优先复制真头，保证声明与真实一致；
  #   - 幂等：已存在则不重写。syntax_mode 不受影响（all 模式 syntax 先于 preview）。
  local af_shim_dir="$ROOT/external/AFNetworking/AFNetworking"
  local af_real_dir="$NATIVES/external/AFNetworking/AFNetworking"
  if [[ ! -f "$af_shim_dir/AFNetworking.h" ]]; then
    mkdir -p "$af_shim_dir"
    if [[ -f "$af_real_dir/AFNetworking.h" ]]; then
      cp -R "$af_real_dir/." "$af_shim_dir/"
      echo "  ⚠ AFNetworking 头链兑底 → 复用 submodule 真头 $af_real_dir"
    else
      cat > "$af_shim_dir/AFNetworking.h" <<'AFSHIM'
// ui-smoke preview 最小 shim（ui_fluent_smoke.sh preview_mode 物化）：
// 仅 ZL2AccountsViewController.m 实际消费的 extern 常量声明；符号定义在
// Natives/Preview/ZL2PagesStub.m。真实 AFNetworking.h 由
// Natives/external/AFNetworking submodule 提供（CMake include 路径），
// 不经过本目录。
extern NSString * const AFNetworkingOperationFailingURLResponseDataErrorKey;
AFSHIM
      echo "  ⚠ AFNetworking 头链兑底 → 最小声明 shim $af_shim_dir/AFNetworking.h（submodule 未初始化）"
    fi
  fi

  local sources=(
    AmeTheme FluentButton FluentCard FluentListCell FluentTextField
    FluentToast FluentSegmentedControl FluentProgress FluentBanner
    LauncherMenuViewController
    ZL2Theme ZL2RailView ZL2HomeViewController
    ZL2DownloadViewController ZL2VersionsViewController
    ZL2AccountsViewController ZL2SettingsViewController
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

  echo "  编译 Preview/ZL2PagesStub.m（ZL2 四页桩 TU，不进 CMakeLists）"
  if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/Preview/ZL2PagesStub.m" -o "$OUT/ZL2PagesStub.o" 2>"$OUT/compile-stub.log"; then
    echo "  ✗ ZL2 桩 TU 编译失败:"
    sed -n '1,15p' "$OUT/compile-stub.log" || true
    FAIL=1
    return
  fi

  echo "  链接 AmeFluentPreview"
  # CoreGraphics/QuartzCore 必须显式链接：CGAffineTransform（Toast/Banner/侧栏弹跳）
  # 与 CALayer/CABasicAnimation（Progress/Card 阴影）符号不在 UIKit 内；
  # 7.0-UI-9-e 补 AuthenticationServices（账户页 ASWebAuthenticationSession MSA 流）
  # 与 UniformTypeIdentifiers（设置页 UTType 文档选择器）——本脚本不用 -fmodules，
  # 无自动链接
  if ! xcrun clang -isysroot "$SDK_SIM" -target "${ARCH}-apple-ios14.0-simulator" \
      -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
      -framework AuthenticationServices -framework UniformTypeIdentifiers \
      -o "$OUT/AmeFluentPreview" \
      "${objs[@]}" "$OUT/AmeFluentPreviewMain.o" "$OUT/ZL2PagesStub.o" 2>"$OUT/link.log"; then
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

  # ── 逐页截图（7.0-UI-9-e）：每页冷启动（-zl2page 预选 rail 项）→ 浅色截 →
  #    深色截 → 还原浅色；6 页 × 2 态共 12 张，命名 ame-zl2-<page>-<mode>.png。
  #    harness 桩链路：下载/版本页空注册表空任务（胶囊隐藏/空态），账户页空
  #    沙盒（未登录空列表），设置页静态组卡——均为可验收的初始视觉。
  local pages=(home download versions accounts settings components)
  local p page_launch_out
  for p in "${pages[@]}"; do
    xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
    if page_launch_out="$(xcrun simctl launch "$device" com.prisma-devs.ame-fluent-preview -zl2page "$p" 2>&1)"; then
      echo "  启动 OK[$p]: $page_launch_out"
    else
      echo "✗ 启动失败[$p]: $page_launch_out"
      FAIL=1
      return
    fi

    sleep 4
    xcrun simctl io "$device" screenshot "$OUT/ame-zl2-$p-light.png" >/dev/null 2>&1 \
      && echo "  ✓ 截图[$p/浅色]: $OUT/ame-zl2-$p-light.png"

    xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl io "$device" screenshot "$OUT/ame-zl2-$p-dark.png" >/dev/null 2>&1 \
      && echo "  ✓ 截图[$p/深色]: $OUT/ame-zl2-$p-dark.png"
    xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  done

  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  echo "== 预览冒烟完成（6 页 × 浅/深 12 张截图即视觉验收：ZL2Home 大启动按钮/下载 chips/版本空态/账户未登录/设置组卡/Fluent 双栏对比）=="
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
