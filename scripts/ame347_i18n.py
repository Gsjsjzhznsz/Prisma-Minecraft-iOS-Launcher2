#!/usr/bin/env python3
# Task347 i18n：导入脉柱救援摘要两键，54 表一致追加（幂等：已存在即跳过）。
# 覆盖口径沿用 ame345 判例：en/zh-Hans/zh-CN/zh-Hant 给译文，其余 50 表
# 落英文兜底（与 ame345.import.prefs_missing 存量形态逐位一致）。
import os

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives', 'resources')

KEYS = {
    'en': [
        ('ame347.import.spine_v1',
         'Launcher settings restored from legacy backup preferences (launcher_preferences.plist)'),
        ('ame347.import.spine_kept',
         'Launcher preferences in backup are empty/corrupt -- current settings kept'),
    ],
    'zh-Hans': [
        ('ame347.import.spine_v1',
         '已从一代备份设置（launcher_preferences.plist）迁移恢复启动器设置'),
        ('ame347.import.spine_kept',
         '备份中的启动器设置文件为空/损坏——已保留当前设置'),
    ],
    'zh-CN': [
        ('ame347.import.spine_v1',
         '已从一代备份设置（launcher_preferences.plist）迁移恢复启动器设置'),
        ('ame347.import.spine_kept',
         '备份中的启动器设置文件为空/损坏——已保留当前设置'),
    ],
    'zh-Hant': [
        ('ame347.import.spine_v1',
         '已從一代備份設定（launcher_preferences.plist）遷移恢復啟動器設定'),
        ('ame347.import.spine_kept',
         '備份中的啟動器設定檔為空/損壞——已保留目前設定'),
    ],
}
FALLBACK = KEYS['en']   # 其余 50 表英文兜底（ame345 判例口径）

def main():
    fails = 0
    tables = sorted(d for d in os.listdir(NAT) if d.endswith('.lproj'))
    for lproj in tables:
        lang = lproj[:-len('.lproj')]
        path = os.path.join(NAT, lproj, 'Localizable.strings')
        if not os.path.isfile(path):
            print(f'SKIP {lang} (no Localizable.strings)')
            continue
        keys = KEYS.get(lang, FALLBACK)
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
    return fails

if __name__ == '__main__':
    main()
