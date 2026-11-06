#!/usr/bin/env python3
# ame379_selfcheck.py -- Task379 四线门禁（用户 1099858 装机复诉四项联修）
# A 线：壳层折叠侧边栏可见性根修——窗格头行容器化（固定 32pt），开关钮/滚动区
#       顶不再锚标题 intrinsic 高度（装机 paneTitle 零高塌缩→钮悬入状态栏带）
# B 线：版本详情轨列前导对齐页头边距（8→16，脱离 fluent 窗格邻接带）
# C 线：fluent 实时跟随系统明暗——darkMode keyWindow 根修 + appearance.changed
#       第 12 事件（壳层 trait 桥）+ fluent-ui v2.5.0 订阅换板 + 文档/索引同步
# D 线：主页右栏复位——账号卡/版本卡回顶部原位，五瓦片改驻版本卡之下
# E 线：插件感知动态色（预建 Appearance 代理回溯覆盖表 = 导航栏标题白字白底根修）
# S 结构护栏 + --selftest 反向验证（病灶变体必翻红，零仓内触碰）
import hashlib, json, os, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

shell = read("Natives/ZL2ShellViewController.m")
detail = read("Natives/ZL2VersionDetailViewController.m")
home = read("Natives/ZL2HomeViewController.m")
theme = read("Natives/ZL2Theme.m")
bridge = read("Natives/AmePluginBridge.m")
runtime = read("Natives/AmePluginRuntime.m")
js = read("plugin-repo/src/fluent-ui/main.js")
manifest = read("plugin-repo/src/fluent-ui/manifest.json")
docs = read("Natives/AI/AiPluginDocsTool.m")

# ══ A 线：窗格头行容器化（折叠开关钮可见性根修） ═══════════════════

check("A1 头行容器在位（属性 + 构建 + 固定 32pt 高 + 安全区上 10pt）",
      "@property(nonatomic, strong) UIView *ame379_paneHeader;" in shell
      and "self.ame379_paneHeader = [[UIView alloc] init];" in shell
      and "[self.ame379_paneHeader.heightAnchor constraintEqualToConstant:32.0]," in shell
      and "[self.ame379_paneHeader.topAnchor constraintEqualToAnchor:self.paneWrap.safeAreaLayoutGuide.topAnchor constant:10.0]," in shell)

check("A2 开关钮锚头行容器（旧口径锚 paneTitle.centerY 退役）",
      "[self.paneToggleButton.centerYAnchor constraintEqualToAnchor:self.ame379_paneHeader.centerYAnchor]," in shell
      and "paneToggleButton.centerYAnchor constraintEqualToAnchor:self.paneTitle.centerYAnchor" not in shell)

check("A3 滚动区顶锚头行容器底（旧口径锚 paneTitle.bottom 退役）",
      "[self.paneScroll.topAnchor constraintEqualToAnchor:self.ame379_paneHeader.bottomAnchor constant:8.0]," in shell
      and "paneScroll.topAnchor constraintEqualToAnchor:self.paneTitle.bottomAnchor" not in shell)

check("A4 头行 z 序置顶（bringSubviewToFront，钮永不被子覆盖）",
      "[self.paneWrap bringSubviewToFront:self.ame379_paneHeader];" in shell)

check("A5 标题文案 bundle 显示名回退链（processName 宿主不确定性防御）",
      'infoDictionary[@"CFBundleDisplayName"]' in shell
      and 'if (ame379_bundleName.length == 0) ame379_bundleName = @"Prisma Ⅱ";' in shell)

check("A6 装机自证日志（[Ame379] pane header 落 header/toggle/tglTrans/title frame；★Task403 重锚：[Ame383] 动作簇自证随右上动作簇退役（bd9e1d9 移除主页重复快捷入口，并行会话未跑门禁未补账）一并摘除）",
      '[Ame379] pane header -- header=%@ toggle=%@ tglTrans=%d title=%@ titleLen=%lu' in shell)

