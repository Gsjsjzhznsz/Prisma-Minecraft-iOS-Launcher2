#!/usr/bin/env python3
"""task393_r3_audit.py -- Task393 r3 编译面预防性审计

背景：run 41663804985 三处编译雷（zPosition 直落 UIView / [self.ame_stopTicker]
点号手误 / ame_settledIndex 属性名手误）全部属于「括号平衡门禁查不出、只有
真编译器才能暴露」的类型面错误。本地无 Xcode，只能用启发式正则把同族雷
提前扫出来。

扫描面（Task393 全部触碰源文件）：
  A. [self.xxx] 裸点号括号（点语法取属性后发空消息 = expected identifier）
  B. self.xxx = / self.xxx 读取，xxx 不在 @property 声明且不是已知合法面
  C. 非 layer 前缀的 .zPosition 直落（UIView 无此属性，CALayer 才有）
  D. accessibilityIncrement/Decrement 实现（SDK 口径 = void，BOOL = 告警）
"""
import os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [
    "Natives/AmeFlowSelectView.m",
    "Natives/ZL2AccountsViewController.m",
    "Natives/ZL2HomeViewController.m",
    "Natives/Preview/AmeFluentPreviewMain.m",
    "Natives/Preview/ZL2PagesStub.m",
]

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

issues = []
for rel in FILES:
    p = os.path.join(REPO, rel)
    if not os.path.exists(p):
        continue
    raw = open(p, encoding='utf-8').read()
    code = strip_comments(raw)
    lines = code.split('\n')

    # 本文件声明的属性名集合（@property 行提取；含 block 属性 void (^name)(...)）
    props = set(re.findall(r'@property\s*\([^)]*\)\s*[\w<>,\*\s]+?\*\s*(\w+)', raw))
    props |= set(re.findall(r'@property\s*\([^)]*\)\s*[\w<>,\*\s]+?\s(\w+)\s*;', raw))
    props |= set(re.findall(r'@property\s*\([^)]*\)[^;]*?\(\^(\w+)\)', raw))

    for ln, line in enumerate(lines, 1):
        # A. [self.xxx] 裸点号括号（消息发给自己.属性的结果且无选择器）
        for m in re.finditer(r'\[\s*self\.(\w+)\s*\]', line):
            issues.append((rel, ln, f"A 点号括号雷 [self.{m.group(1)}]", line.strip()[:90]))
        # C. .zPosition 直落且前缀不是 layer
        for m in re.finditer(r'(\w+(?:\.\w+)*)\.zPosition', line):
            recv = m.group(1)
            if not recv.endswith('.layer'):
                issues.append((rel, ln, f"C zPosition 直落 {recv}", line.strip()[:90]))
        # D. accessibilityIncrement/Decrement BOOL 签名
        if re.match(r'\s*-\s*\(BOOL\)\s*accessibility(Increment|Decrement)', line):
            issues.append((rel, ln, "D accessibility BOOL 签名（SDK=void）", line.strip()[:90]))
        # B. self.<name> 读取/赋值，name 非属性（启发式：排除常见系统面与iVar）
        for m in re.finditer(r'\bself\.(\w+)', line):
            name = m.group(1)
            if name in props:
                continue
            if name in ('layer', 'frame', 'bounds', 'center', 'superview', 'subviews',
                        'window', 'alpha', 'hidden', 'tag', 'clipsToBounds', 'contentMode',
                        'backgroundColor', 'tintColor', 'isAccessibilityElement',
                        'accessibilityTraits', 'accessibilityLabel', 'accessibilityValue',
                        'userInteractionEnabled', 'translatesAutoresizingMaskIntoConstraints',
                        'autoresizingMask', 'transform', 'needsUpdateConstraints',
                        'data', 'count', 'length', 'description', 'class', 'superclass'):
                continue
            # 仅当该行存在 self.name 且 name 形如 ame 前缀（本仓自定义面）时报
            if name.startswith('ame') and re.search(rf'\bself\.{name}\b', line):
                # 检查是否其实有 getter 语义声明（interface extension 属性已在 props）
                issues.append((rel, ln, f"B self.{name} 非声明属性（疑手误）", line.strip()[:90]))

if issues:
    print(f"FAIL: {len(issues)} 处疑点")
    for rel, ln, kind, ctx in issues:
        print(f"  {rel}:{ln} [{kind}] {ctx}")
    sys.exit(1)
print("PASS: 五文件无 A/C/D 族雷；B 族（ame 前缀 self.xxx）零疑点")
