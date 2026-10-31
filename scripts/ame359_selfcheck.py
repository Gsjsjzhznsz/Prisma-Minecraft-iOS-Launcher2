#!/usr/bin/env python3
# ame359_selfcheck.py -- Task 359/360/361/362/363 门禁（装机 IMG_0532 + latestlog.old 实锤四线 + 提示词插件文档扩容）
# A [Ame359] 弹窗 header 滚动区（"悬浮弹窗信息太多挡住按钮"根治）
# B [Ame360] 弹窗伪液态玻璃恢复 + tint 提透（"取消 md3 风格 / 透明度不够"）
# C [Ame361] 新UI设置写入通道对齐（"修改不生效会回退"根修：LGC 中枢/AiSettings/mobileglues 重映射/mod_mirror 粗控）
# D [Ame362] AI 回复可见性（"ai回复的信息没有显示"根修：正文色 labelColor 注入 + 气泡系统底）
# E [Ame363] AI 提示词插件文档扩容（"提示词只给了几个API"：v4 四族主题令牌 + 全量 API 面 + 迁移链 + 工具描述对齐）
# S 反向探针（病灶变体注入比对必翻红，零仓内触碰）
import os, sys, io

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

menu = read("Natives/AmeFloatingMenu.m")
pages = read("Natives/ZL2SettingPages.m")
cell = read("Natives/AI/AIMessageCell.m")
md_h = read("Natives/MarkdownParser.h")
md_m = read("Natives/MarkdownParser.m")
aiset = read("Natives/AI/AiSettings.m")
ptool = read("Natives/AI/AiPluginWriterTool.m")

# Task363 提示词域切片（★ Task364 重锚：现役 defaultSystemPrompt 已升 v5，
# 本脚本 E 区断言对象改为 ame364_v4DefaultSystemPrompt 留档（v4 原文），
# 现役 v5 由 ame364_selfcheck 独立把关）
aiset_v4_zone = aiset[aiset.find("+ (NSString *)ame364_v4DefaultSystemPrompt {"):]
aiset_v4_zone = aiset_v4_zone[:aiset_v4_zone.find("/// ★ Task363：v3 默认提示词全文")]

# ══ A [Ame359] header 滚动区 ═════════════════════════════════
check('A1 headerScroll 属性 + 注释锚在位',
      "@property (nonatomic, strong) UIScrollView *headerScroll;" in menu
      and "Task359" in menu)
check('A2 标题/正文/输入框全部挂 headerScroll（不再直接铺 panel）',
      "[self.headerScroll addSubview:self.titleLabel];" in menu
      and "[self.headerScroll addSubview:self.messageLabel];" in menu
      and "[self.headerScroll addSubview:f];" in menu)
check('A3 布局预算分配（行区保底 MIN(rowsH,110) + header 至多占余量）',
      "CGFloat ame359_rowsMin = MIN(rowsH, 110.0);" in menu
      and "CGFloat headerAvail = MIN(rowsTop, ame359_headerMax);" in menu
      and "rowsAvail = MAX(0.0, panelH - headerAvail - bottomInset);" in menu)
check('A4 headerScroll frame/contentSize/scrollEnabled 铺排',
      "self.headerScroll.frame = CGRectMake(0.0, 0.0, W, headerAvail);" in menu
      and "self.headerScroll.contentSize = CGSizeMake(W, rowsTop);" in menu
      and "self.headerScroll.scrollEnabled = (rowsTop > headerAvail + 0.5);" in menu
      and "self.rowsScroll.frame = CGRectMake(0.0, headerAvail, W, rowsAvail);" in menu)
check('A5 焦点输入框滚入可视区（viewDidAppear scrollRectToVisible）',
      "scrollRectToVisible:ame359_first.frame" in menu)
check('A6 布局日志锚更新（Task359 header 字段）',
      '"[AmeMenu] Task359 panel layout' in menu and "header=%.0f/%.0f scrolled=%d" in menu)

# ══ B [Ame360] 玻璃恢复 + 提透 ═══════════════════════════════
check('B1 玻璃材质闸（Ame360GlassMenuMaterial = YES + 旧 MD3 常量零残留）',
      "static const BOOL Ame360GlassMenuMaterial = YES;" in menu
      and "Ame354MD3MenuMaterial" not in menu)
check('B2 快照磨砂 tint 梯度提透（默认档深 0.32/浅 0.34 + 下限护栏）',
      "? 0.32 - 0.58 * (ame263_t - 0.5)" in menu
      and ": 0.34 - 0.60 * (ame263_t - 0.5)" in menu
      and "MAX(0.03, ame263_a)" in menu and "MAX(0.04, ame263_a)" in menu)
