#!/usr/bin/env python3
# Task321 旧版升级自动迁移 + 兄弟迁移优化：12 键注册 en/zh-Hans/zh-CN/zh-Hant 四表
# （其余表走 en 回退链，Task318 同口径）。幂等：键已存在则整表跳过；追加位置 = 表尾。
# 注意：desc2 含两个位置占位符 %1$@/%2$@；ame321.migrate.done 含 4×%ld。
import os, re

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Natives', 'resources')

EN = r'''
/* Task321 legacy-upgrade auto migration + sibling migration optimization */
"welcome.data.sibling.desc2" = "Source: %1$@ · Size %2$@. One-tap migration into this launcher (source data is kept untouched).";
"welcome.data.sibling.kind.prisma1" = "Prisma 1.x (legacy)";
"welcome.data.sibling.kind.prisma2" = "Prisma 2 early layout";
"welcome.data.sibling.kind.plugins" = "Prisma (plugins era)";
"welcome.data.sibling.kind.legacy" = "Previous launcher (Air/upstream)";
"welcome.data.sibling.title.sync" = "Old data has updates";
"welcome.data.sibling.desc.sync" = "The source changed since the last migration — incremental sync keeps the newer side.";
"welcome.data.sibling.action.sync" = "Sync";
"welcome.data.sibling.confirm.smart" = "Smart merge (recommended)";
"welcome.data.sibling.confirm.overwrite" = "Full overwrite";
"ame321.migrate.done" = "Smart merge done: %ld new · %ld updated · %ld unchanged · %ld kept-newer. Restart the launcher to apply.";
"ame321.migrate.done.overwrite" = "Migrated %ld files (full overwrite). Restart the launcher to apply.";
'''

ZH = r'''
/* Task321 旧版升级自动迁移 + 兄弟迁移优化 */
"welcome.data.sibling.desc2" = "来源 %1$@，数据量 %2$@，可一键迁移到本启动器（源数据保留不动）。";
"welcome.data.sibling.kind.prisma1" = "Prisma 旧版（1.x）";
"welcome.data.sibling.kind.prisma2" = "Prisma 2 早期布局";
"welcome.data.sibling.kind.plugins" = "Prisma（插件期）";
"welcome.data.sibling.kind.legacy" = "旧版启动器（Air/上游）";
"welcome.data.sibling.title.sync" = "旧版数据有更新";
"welcome.data.sibling.desc.sync" = "上次迁移后源目录又有变化——增量同步会保留较新的一侧。";
"welcome.data.sibling.action.sync" = "增量同步";
"welcome.data.sibling.confirm.smart" = "智能合并（推荐）";
"welcome.data.sibling.confirm.overwrite" = "全量覆盖";
"ame321.migrate.done" = "智能合并完成：新增 %ld · 更新 %ld · 未变 %ld · 保留较新 %ld。重启启动器后生效。";
"ame321.migrate.done.overwrite" = "已迁移 %ld 个文件（全量覆盖）。重启启动器后生效。";
'''

# zh-Hant：繁体 + 台港用语（外掛/設定/網路/資料/佈局）
ZH_HANT = r'''
/* Task321 舊版升級自動遷移 + 兄弟遷移最佳化 */
"welcome.data.sibling.desc2" = "來源 %1$@，資料量 %2$@，可一鍵遷移到本啟動器（來源資料保留不動）。";
"welcome.data.sibling.kind.prisma1" = "Prisma 舊版（1.x）";
"welcome.data.sibling.kind.prisma2" = "Prisma 2 舊版佈局";
"welcome.data.sibling.kind.plugins" = "Prisma（外掛期）";
"welcome.data.sibling.kind.legacy" = "舊版啟動器（Air/上游）";
"welcome.data.sibling.title.sync" = "舊版資料有更新";
"welcome.data.sibling.desc.sync" = "上次遷移後來源又有變化——增量同步會保留較新的一側。";
"welcome.data.sibling.action.sync" = "增量同步";
"welcome.data.sibling.confirm.smart" = "智慧合併（建議）";
"welcome.data.sibling.confirm.overwrite" = "全量覆蓋";
"ame321.migrate.done" = "智慧合併完成：新增 %ld · 更新 %ld · 未變 %ld · 保留較新 %ld。重啟啟動器後生效。";
"ame321.migrate.done.overwrite" = "已遷移 %ld 個檔案（全量覆蓋）。重啟啟動器後生效。";
'''

TABLES = {'en': EN, 'zh-Hans': ZH, 'zh-CN': ZH, 'zh-Hant': ZH_HANT}

def keys_of(block):
    return set(re.findall(r'"(welcome\.data\.sibling\.[a-zA-Z0-9_.]+|ame321\.migrate\.done(?:\.overwrite)?)"', block))

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
