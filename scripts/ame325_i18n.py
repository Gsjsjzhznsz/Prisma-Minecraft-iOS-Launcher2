#!/usr/bin/env python3
# Task325 控件仓库页 ZL2 新 UI：3 徽章短键注册 en/zh-Hans/zh-CN/zh-Hant 四表
# （其余表走 en 回退链，Task318 同口径）。幂等：键已存在则整表跳过；追加位置 = 表尾。
# 键：dl.controls.repo.download / dl.controls.repo.update / custom_controls.repo.installed_badge
import os, re

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Natives', 'resources')

EN = r'''
/* Task325 control repo ZL2 card action badges */
"dl.controls.repo.download" = "Download";
"dl.controls.repo.update" = "Update";
"custom_controls.repo.installed_badge" = "Installed";
'''

ZH = r'''
/* Task325 控件仓库 ZL2 卡片动作徽章 */
"dl.controls.repo.download" = "下载";
"dl.controls.repo.update" = "更新";
"custom_controls.repo.installed_badge" = "已安装";
'''

ZH_HANT = r'''
/* Task325 控件倉庫 ZL2 卡片動作徽章 */
"dl.controls.repo.download" = "下載";
"dl.controls.repo.update" = "更新";
"custom_controls.repo.installed_badge" = "已安裝";
'''

TABLES = {'en': EN, 'zh-Hans': ZH, 'zh-CN': ZH, 'zh-Hant': ZH_HANT}

def keys_of(block):
    return set(re.findall(r'"(dl\.controls\.repo\.(?:download|update)|custom_controls\.repo\.installed_badge)"', block))

def existing_keys(text):
    return set(re.findall(r'"([a-zA-Z0-9_.-]+)"\s*=', text))

report = []
for lang, block in TABLES.items():
    path = os.path.join(RES, lang + '.lproj', 'Localizable.strings')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    have = existing_keys(content)
    need = keys_of(block)
    dup = sorted(need & have)
    if dup:
        report.append(f"{lang}: SKIP {len(dup)} already-present keys {dup[:3]}...")
        continue
    if not content.endswith('\n'):
        content += '\n'
    content += block.lstrip('\n').rstrip() + '\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    report.append(f"{lang}: +{len(need)} keys")

print('\n'.join(report))
