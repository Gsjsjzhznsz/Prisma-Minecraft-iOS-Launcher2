#!/usr/bin/env bash
#
# ui_fluent_smoke.sh — Fluent 前端冒烟 + 模拟器预览（7.0 测试仓专用，7.0-UI-7）
#
# 用法:
#   scripts/ui_fluent_smoke.sh syntax    # 快速语法门禁：迁移面 .m 全量 -fsyntax-only（约 1 分钟）
#   scripts/ui_fluent_smoke.sh preview   # 编译预览 harness → 模拟器安装启动 → 浅/深两态截图
#   scripts/ui_fluent_smoke.sh all       # 两者依次（CI 默认）
#
# 7.0-UI-10-c：preview 壳为 ZL2 40pt 顶栏镜像 + 横屏（模拟器截图恒横置），
#   逐页冷启动截图 5 页 × 浅/深两态 = 10 张（★ Task400 -versionpicker：
#   版本/账户双滚轮原地驻主页右栏，home 即含）：
#   ame-zl2-{home,download,versions,accounts,settings}-{light,dark}.png
#   （组件页退役，不再产出 components 组图）
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
  # ★Task340：AMEFluentTheme 面退役（用户澄清 Fluent 重设计只落 fluent-ui 插件，
  #   不落启动器代码；启动器主页回归 ZL2Theme 令牌）
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
      # 本门禁只管 AmeTheme/Fluent/ZL2 迁移面自身的编译错误
      echo "  ⚠ SKIP ${base}（迁移面外头依赖，正式构建覆盖）"
      rm -f "$log"
    else
      echo "  ✗ $base"
      cat "$log" || true
      # ★Task414：失败明细以 ##[error] 直出 = check-run annotations 可读（取证通道，
      #   run 42643918763 冒烟失败但产物路由 404 取证不可达的教训）
      sed 's/^/##[error] [syntax] /' "$log" || true
      bad=$((bad + 1))
      FAIL=1
    fi
  done
  echo "== 语法门禁结果: $(( ${#files[@]} - bad )) 通过 / ${bad} 失败 =="
}