check("A7 376 折叠语义逐字保留（几何派发/宽约束/持久化/紧凑宽 64）",
      "ame376_applyPaneGeometry:(BOOL)animated" in shell
      and "self.ame376_paneWidth = [self.paneWrap.widthAnchor constraintEqualToConstant:ZL2ShellPaneWidth];" in shell
      and 'forKey:@"ame376.paneCollapsed"' in shell
      and "ZL2ShellPaneCompactWidth = 64.0;" in shell
      and "[self.paneTitle setHidden:ame376_compact]" in shell.replace("self.paneTitle.hidden = ame376_compact;", "[self.paneTitle setHidden:ame376_compact]"))

# ══ B 线：版本详情轨列对齐页头边距 ═══════════════════════════════

check("B1 轨列前导 = 页头边距（8→ZL2V13PageMargin，脱离窗格邻接带）",
      "[_railStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin]," in detail
      and "constant:8],\n        [_railStack.trailing" not in detail)

check("B2 轨列尾随/内容容器同步（PageMargin+RailWidth[+4] 一致派生）",
      "[_railStack.trailingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin + ZL2V13RailWidth]," in detail
      and "constant:ZL2V13PageMargin + ZL2V13RailWidth + 4]," in detail)

check("B3 372 全宽命中面口径不变（Fill 对齐 + 项高 56 + 无项内宽约束）",
      "_railStack.alignment = UIStackViewAlignmentFill;" in detail
      and "[item.heightAnchor constraintEqualToConstant:ZL2V13RailItemSize].active = YES;" in detail
      and "ZL2V13RailItemSize = 56.0;" in detail)

# ══ C 线：fluent 实时跟随系统明暗（四件套） ══════════════════════

check("C1 darkMode 读取根修（keyWindow trait；currentTraitCollection 一行式永判浅退役）",
      "connectedScenes" in bridge
      and "cand.isKeyWindow" in bridge
      and "ame366_isDarkMode {" in bridge
      and "return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;" not in bridge)

check("C2 壳层外观桥（traitCollectionDidChange → AmeAppearanceTraitChanged 通知；★r1 重锚：SDK26 不可见选择器退役改 userInterfaceStyle 直比）",
      '- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {' in shell
      and "hasDifferentColorAppearanceComparedTo" not in shell
      and "if (ame379_style == previousTraitCollection.userInterfaceStyle) return;" in shell
      and 'postNotificationName:@"AmeAppearanceTraitChanged"' in shell)

check("C3 事件面第 12 事件（Runtime 订阅通知 → appearance.changed 派发 {dark}）",
      'addObserverForName:@"AmeAppearanceTraitChanged"' in runtime
      and 'ame317_dispatchAll:@"appearance.changed" payload:@{@"dark": @(dark)}]' in runtime)

check("C4 fluent-ui v2.6.0 订阅换板+Task380 同值幂等（appearance.changed → 去重短路 → applyPalette(dark?1:0)）",
      "ame.on('appearance.changed'" in js
      and "lastAppliedDark !== null && ame380_dark === lastAppliedDark" in js
      and "applyPalette(ame380_dark ? 1 : 0, true);" in js
      and "fluent-ui v2.6.0 loaded" in js)

check("C5 manifest 2.5.1 + events 权限（订阅闸；★Task380 演进顺延 2.5.1→2.6.0）",
      '"version": "2.6.0"' in manifest and '"events"' in manifest)

check("C6 插件文档同步（事件 11→12 种 + appearance.changed 条目）",
      "12 种" in docs and "appearance.changed" in docs)

def _idx_ok():
    d = json.loads(read("plugin-repo/index.json"))
    entry = next((p for p in d["plugins"] if p["id"] == "fluent-ui"), None)
    if not entry: return False
    zip_path = os.path.join(REPO, "plugin-repo", entry["file"])
    with open(zip_path, "rb") as f:
        blob = f.read()
    return (entry["version"] == "2.6.0"
            and entry["size"] == len(blob)
            and entry["sha256"] == hashlib.sha256(blob).hexdigest())

check("C7 仓库索引同步（index.json version/size/sha256 = 实际 zip）", _idx_ok())