check('B3 材质日志锚（Task360 pseudo-liquid-glass restored）',
      "[AmeMenu] Task360 menu material: pseudo-liquid-glass restored" in menu)

# ══ C [Ame361] 设置写入通道对齐 ══════════════════════════════
check('C1 导入接线（LiquidGlassCompat + AiSettings）',
      '#import "LiquidGlassCompat.h"' in pages and '#import "AI/AiSettings.h"' in pages)
check('C2 界面风格走 LGC 中枢（错通道 general.interface_style 零残留）',
      "LGCSetStoredInterfaceStyle(LGCInterfaceStyleFromString(styleKeys[index]));" in pages
      and 'getPrefObject(@"general.interface_style")' not in pages
      and 'setPrefString(@"general.interface_style"' not in pages)
check('C3 透明度/双缩放走 LGC 中枢（错通道 general.* 零残留）',
      "LGCSetPseudoGlassTransparency((CGFloat)value / 100.0);" in pages
      and "LGCSetUIScaleMultiplier((CGFloat)value / 100.0);" in pages
      and "LGCSetTextScaleMultiplier((CGFloat)value / 100.0);" in pages
      and 'getPrefFloat(@"general.pseudo_glass_transparency")' not in pages
      and 'getPrefFloat(@"general.ui_scale")' not in pages
      and 'getPrefFloat(@"general.text_scale")' not in pages)
check('C4 AI 安全模式/Markdown 直连 AiSettings（错通道 ai.* 零残留）',
      "[[AiSettings sharedSettings] setSafetyMode:mode];" in pages
      and "[[AiSettings sharedSettings] setMarkdownEnabled:on];" in pages
      and 'getPrefObject(@"ai.safety_mode")' not in pages
      and 'setPrefString(@"ai.safety_mode"' not in pages
      and 'getPrefBool(@"ai.markdown_enabled")' not in pages
      and 'setPrefBool(@"ai.markdown_enabled"' not in pages)
check('C5 mod_mirror 粗控双键写入（虚键零残留 + Task138 协议）',
      'setPrefString(@"download.assetSearchSource", sourceKeys[index]);' in pages
      and 'setPrefString(@"download.assetDownloadSource", sourceKeys[index]);' in pages
      and 'setPrefString(prefKey, sourceKeys[index]);' in pages
      and 'getPrefObject(@"download.mod_mirror")' not in pages)
check('C6 FSR 双键重映射 mobileglues.*（错段 video.* 零残留 + NSNumber 双态解析）',
      'getPrefObject(@"mobileglues.fsr1_setting")' in pages
      and 'setPrefString(@"mobileglues.fsr1_setting", fsrKeys[index]);' in pages
      and 'getPrefObject(@"mobileglues.fsr_rcas_sharpness")' in pages
      and 'setPrefString(@"mobileglues.fsr_rcas_sharpness", rcasKeys[index]);' in pages
      and 'getPrefObject(@"video.fsr1_setting")' not in pages
      and 'setPrefString(@"video.fsr1_setting"' not in pages
      and 'getPrefObject(@"video.fsr_rcas_sharpness")' not in pages
      and 'setPrefString(@"video.fsr_rcas_sharpness"' not in pages
      and "isKindOfClass:[NSNumber class]] ? [(NSNumber *)ame361_fsrRaw stringValue]" in pages)

# ══ D [Ame362] AI 回复可见性 ═════════════════════════════════
check('D1 MarkdownParser textColor 注入口（.h 声明 + .m 实现 + 旧签名转发）',
      "textColor:(nullable UIColor *)textColor;" in md_h
      and "textColor:(UIColor *)ame358_textColor {" in md_m
      and "return [self parseMarkdown:markdown baseFont:baseFont textColor:nil];" in md_m
      and "UIColor *textColor = ame358_textColor ?: [AmeTheme textPrimary];" in md_m)
check('D2 助手气泡正文 labelColor 注入（渲染 + 测高同路）',
      cell.count("textColor:[UIColor labelColor]];" ) >= 2
      and "[MarkdownParser parseMarkdown:content\n                                                         baseFont:" in cell)
check('D3 助手气泡底改系统自适应（硬编码白 0.08 退役）',
      "[UIColor tertiarySystemBackgroundColor];" in cell
      and "bubbleView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];" not in cell)

