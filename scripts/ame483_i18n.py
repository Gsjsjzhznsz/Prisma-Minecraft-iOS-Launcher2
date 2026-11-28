#!/usr/bin/env python3
# Task483 i18n：单根终局 UI 文案，四表一致追加（幂等：已存在即跳过）
# 键：ame483.gamedir.single_root_hint（LauncherPrefGameDirViewController 页脚）
import os

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives', 'resources')

TABLES = {
    'en': [
        ('ame483.gamedir.single_root_hint', 'Single game directory is active (the instances multi-directory layout is retired); all game data now lives under Library/Application Support/minecraft'),
        ('ai.instance.single_root_rejected', 'Single real root is active (Task483): the instances multi-directory layout is retired; creating or switching game directories is no longer supported. Existing data has been consolidated under Library/Application Support/minecraft.'),
    ],
    'zh-Hans': [
        ('ame483.gamedir.single_root_hint', '单一游戏目录已启用（instances 多目录布局已退役），游戏数据统一存放在 Library/Application Support/minecraft'),
        ('ai.instance.single_root_rejected', '单一真实根已生效（Task483）：instances 多目录布局已退役，新建/切换游戏目录不再受支持；现有数据已统一收编到 Library/Application Support/minecraft。'),
    ],
    'zh-CN': [
        ('ame483.gamedir.single_root_hint', '单一游戏目录已启用（instances 多目录布局已退役），游戏数据统一存放在 Library/Application Support/minecraft'),
        ('ai.instance.single_root_rejected', '单一真实根已生效（Task483）：instances 多目录布局已退役，新建/切换游戏目录不再受支持；现有数据已统一收编到 Library/Application Support/minecraft。'),
    ],
    'zh-Hant': [
        ('ame483.gamedir.single_root_hint', '單一遊戲目錄已啟用（instances 多目錄布局已退役），遊戲資料統一存放在 Library/Application Support/minecraft'),
        ('ai.instance.single_root_rejected', '單一真實根已生效（Task483）：instances 多目錄布局已退役，新建/切換遊戲目錄不再受支援；現有資料已統一收編到 Library/Application Support/minecraft。'),
    ],
}

def main():
    fails = 0
    for lang, keys in TABLES.items():
        path = os.path.join(NAT, f'{lang}.lproj', 'Localizable.strings')
        text = open(path, encoding='utf-8').read()
        added = 0
        with open(path, 'a', encoding='utf-8') as f:
            for k, v in keys:
                line = f'"{k}" = "{v}";\n'
                if f'"{k}"' in text:
                    print(f'SKIP {lang} {k} (exists)')
                    continue
                f.write(line)
                added += 1
        print(f'{lang}: +{added} keys')

if __name__ == '__main__':
    main()
