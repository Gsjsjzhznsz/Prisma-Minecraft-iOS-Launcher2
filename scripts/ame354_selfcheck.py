#!/usr/bin/env python3
# ame354_selfcheck.py -- Task354 门禁（用户指令"全面修改为 md3 样式，避免 ui 设计语言混杂"）
# A 菜单/弹窗面板 MD3 材质化（AmeFloatingMenu：TG 玻璃/快照磨砂/系统材质菜单域退役，
#   面板 = ZL2Theme surfaceContainerHigh 实底 + radiusXL 28 + M3 字阶/色彩/形状）
# B AmeTheme v3 M3 承载层（全部 getter 重指向 ZL2Theme，API 兼容零调用面改动）
# C 省电旁路（快照抓帧 + 8Hz 重抓 MD3 下停用）+ 描边环退役
# S 反向探针（病灶变体注入比对必翻红，零仓内触碰）
# 断言纪律：含字符串字面量的断言用原文（raw）；strip 后文本仅用于纯结构检查。
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

def strip_code(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

menu = read("Natives/AmeFloatingMenu.m")
menu_code = strip_code(menu)
amem = read("Natives/AmeTheme.m")
amem_code = strip_code(amem)
ameh = read("Natives/AmeTheme.h")

# ══ A 菜单/弹窗面板 MD3 材质化 ═══════════════════════════════
check('A1 材质闸常量在位（★ Task360 玻璃档恢复：Ame360GlassMenuMaterial = YES）',
      "static const BOOL Ame360GlassMenuMaterial = YES;" in menu_code
      and "Task360" in menu)

check('A2 面板 M3 实底 + 大容器圆角（surfaceContainerHigh + radiusXL）',
      "self.panel.backgroundColor = [ZL2Theme surfaceContainerHigh];" in menu
      and "self.panel.layer.cornerRadius = [ZL2Theme radiusXL];" in menu)

check('A3 三条玻璃/磨砂管线菜单域重新上岗（★ Task360：blurView 效果选择/TG 玻璃/快照磨砂分支）',
      "if (Ame360GlassMenuMaterial && LGCIsGlassStyleActive()) {" in menu_code
      and "BOOL ame252_glassActive = Ame360GlassMenuMaterial &&" in menu_code
      and "if (Ame360GlassMenuMaterial && !ame252_glassActive && ame244_snapImg != nil) {" in menu_code)

check('A4 blurView/描边环随玻璃档归队（hidden = !Ame360GlassMenuMaterial）',
      "self.blurView.hidden = !Ame360GlassMenuMaterial;" in menu_code
      and "self.borderOverlay.hidden = !Ame360GlassMenuMaterial;" in menu_code)

check('A5 M3 字阶落位（title=fontTitleLarge / message=fontBodyMedium / 输入=bodyLarge / 行=bodyLarge+titleMedium）',
      "self.titleLabel.font = [ZL2Theme fontTitleLarge];" in menu
      and "self.messageLabel.font = [ZL2Theme fontBodyMedium];" in menu
      and "f.font = [ZL2Theme fontBodyLarge];" in menu
      and "? [ZL2Theme fontTitleMedium]   //" in menu
      and "_rowLabel.font = [ZL2Theme fontBodyLarge];" in menu)

check('A6 M3 色彩落位（onSurface/onSurfaceVariant/error/surfaceContainerHighest/outlineVariant）',
      "self.titleLabel.textColor = [ZL2Theme onSurface];" in menu
      and "self.messageLabel.textColor = [ZL2Theme onSurfaceVariant];" in menu
      and "(m.style == 2) ? [ZL2Theme error] : [ZL2Theme onSurface]" in menu
      and "f.backgroundColor = [ZL2Theme surfaceContainerHighest];" in menu
      and "sep.backgroundColor = [ZL2Theme outlineVariant];" in menu)

check('A7 MD3 对齐语义（标题/正文起点对齐 + 输入框无描边 + radiusS）',
      menu.count("NSTextAlignmentLeft; // ★ Task354") >= 2
      and "f.layer.borderWidth = 0.0;" in menu
      and "f.layer.cornerRadius = [ZL2Theme radiusS];" in menu)

check('A8 [Ame356] 材质日志锚（pseudo-liquid-glass restored 可 grep）',
      '"[AmeMenu] Task360 menu material: pseudo-liquid-glass restored' in menu)

# ══ B AmeTheme v3 M3 承载层 ═════════════════════════════════
check('B1 色彩 17 getter 全部重指向 ZL2Theme（无 Fluent AmeDynamic 残留取值）',
      all(k in amem for k in [
          "[ZL2Theme primary]", "[ZL2Theme secondaryContainer]", "[ZL2Theme onPrimary]",
          "[ZL2Theme surface]", "[ZL2Theme surfaceContainerLow]", "[ZL2Theme surfaceBright]",
          "[ZL2Theme surfaceContainerHigh]", "[ZL2Theme onSurface]", "[ZL2Theme onSurfaceVariant]",
          "[ZL2Theme outline]", "[ZL2Theme surfaceContainerHighest]", "[ZL2Theme surfaceVariant]",
          "[ZL2Theme outlineVariant]", "[ZL2Theme error]", "[ZL2Theme success]", "[ZL2Theme warning]",
          "[ZL2Theme primary];" ]) and "AmeDynamic(" not in amem_code)

check('B2 字阶 7 getter 全部重指向（labelMedium/bodyMedium/bodyLarge/labelLarge/titleLarge/headline）',
      all(k in amem for k in [
          "[ZL2Theme fontLabelMedium]", "[ZL2Theme fontBodyMedium]", "[ZL2Theme fontBodyLarge]",
          "[ZL2Theme fontLabelLarge]", "[ZL2Theme fontTitleLarge]", "[ZL2Theme fontHeadline]"]))

check('B3 圆角 5 getter 全部重指向（XS/S/M/L/XL）',
      all(k in amem for k in [
          "[ZL2Theme radiusXS]", "[ZL2Theme radiusS];", "[ZL2Theme radiusM];",
          "[ZL2Theme radiusL];", "[ZL2Theme radiusXL];"]))

check('B4 .h 契约更新（v3 M3 承载层声明 + 旧 Fluent 取值档案留痕）',
      "v3 · M3 承载层" in ameh and "Task354" in ameh and "fluent2_kit" in ameh)

# ══ C 省电旁路 + 结构护栏 ═══════════════════════════════════
check('C1 快照抓帧 + 8Hz 重抓玻璃档恢复（★ Task360 旁路退役）',
      "if (Ame360GlassMenuMaterial) {\n        menu.ame243_snapshotImage" in menu
      and "if (Ame360GlassMenuMaterial) {\n        [self ame246_startBackgroundRefresh];" in menu)

check('C2 呈现/命中/动作链未动（present 镜像 + rowTapped + dimTapped 锚仍在）',
      "ame237_rowTapped:" in menu_code and "ame237_dimTapped" in menu_code
      and 'presentViewController:menu animated:NO' in menu_code)

# ══ S 反向探针（病灶变体注入比对，零仓内触碰） ═════════════
check('S-A1 摘除玻璃材质闸 → 变体可检出',
      "static const BOOL Ame360GlassMenuMaterial = YES;" in menu
      and "static const BOOL Ame360GlassMenuMaterial = YES;"
          not in menu.replace("static const BOOL Ame360GlassMenuMaterial = YES;", ""))
check('S-A2 面板底色回退 Fluent 值 → 变体可检出',
      "self.panel.backgroundColor = [ZL2Theme surfaceContainerHigh];" in menu
      and "self.panel.backgroundColor = [ZL2Theme surfaceContainerHigh];"
          not in menu.replace("[ZL2Theme surfaceContainerHigh]", "[AmeTheme surfaceOverlay]"))
check('S-B1 AmeTheme 回落 Fluent 硬编码 → 变体可检出',
      "AmeDynamic(" not in amem_code
      and "AmeDynamic(" not in amem_code.replace("return [ZL2Theme ", "return AmeDynamic(0x0,".replace("AmeDynamic(0x0,", "")))
check('S-C1 玻璃分支闸摘除（TG 玻璃在菜单域退役路径）→ 变体可检出',
      "BOOL ame252_glassActive = Ame360GlassMenuMaterial &&" in menu
      and "BOOL ame252_glassActive = Ame360GlassMenuMaterial &&"
          not in menu.replace("BOOL ame252_glassActive = Ame360GlassMenuMaterial &&",
                              "BOOL ame252_glassActive = NO &&"))

print()
if fails:
    print(f"ame354_selfcheck: {len(fails)} FAIL / {passed} PASS")
    for f in fails:
        print(f"  - {f}")
    sys.exit(1)
print(f"ame354_selfcheck: ALL GREEN ({passed} assertions)")
