#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task459 自检门（用户复诉「问题依旧。我这个应该是md3界面。还有版本设置去哪里了。」+
IMG_0741 装机截图像素取证轮）：

  「版本设置去哪里了」= 主页右栏版本卡卡尾刷新/齿轮（版本管理→版本设置链）两钮
  第四轮复发（Task443→455→456→459 同源临床）。IMG_0741 像素实锤：单实例设备
  （出厂 (Default) 卡 n=1）版本卡恒 418pt（五行理想高），滚动视口余量 357pt，
  卡被视口底缘裁剪——可见卡高恰 357pt、卡尾两钮域（卡顶 366-398pt）零像素。

  根因 = ame414_relayoutVersionHeight 的 n≤5 分支以五行理想高直接落定早退，
  avail 钳制只护 n>5 分支 = Task456「target 恒 ≤ avail」断言的漏网面；
  附带 Task456 chrome 超定雷：卡高常量 2.0×padding(16)+6+32+4=58 与内容链
  （flow.top 单侧 8+6+32+4=50）差 8pt，required 超定 = AutoLayout 随机断钉
  家族现行（注释 50 vs 代码 58 判例留档）。

  根修 = ①avail 前置为两分支共用钳制（单行 64pt 绝对下限，滚轮可拖语义无损）
  ②chrome 单源常量 ame456_versionCardChrome=50，卡高常量/写入单点/余量式三点
  同源引用，零超定。

R = 修复形态执法 / X = 全仓扫描（家族零容忍）/ S = 敏感性自证（放行样本）
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []


def check(name, ok, detail=""):
    print(("  [PASS] " if ok else "  [FAIL] ") + name + (("  -- " + detail) if (detail and not ok) else ""))
    if not ok:
        FAILS.append(name)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


home = read("Natives/ZL2HomeViewController.m")
buildtag = read("Natives/BuildTag.h")

print("== R 修复形态执法 ==")

# R1a 旧无条件早退形态退役（n≤5 分支直落五行理想高 = 本轮根因形态）
check("R1a 旧 n≤5 无条件理想高早退形态退役",
      "ame456_setVersionCardFlowHeight:ame414_ideal]" not in home)

# R1b 统一钳制形态在位（fmax 单行下限 + fmin(full, avail)）
check("R1b 两分支统一钳制形态在位",
      re.search(r"ame414_target\s*=\s*fmax\(ZL2HomeVersionFlowItemH,\s*fmin\(ame414_full,\s*ame414_avail\)\)", home) is not None)

# R1c avail 前置于钳制（余量计算先于 target 写入 = 两分支共用）
idx_avail = home.find("CGFloat ame414_avail")
idx_target = home.find("CGFloat ame414_target")
idx_set = home.find("[self ame456_setVersionCardFlowHeight:ame414_target]")
check("R1c avail 前置于钳制与落定（序 avail < target < set）",
      0 <= idx_avail < idx_target < idx_set)

# R1d ame414 全方法域内无中间早退（守卫 return 后直达落定 = n≤5 不再绕过钳制）
m = re.search(r"- \(void\)ame414_relayoutVersionHeight \{.*?\n\}", home, re.S)
body = m.group(0) if m else ""
check("R1d 方法体仅守卫早退 + 恰一次落定",
      body.count("return;") == 1
      and body.count("ame456_setVersionCardFlowHeight") == 1)

# R1e 判例注释在位（第四轮复发根因留档）
check("R1e Task459 判例注释（余量统一前置）在位",
      "★Task459 余量统一前置" in home and "四轮同源临床" in home)

# R2a chrome 单源常量定义恰一处、值 50
defs = re.findall(r"static const CGFloat ame456_versionCardChrome\s*=\s*([\d.]+);", home)
check("R2a ame456_versionCardChrome 定义恰一处且 = 50",
      len(defs) == 1 and float(defs[0]) == 50.0)

# R2b 三消费点同源引用（写入单点 / 卡高常量创建 / ame414 余量式）
check("R2b 写入单点引用 chrome 常量",
      "CGFloat ame456_card = ame456_flow + ame456_versionCardChrome;" in home)
check("R2b 卡高常量创建点引用 chrome 常量",
      "_versionFlow.viewportHeight\n                                                             + ame456_versionCardChrome];" in home)
check("R2b ame414 余量式引用 chrome 常量",
      "- ame456_versionCardChrome;   // ★Task459 版本卡内构单源 50" in home)

