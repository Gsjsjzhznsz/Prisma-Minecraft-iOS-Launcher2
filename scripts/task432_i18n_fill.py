#!/usr/bin/env python3
"""Task432 i18n 填表 —— 本轮新增 ame432.* 键四主表落表（en/zh-Hans/zh-CN/zh-Hant）。

家法：
  1. 代码键集闭合校验：扫描 Natives/**/*.m 的 localize(@"ame432.KEY", @"默认")，
     任何代码键不在字典 → 列出并 FAIL（防漏键）。
  2. 四表等量插入：zh-CN 镜像 zh-Hans（本轮新键无地区差异变体），键序按字典序。
  3. 落表后复核：四表键数一致 + 代码键全部在表。
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLES = {
    "en": ROOT / "Natives/resources/en.lproj/Localizable.strings",
    "zh-Hans": ROOT / "Natives/resources/zh-Hans.lproj/Localizable.strings",
    "zh-CN": ROOT / "Natives/resources/zh-CN.lproj/Localizable.strings",
    "zh-Hant": ROOT / "Natives/resources/zh-Hant.lproj/Localizable.strings",
}

# 键名 -> (英文, 简体, 繁体)。简体默认值以代码内联为准（第六工位报告口径）。
DICT = {
    # ── SA 工位（ModpackImport 文件夹导入 6 键）────────────────────
    "ame432.import.folder.button": ("Import Folder", "导入文件夹", "匯入資料夾"),
    "ame432.import.folder.packing": ("Packing folder…", "正在打包文件夹…", "正在打包資料夾…"),
    "ame432.import.folder.unrecognized": ("Not a MultiMC/Prism instance (mmc-pack.json / instance.cfg not found)",
        "所选文件夹不是 MultiMC/Prism 整合包实例（未找到 mmc-pack.json / instance.cfg）",
        "所選資料夾不是 MultiMC/Prism 整合包實例（未找到 mmc-pack.json / instance.cfg）"),
    "ame432.import.folder.failed": ("Failed to pack folder: %@", "文件夹打包失败：%@", "資料夾打包失敗：%@"),
    "ame432.import.folder.failed.plain": ("Failed to pack folder", "文件夹打包失败", "資料夾打包失敗"),
    "ame432.import.folder.failed.title": ("Cannot Import Folder", "无法导入文件夹", "無法匯入資料夾"),
    # ── SC 工位（设置页尾部入口 2 键）────────────────────────────
    "ame432.settab.ai_tail": ("AI Settings", "AI 设置", "AI 設定"),
    "ame432.settab.debug_tail": ("Debug", "调试", "除錯"),
    # ── SD 工位（主题 5 + 布局卡 22 + 许可证 2 = 29 键）──────────
    "ame432.theme.mode.title": ("Light & Dark Mode", "深浅模式", "深淺模式"),
    "ame432.theme.mode.subtitle": ("Follow System / Light / Dark", "跟随系统 / 浅色 / 深色", "跟隨系統 / 淺色 / 深色"),
    "ame432.f.palette.subtitle": ("Follow wallpaper, or pick a named palette (incl. Jade Breeze / Rosy Sunset)",
        "跟随背景自动取色，或选择命名色板（含翠风/霞紫）", "跟隨背景自動取色，或選擇命名色板（含翠風/霞紫）"),
    "ame432.f.palette.jade": ("Jade Breeze", "翠风", "翠風"),
    "ame432.f.palette.rosy": ("Rosy Sunset", "霞紫", "霞紫"),
    "ame432.layouts.empty": ("No layout cards yet", "暂无布局卡", "暫無佈局卡"),
    "ame432.layouts.empty.subtitle": ("Use New Layout / Import Layout File below, or the Control Repo",
        "用下方「新建布局 / 导入布局文件」或控件仓库补齐", "用下方「新建佈局 / 匯入佈局檔」或控件倉庫補齊"),
    "ame432.layouts.create": ("New Layout", "新建布局", "新建佈局"),
    "ame432.layouts.create.subtitle": ("Create an empty layout from the factory template",
        "以出厂模板创建空白布局（可在编辑器中添加控件）", "以出廠模板建立空白佈局（可在編輯器中添加控件）"),
    "ame432.layouts.create.name.placeholder": ("Layout name", "布局名称", "佈局名稱"),
    "ame432.layouts.create.error.empty": ("Layout name cannot be empty", "布局名称不能为空", "佈局名稱不能為空"),
    "ame432.layouts.create.error.duplicate": ("A layout with this name already exists",
        "同名布局已存在，换一个名称", "同名佈局已存在，換一個名稱"),
    "ame432.layouts.create.error.write": ("Failed to write layout (disk or permission)",
        "布局写入失败（磁盘或权限）", "佈局寫入失敗（磁碟或權限）"),
    "ame432.layouts.import": ("Import Layout File", "导入布局文件", "匯入佈局檔"),
    "ame432.layouts.import.subtitle": ("Import a .json (validated as parseable before entering controlmap)",
        "从文件导入 .json（校验可解析后才入库 controlmap）", "從檔案匯入 .json（校驗可解析後才入庫 controlmap）"),
    "ame432.layouts.import.error.parse": ("Not a parseable layout JSON (or version above supported)",
        "导入失败：所选文件不是可解析的布局 JSON（或版本高于当前支持）",
        "匯入失敗：所選檔案不是可解析的佈局 JSON（或版本高於當前支援）"),
    "ame432.layouts.import.error.copy": ("Cannot write to the controlmap directory",
        "导入失败：无法写入 controlmap 目录", "匯入失敗：無法寫入 controlmap 目錄"),
    "ame432.layouts.import.default.name": ("Imported Layout", "导入布局", "匯入佈局"),
    "ame432.layouts.import.done": ("Imported: %@", "导入成功：%@", "匯入成功：%@"),
    "ame432.layouts.delete": ("Delete Layout", "删除布局", "刪除佈局"),
    "ame432.layouts.delete.subtitle": ("Pick from list + confirm before deletion",
        "删除 controlmap 中的布局文件（删档前列表选择 + 确认）", "刪除 controlmap 中的佈局檔案（刪檔前清單選擇 + 確認）"),
    "ame432.layouts.delete.pick": ("Pick a layout to delete", "选择要删除的布局", "選擇要刪除的佈局"),
    "ame432.layouts.delete.confirm": ("Delete layout \u201c%@\u201d? This cannot be undone.",
        "确定删除布局「%@」？该操作不可撤销。", "確定刪除佈局「%@」？該操作不可撤銷。"),
    "ame432.layouts.delete.confirm.default": ("\n\nNote: this is the current default layout; the factory custom.json will fall back after deletion.",
        "\n\n注意：这是当前默认布局，删除后将回落出厂布局 custom.json。",
        "\n\n注意：這是當前預設佈局，刪除後將回落出廠佈局 custom.json。"),
    "ame432.layouts.delete.error.empty": ("No deletable layouts", "暂无可删除的布局", "暫無可刪除的佈局"),
    "ame432.layouts.delete.error.failed": ("Delete failed (file missing or in use)",
        "删除失败（文件不存在或被占用）", "刪除失敗（檔案不存在或被佔用）"),
    "ame432.layouts.card.buttons": ("%lu buttons", "%lu 个按钮", "%lu 個按鈕"),
    "ame432.layouts.card.current": ("Current default · %@", "当前默认 · %@", "當前預設 · %@"),
    "ame432.layouts.card.current.short": ("Current default", "当前默认", "當前預設"),
    "ame432.layouts.card.unparsed": ("Layout file unparsable", "布局文件无法解析", "佈局檔案無法解析"),
    "ame432.about.license.title": ("Open-source Licenses", "开源许可证", "開源許可證"),
    "ame432.about.license.view": ("View full license text", "查看许可证全文", "查看許可證全文"),
    # ── SB1 工位（修改版本 20 + 数据包 9 = 29 键）─────────────────
    "ame432.vdet.modify": ("Modify Version", "修改版本", "修改版本"),
    "ame432.vdet.modify.instance": ("Instance", "实例", "實例"),
    "ame432.vdet.modify.mc_version": ("MC Version", "MC 版本", "MC 版本"),
    "ame432.vdet.modify.current_loader": ("Current Loader", "当前加载器", "當前載入器"),
    "ame432.vdet.modify.family_title": ("Target loader (tap to pick a version)", "目标加载器（点击选择版本后安装）", "目標載入器（點擊選擇版本後安裝）"),
    "ame432.vdet.modify.loader_none": ("Vanilla (no loader installed)", "原版（未装加载器）", "原版（未裝載入器）"),
    "ame432.vdet.modify.family.vanilla": ("Vanilla", "原版", "原版"),
    "ame432.vdet.modify.current_fmt": ("Current %@", "当前 %@", "當前 %@"),
    "ame432.vdet.modify.tap_hint": ("Tap to pick a version", "点击选择版本", "點擊選擇版本"),
    "ame432.vdet.modify.unsupported": ("Not supported yet", "暂不支持", "暫不支援"),
    "ame432.vdet.modify.no_base": ("No MC version installed for this instance", "实例尚未安装 MC 版本，无法修改加载器", "實例尚未安裝 MC 版本，無法修改載入器"),
    "ame432.vdet.modify.versions_loading": ("Fetching available %@ versions…", "正在获取 %@ 可用版本…", "正在獲取 %@ 可用版本…"),
    "ame432.vdet.modify.no_versions": ("No available versions (network error or unsupported MC version)",
        "暂无可用版本（网络异常或该 MC 版本不受支持）", "暫無可用版本（網路異常或該 MC 版本不受支援）"),
    "ame432.vdet.modify.pick_version_title": ("Choose %@ version", "选择 %@ 版本", "選擇 %@ 版本"),
    "ame432.vdet.modify.confirm_title": ("Confirm Install", "确认安装", "確認安裝"),
    "ame432.vdet.modify.confirm_body": ("Install %@ %@ (MC %@) for instance \u201c%@\u201d? After success the instance points to the new version entity; the old one is kept.",
        "将为实例「%@」安装 %@ %@（MC %@）。\n安装成功后实例指向新版本实体，旧版本实体保留。",
        "將為實例「%@」安裝 %@ %@（MC %@）。\n安裝成功後實例指向新版本實體，舊版本實體保留。"),
    "ame432.vdet.modify.confirm_install": ("Install", "安装", "安裝"),
    "ame432.vdet.modify.installing": ("Installing %@ %@…", "正在安装 %@ %@…", "正在安裝 %@ %@…"),
    "ame432.vdet.modify.install_ok": ("Installed %@ (version entity %@)", "已安装 %@（版本实体 %@）", "已安裝 %@（版本實體 %@）"),
    "ame432.vdet.modify.install_failed": ("Install failed", "安装失败", "安裝失敗"),
    "ame432.vdet.datapacks.entry": ("Data Packs", "数据包", "資料包"),
    "ame432.vdet.datapacks.entry_hint": ("Managed per world directory", "世界目录内管理", "世界目錄內管理"),
    "ame432.vdet.datapacks.no_world": ("No saves yet (data packs live in each world's directory)",
        "暂无存档（数据包位于世界存档目录内）", "暫無存檔（資料包位於世界存檔目錄內）"),
    "ame432.vdet.datapacks.pick_world": ("Choose a world to manage data packs", "选择要管理数据包的世界", "選擇要管理資料包的世界"),
    "ame432.vdet.datapacks.world_fmt": ("World: %@", "世界：%@", "世界：%@"),
    "ame432.vdet.datapacks.import": ("Import data pack", "导入数据包", "匯入資料包"),
    "ame432.vdet.datapacks.empty": ("No data packs yet. Tap top-right to import a zip or folder.",
        "暂无数据包。点右上角导入 zip 或文件夹。", "暫無資料包。點右上角匯入 zip 或資料夾。"),
    "ame432.vdet.datapacks.dir_tag": ("Folder", "目录", "資料夾"),
    "ame432.vdet.datapacks.delete_confirm": ("Delete data pack \u201c%@\u201d? This cannot be undone.",
        "删除数据包「%@」？该操作不可撤销。", "刪除資料包「%@」？該操作不可撤銷。"),
    # ── SB2 工位（SearchId 闭环 3 键）────────────────────────────
    "ame432.searchid.gallery": ("Screenshots", "截图", "截圖"),
    "ame432.searchid.go_download": ("Go to Download", "前往下载", "前往下載"),
    "ame432.searchid.mcmod": ("Search mcmod.cn (Chinese docs)", "mcmod 中文资料搜索", "mcmod 中文資料搜尋"),
}


def scan_code_keys():
    """扫描 Natives/**/*.m 提取 localize(@"ame432.KEY") 键集（多行调用容错）。"""
    pat = re.compile(r'localize\(@"(ame432\.[A-Za-z0-9_.]+)"')
    keys = set()
    for p in ROOT.glob("Natives/**/*.m"):
        t = p.read_text(encoding="utf-8", errors="replace")
        keys |= set(pat.findall(t))
    return keys


def load_table_keys(path):
    t = path.read_text(encoding="utf-8")
    return set(re.findall(r'^"((?:[^"\\]|\\.)+)"\s*=', t, re.M))


def esc(v):
    # 真实换行 → \n 转义（.strings 规范形态）；先转义既有反斜杠与引号。
    return v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
    code_keys = scan_code_keys()
    missing = sorted(code_keys - set(DICT))
    if missing:
        print("FAIL 代码键缺译文字典:", missing)
        sys.exit(2)

    tables = {name: p.read_text(encoding="utf-8") for name, p in TABLES.items()}
    before = {name: load_table_keys(p) for name, p in TABLES.items()}

    added = []
    for key in sorted(DICT):
        if key in before["en"]:
            continue  # 既有键跳过（幂等）
        en, hans, hant = DICT[key]
        zhcn = hans  # 本轮新键 zh-CN 镜像简体
        blocks = {"en": en, "zh-Hans": hans, "zh-CN": zhcn, "zh-Hant": hant}
        for name, val in blocks.items():
            tables[name] += '\n"%s" = "%s";\n' % (key, esc(val))
        added.append(key)

    for name, p in TABLES.items():
        p.write_text(tables[name], encoding="utf-8")

    after = {name: load_table_keys(TABLES[name]) for name in TABLES}
    counts = {name: len(after[name]) for name in after}
    parity = len(set(counts.values())) == 1
    leftover = sorted(code_keys - after["en"])

    print("keys_in_code:", len(code_keys))
    print("added:", len(added))
    print("table_key_counts:", counts)
    print("parity:", "PASS" if parity else "FAIL")
    print("code_keys_missing_from_tables:", leftover if leftover else "0")
    if not parity or leftover:
        sys.exit(3)
    print("Task432 i18n fill ALL GREEN")


if __name__ == "__main__":
    main()