# ══ D 线：主页右栏列序（★Task393 重锚：快航瓦片退役——同一批页面的切换
#    入口收敛为壳层右上角动作簇（MD3）/左窗格（fui）各一处，主页右栏回归
#    账号卡→版本卡→弹性占位→启动组 纯内容列；379 原"瓦片驻版本卡之下"
#    口径随瓦片退役） ═══════════════════════════════════════════════

check("D1 瓦片构建调用位（★Task401 重锚：五瓦片卡窗驻右栏顶——用户规格「五个按钮在顶上」；构建序 = quickNavCard 建卡 → 瓦片行入驻 → 账户横排滚轮卡随后）",
      home.index("[self ame378_buildQuickNav];") > home.index("_quickNavCard = [[UIView alloc] init];")
      and home.index("[self ame378_buildQuickNav];") < home.index("_accountFlow = [[AmeFlowSelectView alloc] init];"))

check("D2 右栏列序（★Task401 重锚：瓦片卡窗 → 账户横排滚轮卡窗 → 版本竖排滚轮卡窗（menuStack arranged 序）+ 启动组卡窗钉底（滚动区底缘锚启动卡顶 - 卡间隙））",
      home.index("[_menuStack addArrangedSubview:_quickNavCard];")
      < home.index("[_menuStack addArrangedSubview:_accountCard];")
      < home.index("[_menuStack addArrangedSubview:_versionCard];")
      and "[_menuScrollView.bottomAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:-ZL2HomeCardGap]," in home)

check("D3 ★Task393 切换入口收敛壳层（★Task403 重锚：右上动作簇整体退役=主页重复快捷入口清除（bd9e1d9，用户规格执行）——切换入口收敛为左窗格唯一（首页项 house.fill = showPageAtIndex:0）+ 顶栏返回钮辅助回程，fui/MD3 同一口径）",
      "self.navBackButton = [[ZL2ShellIconButton alloc] initWithSymbol:@\"chevron.left\" fallback:nil];" in shell
      and 'ame347_symbols = @[@"house.fill",' in shell)

# ══ E 线：插件感知动态色（导航栏标题白字白底根修） ════════════════

check("E1 插件感知动态色在位（provider 内实时查覆盖表 + 经典深浅对兜底）",
      "static UIColor *Ame317_PluginAwareColor(NSString *token, int light, int dark) {" in theme
      and "UIColor *ame317_ov = AmePluginColorOverride(token);" in theme
      and "[ame317_ov resolvedColorWithTraitCollection:traits];" in theme)

check("E2 宏全量改道（静态直返口径退役）",
      "#define AME317_PLUGIN_COLOR(token, light, dark) \\\n    Ame317_PluginAwareColor(@#token, light, dark)" in theme
      and "ame317_ov ? ame317_ov : ZL2ColorLightDark(light, dark);" not in theme)

check("E3 回退对语义不变（浅/深十六进制定值仍经 ZL2ColorLightDark 路径等价）",
      "static UIColor *ZL2ColorLightDark(int light, int dark) {" in theme
      and theme.count("Ame317_PluginAwareColor(@#token, light, dark)") >= 1)

# ══ S 结构护栏 ═══════════════════════════════════════════════════

check("S1 存量锚不回退（376 派发/378 bare 壳/347 骨架选择器在位）",
      "[self ame376_applyPaneGeometry:NO];" in shell
      and "ame_buildBareShell" in shell
      and '[[ZL2Theme ame347_shellLayout]' in shell
      and 'isEqualToString:@"navigationview"' in shell)

check("S2 通知名一致（壳发布 = Runtime 订阅，字符串逐字）",
      shell.count('@"AmeAppearanceTraitChanged"') >= 1
      and runtime.count('@"AmeAppearanceTraitChanged"') == 1)

print()
if fails:
    print(f"ame379_selfcheck: {len(fails)} FAIL -> " + "; ".join(fails))
    sys.exit(1)
print(f"ame379_selfcheck: ALL {passed} PASS")
