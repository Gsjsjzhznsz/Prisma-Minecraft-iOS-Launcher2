#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""task400_gate_reanchor.py -- ame378/ame379 门禁重锚到 Task400 口径
（显示层吞字节判例：门禁脚本内的锚字符串不可经终端显示核对，一律
按 check 名前缀做块级替换，替换后直接跑脚本验证。）
"""
import io, sys

def block_replace(path, name_prefix, new_block, insert_after=None):
    with io.open(path, encoding="utf-8", newline="") as f:
        t = f.read()
    marker = 'check("%s ' % name_prefix
    i = t.find(marker)
    if i < 0:
        print("FAIL start marker not found:", name_prefix); sys.exit(1)
    j = t.find("\n\n", i)
    if j < 0:
        print("FAIL end not found:", name_prefix); sys.exit(1)
    t = t[:i] + new_block + t[j:]
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    print("OK", name_prefix)

REPO = "/home/z/my-project/repo"

# ── ame378 C1：瓦片驻顶卡 ──
block_replace(REPO + "/scripts/ame378_selfcheck.py", "C1", '''check("C1 快航构建器在位 + 顶卡挂接（★Task400 重锚：瓦片卡驻右栏顶——用户复诉「五个按钮在顶上，你移到中间干啥」；Task379「随账号/版本卡之后」与弹性占位口径随卡片化滚动区退役；构建序 = quickNavCard 建卡 → 瓦片行入驻 → 账户/版本滚轮卡随后）",
      "- (void)ame378_buildQuickNav {" in home_code
      and "[self ame378_buildQuickNav];" in home_code
      and "[_quickNavCard addSubview:_quickNavWrap];" in home_code
      and home_code.index("[self ame378_buildQuickNav];") > home_code.index("_quickNavCard = [[UIView alloc] init];")
      and home_code.index("[self ame378_buildQuickNav];") < home_code.index("_accountCard = [[UIView alloc] init];"))''')

# ── ame378 C4：卡片化对称留白 ──
block_replace(REPO + "/scripts/ame378_selfcheck.py", "C4", '''check("C4 对称留白纪律（★Task400 重锚：单行 fillEqually 均分 + 统一间距 + 瓦片行四边钉顶卡内缩 8pt（卡片化对称内边距）+ 长标签缩排不截断 + 卡间间隙 = 栏距屏边 8pt 同值 + 栏停靠边四边 8pt 沿用）",
      home_code.count("UIStackViewDistributionFillEqually") == 1
      and "_quickNavWrap.spacing = ZL2HomeQuickNavGap;" in home_code
      and "ame378_label.minimumScaleFactor = 0.7;" in home_code
      and "[_quickNavWrap.topAnchor constraintEqualToAnchor:_quickNavCard.topAnchor constant:ZL2HomeCardPadding]," in home_code
      and "[_quickNavWrap.leadingAnchor constraintEqualToAnchor:_quickNavCard.leadingAnchor constant:ZL2HomeCardPadding]," in home_code
      and "[_quickNavWrap.trailingAnchor constraintEqualToAnchor:_quickNavCard.trailingAnchor constant:-ZL2HomeCardPadding]," in home_code
      and "_menuStack.spacing = ZL2HomeCardGap;" in home_code
      and "menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8]," in home_code
      and "menu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8]," in home_code)''')

# ── ame378 C9 + 新增 C10：滚轮功能锚 + 卡片化口径 ──
block_replace(REPO + "/scripts/ame378_selfcheck.py", "C9", '''check("C9 账户/版本滚轮卡功能锚（★Task400 重锚：双卡改 AmeIpodFlowView 原地滚轮——落定回调/卡尾钮（账户管理+刷新+齿轮）/a11y id 保留；卡体点击链退役 = 拖拽即选择）",
      "_accountFlow = [[AmeIpodFlowView alloc] init];" in home_code
      and "_versionFlow = [[AmeIpodFlowView alloc] init];" in home_code
      and "_accountFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "_versionFlow.onSettle = ^(NSInteger ame400_index) {" in home_code
      and "accountCardTapped" in home_code
      and "versionSettingsTapped" in home_code
      and 'accessibilityIdentifier = @"zl2_home_account_card";' in home
      and 'accessibilityIdentifier = @"zl2_home_version_card";' in home)

check("C10 右栏卡片化口径（★Task400 新立：用户规格第 4 条——栏容器背景透明（呈现启动器背景）+ 四卡 surfaceContainer/radiusXL（右侧栏圆角同款）+ 卡间间隙 8pt（= Task392 栏距屏边四边同值）+ MC 头像 1 物理像素超小圆角）",
      "_actionMenu.backgroundColor = [UIColor clearColor];" in home_code
      and "_quickNavCard.backgroundColor = [ZL2Theme surfaceContainer];" in home_code
      and "_accountCard.backgroundColor = [ZL2Theme surfaceContainer];" in home_code
      and "_versionCard.backgroundColor = [ZL2Theme surfaceContainer];" in home_code
      and "_launchCard.backgroundColor = [ZL2Theme surfaceContainer];" in home_code
      and home_code.count("layer.cornerRadius = [ZL2Theme radiusXL];") >= 4
      and "ZL2HomeCardGap            = 8;" in home
      and "layer.cornerRadius = 1.0 / [UIScreen mainScreen].scale;" in home_code)''')

# ── ame379 D1/D2：列序重锚 ──
block_replace(REPO + "/scripts/ame379_selfcheck.py", "D1", '''check("D1 瓦片构建调用位（★Task400 重锚：五瓦片卡驻右栏顶——用户复诉「五个按钮在顶上，你移到中间干啥」；Task379「瓦片随账号/版本卡之后」与弹性占位口径随卡片化滚动区退役）",
      home.index("[self ame378_buildQuickNav];") > home.index("_quickNavCard = [[UIView alloc] init];")
      and home.index("[self ame378_buildQuickNav];") < home.index("_accountFlow = [[AmeIpodFlowView alloc] init];"))''')

block_replace(REPO + "/scripts/ame379_selfcheck.py", "D2", '''check("D2 右栏列序（★Task400 重锚：瓦片卡 → 账户滚轮卡 → 版本滚轮卡（menuStack arranged 序）+ 启动组卡钉底（滚动区底缘锚启动卡顶 - 卡间隙））",
      home.index("[_menuStack addArrangedSubview:_quickNavCard];")
      < home.index("[_menuStack addArrangedSubview:_accountCard];")
      < home.index("[_menuStack addArrangedSubview:_versionCard];")
      and "[_menuScrollView.bottomAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:-ZL2HomeCardGap]," in home)''')

print("ALL REANCHORS DONE")