# ══ E [Ame363] AI 提示词插件文档扩容 ═════════════════════
check('E1 迁移链 v3→v4→v5（ame363_v3/ame364_v4 双留档 + 版本号 5 + 两级自适应升级日志）',
      "+ (NSString *)ame363_v3DefaultSystemPrompt {" in aiset
      and "+ (NSString *)ame364_v4DefaultSystemPrompt {" in aiset
      and "[ame267_saved isEqualToString:[self ame363_v3DefaultSystemPrompt]]" in aiset
      and "[ame267_saved isEqualToString:[self ame364_v4DefaultSystemPrompt]]" in aiset
      and "[ame267_d setInteger:5 forKey:kSystemPromptVersionKey];" in aiset
      and "Task363: v3 default system prompt auto-upgraded to v4" in aiset
      and "Task364: v4 default system prompt auto-upgraded to v5" in aiset)
check('E2 v4 提示词含主题四家族（setThemeToken/Shape/Layout/Structure + shellLayout 值域）',
      "ame.setThemeToken(色令牌表)" in aiset_v4_zone
      and "ame.setThemeShape(形状/字阶表)" in aiset_v4_zone
      and "ame.setThemeLayout(排版刻度表)" in aiset_v4_zone
      and "ame.setThemeStructure({shellLayout:'topbar'|'navigationview'})" in aiset_v4_zone)
check('E3 v4 提示词含全量 API 面锚点（14 权限+ame.super/色值格式/事件七种/文件限额/网络超时）',
      "共 14 项" in aiset_v4_zone and "ame.super" in aiset_v4_zone
      and "#RRGGBBAA" in aiset_v4_zone
      and "app.launch / app.foreground / app.background / profile.changed / profile.listChanged / game.starting / game.exited" in aiset_v4_zone
      and "≤2MB" in aiset_v4_zone and "30 秒超时" in aiset_v4_zone)
check('E4 create_plugin 工具描述对齐（三族主题令牌 + 色值 + 立即生效语义）',
      "ame.setThemeShape" in ptool and "ame.setThemeLayout" in ptool
      and "ame.setThemeStructure" in ptool and "#RRGGBBAA" in ptool)
check('E5 v4 保留一~六章/行为纪律/openPage 七页（非插件域零回归）',
      "【一、用户想安装 Minecraft 时" in aiset_v4_zone
      and "【行为纪律】" in aiset_v4_zone
      and "home/download/versions/accounts/settings/multiplayer/ai" in aiset_v4_zone)

# ══ S 反向探针 ═══════════════════════════════════════════════
check('S-A1 摘除 headerScroll 铺排 → 变体可检出',
      "self.headerScroll.frame = CGRectMake(0.0, 0.0, W, headerAvail);" in menu
      and "self.headerScroll.frame = CGRectMake(0.0, 0.0, W, headerAvail);"
          not in menu.replace("CGRectMake(0.0, 0.0, W, headerAvail)", "CGRectMake(0.0, 0.0, 0, 0)"))
check('S-B1 tint 梯度回退旧值 → 变体可检出',
      "? 0.32 - 0.58 * (ame263_t - 0.5)" in menu
      and "? 0.32 - 0.58 * (ame263_t - 0.5)" not in menu.replace("0.32 - 0.58", "0.40 - 0.50"))
check('S-C1 设置错通道回潮 → 变体可检出',
      'setPrefString(@"general.interface_style"' not in pages
      and 'setPrefString(@"general.interface_style"' not in pages.replace(
          'setPrefString(@"general.interface_style"', 'AME357_SENTINEL("general.interface_style"'))
check('S-D1 正文色注入口摘除 → 变体可检出',
      "UIColor *textColor = ame358_textColor ?: [AmeTheme textPrimary];" in md_m
      and "UIColor *textColor = ame358_textColor ?: [AmeTheme textPrimary];" not in
          md_m.replace("ame358_textColor ?", "nil ?:"))
check('S-E1 v4 提示词回退紧凑版旧【七】→ 变体可检出（旧 API 概施行在新域零残留）',
      "插件 API（全局对象 ame）：ame.on/off（事件" not in aiset_v4_zone
      and "插件 API（全局对象 ame）：ame.on/off（事件" in aiset)

print()
if fails:
    print(f"ame359_selfcheck: {len(fails)} FAIL / {passed} PASS")
    for f in fails:
        print(f"  - {f}")
    sys.exit(1)
print(f"ame359_selfcheck: ALL GREEN ({passed} assertions)")
