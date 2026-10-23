#!/usr/bin/env python3
# Task318：ame318.* 内置插件仓库键注册 en/zh-Hans/zh-CN/zh-Hant 四表（其余 50 表走 en 回退链）
# 幂等：键已存在则跳过；追加位置 = 表尾
# 注意：键名含连字符（builtin.<plugin-id>），existing_keys 正则须含 '-'
import os, re

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Natives', 'resources')

EN = r'''
/* Task318 builtin plugin store (ZL2PluginRepoViewController) */
"ame318.repo.title" = "Plugin Store";
"ame318.repo.nav" = "Store";
"ame318.repo.entry_subtitle" = "Browse and one-tap install bundled plugins";
"ame318.repo.section_title" = "Bundled plugins";
"ame318.repo.empty" = "No bundled plugins found.";
"ame318.repo.install" = "Install";
"ame318.repo.installing" = "Installing…";
"ame318.repo.reinstall_body" = "This plugin is already installed — reinstalling overwrites it and clears the plugin's private storage.";
"ame318.repo.zip_failed" = "Failed to package the bundled plugin (zip error).";
/* Task318 bundled plugin display names/descriptions (manifest fallback) */
"ame318.builtin.theme-sunset.name" = "Sunset Themes";
"ame318.builtin.theme-sunset.desc" = "Four curated palettes with one-tap apply, cycling and reset. Theme override is high-risk: grant it on the plugin detail page.";
"ame318.builtin.renderer-quickswitch.name" = "Renderer Quick Switch";
"ame318.builtin.renderer-quickswitch.desc" = "Cycle installed renderers and inspect the current backend.";
"ame318.builtin.launch-counter.name" = "Launch Stats";
"ame318.builtin.launch-counter.desc" = "Count game launches and the last exit code (stored privately).";
"ame318.builtin.modrinth-hot.name" = "Modrinth Trending";
"ame318.builtin.modrinth-hot.desc" = "Fetch Modrinth's top five mods by downloads (requires network).";
'''

ZH = r'''
/* Task318 内置插件仓库（ZL2PluginRepoViewController） */
"ame318.repo.title" = "插件仓库";
"ame318.repo.nav" = "仓库";
"ame318.repo.entry_subtitle" = "浏览并一键安装内置预置插件";
"ame318.repo.section_title" = "内置插件";
"ame318.repo.empty" = "未找到内置插件。";
"ame318.repo.install" = "安装";
"ame318.repo.installing" = "安装中…";
"ame318.repo.reinstall_body" = "该插件已安装——此次安装为覆盖更新，插件私有存储会被清空。";
"ame318.repo.zip_failed" = "打包内置插件失败（zip 写入错误）。";
/* Task318 内置插件展示名/简介（manifest 兜底） */
"ame318.builtin.theme-sunset.name" = "日落主题包";
"ame318.builtin.theme-sunset.desc" = "四套精选配色一键换肤，支持循环切换与恢复默认。主题覆盖属高危权限：请在插件详情页授权。";
"ame318.builtin.renderer-quickswitch.name" = "渲染器快切";
"ame318.builtin.renderer-quickswitch.desc" = "在已安装渲染器间循环切换并查看当前后端。";
"ame318.builtin.launch-counter.name" = "启动统计";
"ame318.builtin.launch-counter.desc" = "统计游戏启动次数与最近退出码，数据仅存本插件私有存储。";
"ame318.builtin.modrinth-hot.name" = "Modrinth 热门榜";
"ame318.builtin.modrinth-hot.desc" = "联网拉取 Modrinth 下载量前五的模组（需联网权限）。";
'''

# zh-Hant：繁体 + 台港用语（外掛/設定/網路/資料）
ZH_HANT = r'''
/* Task318 內建外掛倉庫（ZL2PluginRepoViewController） */
"ame318.repo.title" = "外掛倉庫";
"ame318.repo.nav" = "倉庫";
"ame318.repo.entry_subtitle" = "瀏覽並一鍵安裝內建預置外掛";
"ame318.repo.section_title" = "內建外掛";
"ame318.repo.empty" = "未找到內建外掛。";
"ame318.repo.install" = "安裝";
"ame318.repo.installing" = "安裝中…";
"ame318.repo.reinstall_body" = "該外掛已安裝——此次安裝為覆蓋更新，外掛私有儲存會被清空。";
"ame318.repo.zip_failed" = "打包內建外掛失敗（zip 寫入錯誤）。";
/* Task318 內建外掛顯示名/簡介（manifest 兜底） */
"ame318.builtin.theme-sunset.name" = "日落主題包";
"ame318.builtin.theme-sunset.desc" = "四套精選配色一鍵換膚，支援循環切換與恢復預設。主題覆寫屬高風險權限：請在外掛詳情頁授權。";
"ame318.builtin.renderer-quickswitch.name" = "渲染器快切";
"ame318.builtin.renderer-quickswitch.desc" = "在已安裝渲染器間循環切換並查看目前後端。";
"ame318.builtin.launch-counter.name" = "啟動統計";
"ame318.builtin.launch-counter.desc" = "統計遊戲啟動次數與最近結束代碼，資料僅存本外掛私有儲存。";
"ame318.builtin.modrinth-hot.name" = "Modrinth 熱門榜";
"ame318.builtin.modrinth-hot.desc" = "連網抓取 Modrinth 下載量前五的模組（需網路權限）。";
'''

TABLES = {'en': EN, 'zh-Hans': ZH, 'zh-CN': ZH, 'zh-Hant': ZH_HANT}

def keys_of(block):
    return set(re.findall(r'"(ame318\.[a-zA-Z0-9_.-]+)"', block))

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