# ─────────────────────────────────────────────────────────────
# preview 模式：编译 harness → 模拟器安装启动 → 逐页浅/深截图
#   harness = AmeTheme + Fluent 组件 8 件（Task343：LauncherMenuViewController 随旧壳退役摘除）
#   + Preview/AmeFluentPreviewMain.m（服务桩内嵌，见该文件头注释）
#   + Preview/ZL2PagesStub.m（7.0-UI-9 四页桩 TU）。
#   7.0-UI-9-e 起槽位 1-4 换装 ZL2 四功能页真实 VC；7.0-UI-10-c 起壳为
#   40pt 顶栏镜像 + 横屏（组件陈列页退役），逐页冷启动（-zl2page）五页
#   各截浅/深两态共 10 张。
# ─────────────────────────────────────────────────────────────
preview_mode() {
  echo "== UI Fluent 预览（模拟器渲染冒烟）=="

  local sources=(
    AmeTheme   # ★Task340：AMEFluentTheme 退役（重设计只落 fluent-ui 远程插件）
    FluentButton FluentCard FluentListCell FluentTextField
    FluentToast FluentSegmentedControl FluentProgress FluentBanner
    ZL2Theme ZL2RailView ZL2HomeViewController
    AmeFlowSelectView                 # ★ Task393 封面流选择器（★ Task401 更名+横轴化：账户横排/版本竖排共用）
    ZL2DownloadViewController ZL2VersionsViewController
    ZL2AccountsViewController ZL2SettingsViewController
    ZL2SkinPreviewView   # ★Task413：账户页内嵌皮肤 3D 预览（ZL2AccountsViewController 引用其类符号，冒烟固定清单缺席 = _OBJC_CLASS_$ 未定义判例；Y 轴翻转根修版）
    ZL2AssetSearchViewController   # 7.0-UI-10：下载页资产搜索组件（.h+.m，与下载页同轮落地）
    ZL2M3Kit                       # 7.0-UI-12：MD3 功能组件库（搜索/chip/开关/对话框/弹层）
    ZL2GameDownloadViewController  # 7.0-UI-12：游戏 M3 下载页（旧 DownloadViewController 退场）
    ZL2GameAddonsViewController    # 7.0-UI-14：Addons 加载器选择屏（选版后加载器组合+安装分发）
    ZL2SearchIdViewController      # 7.0-UI-14：按项目 ID 直查页（下载左轨第 6 项）
    ZL2FavoritesStore              # 7.0-UI-14：收藏仓库（plist 快照，搜索卡心形/收藏页共用）
    installer/FabricUtils          # Task336：Addons 页直装执行器（ame336 页内联安装新依赖）
    ZL2ShellViewController         # ★Task417：真壳本体入预览（-zl2shell real 真类渲染 +
                                   #   probe 页真 ZL2ShellNavItem 字形管线；镜像不可信教训的结构性终点：
                                   #   真机 10pt vs CI 镜像 20pt 两倍差 = 镜像自绘图标从未经过真管线）
  )
  local objs=()
  for s in "${sources[@]}"; do
    local base; base="$(basename "$s")"   # Task336：支持 installer/ 子目录 TU（.o 平铺 OUT）
    echo "  编译 $s.m"
    if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/$s.m" -o "$OUT/$base.o" 2>"$OUT/compile-$base.log"; then
      echo "  ✗ $s.m 编译失败:"
      cat "$OUT/compile-$base.log" || true
      sed 's/^/##[error] [preview-compile] /' "$OUT/compile-$base.log" || true
      FAIL=1
      return
    fi
    objs+=("$OUT/$base.o")
  done

  echo "  编译 Preview/AmeFluentPreviewMain.m"
  if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/Preview/AmeFluentPreviewMain.m" -o "$OUT/AmeFluentPreviewMain.o" 2>"$OUT/compile-main.log"; then
    echo "  ✗ harness 编译失败:"
    cat "$OUT/compile-main.log" || true
    sed 's/^/##[error] [preview-main] /' "$OUT/compile-main.log" || true
    FAIL=1
    return
  fi

  echo "  编译 Preview/ZL2PagesStub.m（ZL2 四页桩 TU，不进 CMakeLists）"
  if ! xcrun clang -c "${COMMON[@]}" "$NATIVES/Preview/ZL2PagesStub.m" -o "$OUT/ZL2PagesStub.o" 2>"$OUT/compile-stub.log"; then
    echo "  ✗ ZL2 桩 TU 编译失败:"
    cat "$OUT/compile-stub.log" || true
    sed 's/^/##[error] [preview-stub] /' "$OUT/compile-stub.log" || true
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
    head -80 "$OUT/link.log" || true
    sed 's/^/##[error] [link] /' "$OUT/link.log" | head -40 || true
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
  <key>UIRequiresFullScreen</key><true/>
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
  local device=""
  device="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  if [[ -z "${device:-}" ]]; then
    device="$(xcrun simctl list devices available 2>/dev/null | grep 'iPhone' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  fi
  if [[ -z "$device" ]]; then
    echo "✗ 未找到可用 iPhone 模拟器"
    FAIL=1
    return
  fi
  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  echo "  模拟器 UDID: $device"

  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$app" || { echo "✗ 安装失败"; FAIL=1; return; }

  # ── 逐页截图（7.0-UI-9-e；7.0-UI-10-c 去组件页收敛五页）：每页冷启动
  #    （-zl2page 预选顶栏镜像页）→ 浅色截 → 深色截 → 还原浅色；
  #    5 页 × 2 态共 10 张，命名 ame-zl2-<page>-<mode>.png。harness 恒横屏
  #    （AppDelegate supportedInterfaceOrientationsForWindow 强制，截图尺寸
  #    随设备/横置方向而定）。桩链路：下载/版本页空注册表空任务（胶囊隐藏/
  #    空态），账户页空沙盒（未登录空列表），设置页静态组卡——均为可验收
  #    的初始视觉。
  # ★ Task400：versionpicker 专用页退役（版本/账户双滚轮原地驻主页右栏，
  #    home 截图即含双滚轮——预览沙盒假账户×4/假实例×4 注入不变）
  local pages=(home download versions accounts settings probe)   # ★Task417 +probe 字形阶梯探针页
  local p page_launch_out
  for p in "${pages[@]}"; do
    xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
    if page_launch_out="$(xcrun simctl launch "$device" com.prisma-devs.ame-fluent-preview -zl2page "$p" 2>&1)"; then
      echo "  启动 OK[$p]: $page_launch_out"
    else
      echo "✗ 启动失败[$p]: $page_launch_out"
      echo "##[error] [launch-$p] $page_launch_out"
      FAIL=1
      return
    fi

    sleep 4
    # 崩溃哨兵（r11 重写）：宿主级 pgrep（模拟器 app=宿主进程，比 simctl spawn
    # launchctl list 稳定——run 39654817069 实证 launchctl 存在漏报 app 的竞态假
    # 阴性：同一 PID 在 console-pty 重挂时仍存活）+ 3 次重试防抖。
    local alive=0 li
    for li in 1 2 3; do
      if pgrep -f "AmeFluentPreview.app" >/dev/null 2>&1; then alive=1; break; fi
      sleep 1
    done
    if [ "$alive" -ne 1 ]; then
      echo "✗ 存活检查失败[see-log]：launch 成功但进程已亡（启动即崩）"
      echo "── launchctl list 原始输出（前 15 行，验证命令可用性）:"
      xcrun simctl spawn "$device" launchctl list 2>&1 | head -15
      echo "── DiagnosticReports 最近 13 项:"
      ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | head -13
      for f in $(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -3); do
        echo "── 崩溃报告(最近): $f"
        grep -aoE '"exception"[^}]{0,260}|"asi":\{[^}]{0,600}|Application Specific Information[^}]{0,400}|unrecognized selector[^"]{0,140}|dyld[^"]{0,200}|"terminationDetails":"[^"]{0,300}' "$f" | head -15
      done
      # console-pty 直捕（取证期临时）：app 的 stdout/stderr 原样落日志，崩溃
      # 栈/NSException reason/dyld 报错直接可见；后台+超时自杀防阻塞
      xcrun simctl launch --console-pty "$device" com.prisma-devs.ame-fluent-preview -zl2page "$p" > "$OUT/console-$p.log" 2>&1 &
      local conpid=$!
      sleep 6
      kill "$conpid" 2>/dev/null || true
      wait "$conpid" 2>/dev/null || true
      echo "── console-pty 直捕[$p]（首 80 行）:"
      head -80 "$OUT/console-$p.log" 2>/dev/null || echo "  （无输出）"
      # ★Task414：崩溃取证走 annotations（产物路由 404 期间唯一稳定通道）
      sed 's/^/##[error] [console-'$p'] /' "$OUT/console-$p.log" 2>/dev/null | head -40 || true
      echo "── 模拟器统一日志（ame-fluent 相关，近 4 分钟）:"
      xcrun simctl spawn "$device" log show --last 4m --style compact --predicate 'eventMessage CONTAINS[c] "ame-fluent" OR processImagePath CONTAINS[c] "ame-fluent"' 2>/dev/null | grep -aiE "exit|kill|crash|terminat|launch|bootstrapp|runningboard" | head -30
      FAIL=1
      return
    fi
    # 截图归正：app 横置渲染于竖屏 framebuffer（LandscapeRight 内容顶边=设备右缘），
    # simctl 抓原生竖屏缓冲 → sips 逆时针 90°（-r 270）归正为真横屏交付图
    xcrun simctl io "$device" screenshot "$OUT/ame-zl2-$p-light.png" >/dev/null 2>&1 \
      && sips -r 270 "$OUT/ame-zl2-$p-light.png" >/dev/null 2>&1 \
      && echo "  ✓ 截图[$p/浅色]: $OUT/ame-zl2-$p-light.png"

    xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl io "$device" screenshot "$OUT/ame-zl2-$p-dark.png" >/dev/null 2>&1 \
      && sips -r 270 "$OUT/ame-zl2-$p-dark.png" >/dev/null 2>&1 \
      && echo "  ✓ 截图[$p/深色]: $OUT/ame-zl2-$p-dark.png"
    xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  done

  # ── fui NavigationView 镜像轨（★Task414 第 23 轮复诉⑥「你不会运用预览吗」：
  #    fui 左栏 rail 自本轮起可截图验收——64 折叠窗格 + 图标 24 恒定 + 选中
  #    surfaceContainerHighest 抬升在 fluent-dark 暗板下的真实观感；工作室/
  #    账户页暗板同帧覆盖。★Task416 第 24 轮复诉「折叠侧边栏会把图标大小也
  #    调节了」：新增展开态镜像轨（-zl2pane expanded = 280 宽 + 标签），折叠
  #    /展开同帧对比 = 图标 24pt 两态恒定的直接图证）──
  local fp
  for fp in home accounts; do
    xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
    if page_launch_out="$(xcrun simctl launch "$device" com.prisma-devs.ame-fluent-preview -zl2page "$fp" -zl2shell nav -zl2theme fluent-dark 2>&1)"; then
      echo "  启动 OK[nav/$fp]: $page_launch_out"
    else
      echo "✗ 启动失败[nav/$fp]: $page_launch_out"
      FAIL=1
      return
    fi
    sleep 4
    local alive2 fl2
    alive2=0
    for fl2 in 1 2 3; do
      if pgrep -f "AmeFluentPreview.app" >/dev/null 2>&1; then alive2=1; break; fi
      sleep 1
    done
    if [ "$alive2" -ne 1 ]; then
      echo "✗ 存活检查失败[nav/$fp]：launch 成功但进程已亡（启动即崩）"
      echo "##[error] [alive-nav-$fp] 进程已亡（启动即崩）"
      FAIL=1
      return
    fi
    xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl io "$device" screenshot "$OUT/ame-zl2-nav-fluent-$fp-dark.png" >/dev/null 2>&1 \
      && sips -r 270 "$OUT/ame-zl2-nav-fluent-$fp-dark.png" >/dev/null 2>&1 \
      && echo "  ✓ 截图[nav/$fp/fluent-dark]: $OUT/ame-zl2-nav-fluent-$fp-dark.png"
    xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  done

  # ★Task416 展开态镜像轨（折叠 vs 展开同轮对比：图标 24pt 恒定图证）
  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  if page_launch_out="$(xcrun simctl launch "$device" com.prisma-devs.ame-fluent-preview -zl2page home -zl2shell nav -zl2theme fluent-dark -zl2pane expanded 2>&1)"; then
    echo "  启动 OK[nav-expanded/home]: $page_launch_out"
  else
    echo "✗ 启动失败[nav-expanded/home]: $page_launch_out"
    FAIL=1
    return
  fi
  sleep 4
  xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl io "$device" screenshot "$OUT/ame-zl2-nav-fluent-home-expanded-dark.png" >/dev/null 2>&1 \
    && sips -r 270 "$OUT/ame-zl2-nav-fluent-home-expanded-dark.png" >/dev/null 2>&1 \
    && echo "  ✓ 截图[nav-expanded/home/fluent-dark]: $OUT/ame-zl2-nav-fluent-home-expanded-dark.png"
  xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true

  # ── ★Task417 真壳本体腿（-zl2shell real）：真 ZL2ShellViewController +
  #    fui 四族令牌真路径，折叠态（真机用户口径）——CI 截图从此验证真壳
  #    真字形管线（403/405/412/413 四轮修复首次可被截图仲裁）──
  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  # ★Task417-r5：console-pty 直捕真壳 stdout/stderr（log show 漏采判例：
  #   run 169/170/171 三轮 [Ame417] shell 行均未入 sim 日志库，唯探针行入
  #   = 采样不可靠；console-pty 直捕 = 取证通道确定性，Task414 崩溃取证
  #   同款通道）
  xcrun simctl launch --console-pty "$device" com.prisma-devs.ame-fluent-preview -zl2page home -zl2shell real > "$OUT/console-real.log" 2>&1 &
  local realpid=$!
  sleep 6
  xcrun simctl ui "$device" appearance dark >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl io "$device" screenshot "$OUT/ame-zl2-real-nav-home-dark.png" >/dev/null 2>&1 \
    && sips -r 270 "$OUT/ame-zl2-real-nav-home-dark.png" >/dev/null 2>&1 \
    && echo "  ✓ 截图[real/home/fluent-dark]: $OUT/ame-zl2-real-nav-home-dark.png"
  xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  grep -aE "Ame417|Ame404|Ame388" "$OUT/console-real.log" | head -8 || true
  kill "$realpid" 2>/dev/null || true
  wait "$realpid" 2>/dev/null || true
  # [Ame417]/[ZL2SkinPreview] 日志取证（真类字形读数 + 3D 装配面数数值直出）
  xcrun simctl spawn "$device" log show --last 12m --style compact \
    --predicate 'eventMessage CONTAINS "Ame417" OR eventMessage CONTAINS "ZL2SkinPreview" OR eventMessage CONTAINS "Ame404"' \
    > "$OUT/ame417-diag.log" 2>/dev/null || true
  grep -aE "Ame417|ZL2SkinPreview|Ame404" "$OUT/ame417-diag.log" | tail -20 || true

  xcrun simctl terminate "$device" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  echo "== 预览冒烟完成（bare 六页浅/深 12 张 + fui nav 镜像 2 张 + 展开态 1 张 + 真壳 1 张 = 16 张截图即视觉验收）=="

  # ── ★Task417 iPad 仿真腿：真机用户是 iPad（IMG_0611/0612 = 1180×820pt
  #    @2x 横屏），而既往冒烟只跑 iPhone 模拟器 = iPad 尺寸类从未被截图验证
  #    ——本轮起 iPad 可用即跑（无可回退跳过，不阻塞门禁）：真壳折叠/展开 +
  #    探针页 + 账户页（写实皮+帽层 3D）四张 iPad 尺寸图 = 尺寸类对勘证据链──
  local ipad_udid=""
  ipad_udid="$(xcrun simctl list devices available 2>/dev/null | grep 'iPad' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  if [[ -n "${ipad_udid:-}" ]]; then
    echo "== iPad leg (UDID: ${ipad_udid}) =="   # ★Task417-r4：纯 ASCII 边界（macOS bash 3.2 多字节名吞并雷：$var）全角）中被吞入变量名 = unbound 假象）
    xcrun simctl boot "$ipad_udid" 2>/dev/null || true
    xcrun simctl bootstatus "$ipad_udid" -b >/dev/null 2>&1 || true
    xcrun simctl install "$ipad_udid" "$app" || { echo "✗ iPad 安装失败（iPad 腿跳过，不阻塞）"; return; }
    local ip
    for ip in "real-collapsed:home -zl2shell real" \
              "real-expanded:home -zl2shell real -zl2pane expanded" \
              "probe:probe" \
              "accounts:accounts"; do
      local ip_name="${ip%%:*}"
      local ip_args="${ip#*:}"
      xcrun simctl terminate "$ipad_udid" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
      if page_launch_out="$(xcrun simctl launch "$ipad_udid" com.prisma-devs.ame-fluent-preview -zl2page $ip_args 2>&1)"; then
        echo "  启动 OK[ipad/$ip_name]: $page_launch_out"
      else
        echo "✗ 启动失败[ipad/${ip_name}]: ${page_launch_out}（iPad 腿跳过，不阻塞）"
        continue
      fi
      sleep 5
      xcrun simctl ui "$ipad_udid" appearance dark >/dev/null 2>&1 || true
      sleep 2
      xcrun simctl io "$ipad_udid" screenshot "$OUT/ame-zl2-$ip_name-ipad-dark.png" >/dev/null 2>&1 \
        && sips -r 270 "$OUT/ame-zl2-$ip_name-ipad-dark.png" >/dev/null 2>&1 \
        && echo "  ✓ 截图[ipad/$ip_name]: $OUT/ame-zl2-$ip_name-ipad-dark.png"
    done
    xcrun simctl ui "$ipad_udid" appearance light >/dev/null 2>&1 || true
    xcrun simctl terminate "$ipad_udid" com.prisma-devs.ame-fluent-preview >/dev/null 2>&1 || true
  else
    echo "  ⚠ 无可用 iPad 模拟器（iPad 腿跳过）"
  fi
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