# R2c 旧手写 chrome 字面量形态清零（ZL2HomeViewController 内零容忍）
check("R2c 旧 2.0×padding chrome 字面量清零",
      "2.0 * ZL2HomeCardPadding + 6.0" not in home)

# R3 卡尾两钮结构钉原样（Task456 卡内零超定形态不得回退）
check("R3 flow.bottom=齿轮.top−6 / 齿轮.bottom=卡底−4 / 尺寸 32 原钉在位",
      "_versionFlow.bottomAnchor constraintEqualToAnchor:_versionSettingsButton.topAnchor constant:-6" in home
      and "_versionSettingsButton.bottomAnchor constraintEqualToAnchor:_versionCard.bottomAnchor constant:-4" in home
      and home.count("[_versionSettingsButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight]") == 1)

# R4 两钮创建面原样（gearshape 版本管理 / arrow.clockwise 刷新实例列表）
check("R4 齿轮=版本管理 / 刷新=刷新实例列表 a11y 在位",
      'a11y:localize(@"ame369.home.version_manager_a11y", @"版本管理")' in home
      and 'a11y:localize(@"ame369.home.refresh_instances_a11y", @"刷新实例列表")' in home)

# R5 BuildTag 代际
check("R5 BuildTag = Task460 · 2026-11-21（★Task460 重锚）",
      'ame415_buildTag = @"Task460 · 2026-11-21"' in buildtag)

print("== X 全仓扫描 ==")

# X1 chrome 手写字面量家族全仓清零（除定义行注释外零出现）
hits = []
for p in sorted((ROOT / "Natives").glob("*.m")):
    t = p.read_text(encoding="utf-8", errors="replace")
    if "2.0 * ZL2HomeCardPadding + 6.0" in t:
        hits.append(p.name)
check("X1 chrome 手写字面量家族全仓零容忍", not hits, " ".join(hits))

# X2 chrome 常量全仓定义唯一
all_defs = 0
for p in sorted(list((ROOT / "Natives").glob("*.m")) + list((ROOT / "Natives").glob("*.h"))):
    t = p.read_text(encoding="utf-8", errors="replace")
    all_defs += len(re.findall(r"static const CGFloat ame456_versionCardChrome\s*=", t))
check("X2 ame456_versionCardChrome 全仓定义唯一", all_defs == 1)

# X3 镜像右停靠原钉复立面原样（卡尾四钮换边语义零回归）
check("X3 右停靠原钉复立（ame_m addObjectsFromArray:ame_pins）在位",
      "if (!ame_left) {" in home
      and "[ame_m addObjectsFromArray:ame_pins];" in home)

# X4 Task456 卡高写入单点守卫原样（|Δ|>0.5 幂等）
check("X4 写入单点 0.5 幂等守卫在位",
      "fabs(_ame456_versionCardHeight.constant - ame456_card) > 0.5" in home)

print("== S 敏感性自证 ==")

# S1 值敏感性：chrome 若被改成 51/49 必红（定义行值域断言而非子串巧合）
check("S1 chrome 值断言非子串巧合（float == 50.0 判据）",
      len(defs) == 1 and abs(float(defs[0]) - 50.0) < 1e-9)

# S2 钳制下限敏感性：单行 64 绝对下限在钳制式内（fmax 首参）
check("S2 单行下限位于 fmax 首参（拖动语义保全）",
      re.search(r"fmax\(ZL2HomeVersionFlowItemH, fmin\(ame414_full, ame414_avail\)\)", home) is not None)

# S3 Task443 补减项保留（快航卡 + 两段间隙 = 余量口径不回退）
check("S3 Task443 补减项（快航卡/账户卡/两段 gap）在位",
      "_quickNavCard.frame.size.height" in body
      and "_accountCard.frame.size.height" in body
      and body.count("- ZL2HomeCardGap") >= 2)

# S4 放行样本：其余 ame456 命名面不受本门约束（写入单点注释保留）
check("S4 Task456 写入单点判例注释保留（方法域在 @implementation 内判例）",
      "方法体必须在 @implementation 内（Task455 事故①判例）" in home)

print()
if FAILS:
    print("task459_selfcheck RED -- %d FAIL: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
n_checks = 21
print("task459_selfcheck ALL PASS (%d assertions)" % n_checks)
