#!/usr/bin/env python3
# Task317：ame317.* 插件系统键注册 en/zh-Hans/zh-CN/zh-Hant 四表（其余 50 表走 en 回退链）
# 幂等：键已存在则跳过；追加位置 = 表尾
import os, re

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Natives', 'resources')

EN = r'''
/* Task317 plugin system (AmePlugin) */
"ame317.list.title" = "Plugins";
"ame317.settings.entry_subtitle" = "Install plugin packages, manage permissions and runtime state";
"ame317.list.section_installed" = "Installed plugins";
"ame317.list.section_rows" = "Launcher rows from plugins";
"ame317.list.section_about" = "About";
"ame317.list.empty" = "No plugins installed. Import a .ameplugin package to get started.";
"ame317.list.by_author" = "by %@";
"ame317.list.from_plugin" = "From plugin";
"ame317.list.api_line" = "Plugin API version: %ld";
"ame317.install.failed_title" = "Install failed";
"ame317.install.err_zip" = "Cannot read the .ameplugin package (damaged or not a zip archive).";
"ame317.install.err_manifest" = "manifest.json was not found at the package root.";
"ame317.install.err_json" = "manifest.json is not valid JSON.";
"ame317.install.err_schema" = "manifest.json has missing or invalid fields (or unregistered permission ids).";
"ame317.install.err_entry" = "Entry script missing or its path escapes the package.";
"ame317.install.err_api" = "The plugin requires a newer plugin API version than this launcher provides.";
"ame317.install.err_move" = "Failed to write the plugin into the plugins folder.";
"ame317.install.no_perms" = "No permissions declared";
"ame317.install.confirm_body" = "This plugin requests the following permissions:";
"ame317.detail.section_info" = "Info";
"ame317.detail.section_runtime" = "Runtime";
"ame317.detail.section_perms" = "Permissions";
"ame317.detail.enabled" = "Enable plugin";
"ame317.detail.broken" = "Broken manifest";
"ame317.detail.not_declared" = "Not declared in manifest (%@)";
"ame317.detail.uninstall" = "Uninstall plugin";
"ame317.detail.uninstall_confirm_title" = "Uninstall plugin?";
"ame317.detail.uninstall_confirm_body" = "\"%@\" and its granted permissions will be removed. This cannot be undone.";
"ame317.bridge.denied" = "[ame] permission denied: plugin %@ has no grant for %@";
"ame317.bridge.invalid_value" = "[ame] invalid value: %@";
"ame317.bridge.bad_url" = "[ame] invalid URL";
"ame317.common.ok" = "OK";
/* Task317 permission groups */
"ame317.perm.events.name" = "Launcher events";
"ame317.perm.events.desc" = "Receive launcher events such as app launch, game start/exit, and app foreground/background";
"ame317.perm.ui.dialog.name" = "Show dialogs";
"ame317.perm.ui.dialog.desc" = "Display dialogs and toasts on behalf of the plugin";
"ame317.perm.ui.rows.name" = "Add launcher rows";
"ame317.perm.ui.rows.desc" = "Contribute tappable rows to the launcher home page";
"ame317.perm.ui.theme.name" = "Override theme";
"ame317.perm.ui.theme.desc" = "Override launcher color tokens (may change appearance) — high risk";
"ame317.perm.settings.read.name" = "Read settings";
"ame317.perm.settings.read.desc" = "Read launcher preferences (read-only)";
"ame317.perm.settings.write.name" = "Modify settings";
"ame317.perm.settings.write.desc" = "Change launcher preferences — high risk";
"ame317.perm.renderer.read.name" = "Read renderer config";
"ame317.perm.renderer.read.desc" = "Read the current renderer and backend selection";
"ame317.perm.renderer.write.name" = "Switch renderer";
"ame317.perm.renderer.write.desc" = "Change the graphics renderer/backend — wrong values cause a black screen — high risk";
"ame317.perm.profile.read.name" = "Read profiles";
"ame317.perm.profile.read.desc" = "Read the list of game profiles/instances";
"ame317.perm.storage.name" = "Private storage";
"ame317.perm.storage.desc" = "Private key-value storage scoped to this plugin";
"ame317.perm.net.name" = "Network access";
"ame317.perm.net.desc" = "Send network requests to arbitrary URLs — high risk";
'''

ZH = r'''
/* Task317 插件系统（AmePlugin） */
"ame317.list.title" = "插件";
"ame317.settings.entry_subtitle" = "安装插件包，管理权限与运行状态";
"ame317.list.section_installed" = "已安装插件";
"ame317.list.section_rows" = "插件贡献的启动器行";
"ame317.list.section_about" = "关于";
"ame317.list.empty" = "尚未安装插件。导入 .ameplugin 插件包开始使用。";
"ame317.list.by_author" = "作者 %@";
"ame317.list.from_plugin" = "来自插件";
"ame317.list.api_line" = "插件 API 版本：%ld";
"ame317.install.failed_title" = "安装失败";
"ame317.install.err_zip" = "无法读取 .ameplugin 包（已损坏或非 zip 存档）。";
"ame317.install.err_manifest" = "包根部未找到 manifest.json。";
"ame317.install.err_json" = "manifest.json 不是有效 JSON。";
"ame317.install.err_schema" = "manifest.json 字段缺失或非法（含未注册的权限 id）。";
"ame317.install.err_entry" = "入口脚本缺失或路径越界。";
"ame317.install.err_api" = "插件要求的插件 API 版本高于本启动器。";
"ame317.install.err_move" = "插件写入 plugins 目录失败。";
"ame317.install.no_perms" = "未声明任何权限";
"ame317.install.confirm_body" = "该插件申请以下权限：";
"ame317.detail.section_info" = "信息";
"ame317.detail.section_runtime" = "运行";
"ame317.detail.section_perms" = "权限";
"ame317.detail.enabled" = "启用插件";
"ame317.detail.broken" = "清单损坏";
"ame317.detail.not_declared" = "未在清单声明（%@）";
"ame317.detail.uninstall" = "卸载插件";
"ame317.detail.uninstall_confirm_title" = "卸载插件？";
"ame317.detail.uninstall_confirm_body" = "「%@」及其已授权限将被移除，此操作不可撤销。";
"ame317.bridge.denied" = "[ame] 权限被拒：插件 %@ 未获授权 %@";
"ame317.bridge.invalid_value" = "[ame] 非法值：%@";
"ame317.bridge.bad_url" = "[ame] 无效 URL";
"ame317.common.ok" = "好";
/* Task317 权限组 */
"ame317.perm.events.name" = "启动器事件";
"ame317.perm.events.desc" = "接收启动器启动、游戏开始/退出、前后台切换等事件";
"ame317.perm.ui.dialog.name" = "显示弹窗";
"ame317.perm.ui.dialog.desc" = "允许插件弹出对话框与轻提示";
"ame317.perm.ui.rows.name" = "添加启动器行";
"ame317.perm.ui.rows.desc" = "允许插件向主页贡献可点按的入口行";
"ame317.perm.ui.theme.name" = "覆盖主题";
"ame317.perm.ui.theme.desc" = "允许插件覆盖启动器配色令牌（可能改变外观）——高危";
"ame317.perm.settings.read.name" = "读取设置";
"ame317.perm.settings.read.desc" = "读取启动器偏好设置（只读）";
"ame317.perm.settings.write.name" = "修改设置";
"ame317.perm.settings.write.desc" = "允许插件更改启动器偏好——高危";
"ame317.perm.renderer.read.name" = "读取渲染器配置";
"ame317.perm.renderer.read.desc" = "读取当前渲染器与后端选择";
"ame317.perm.renderer.write.name" = "切换渲染器";
"ame317.perm.renderer.write.desc" = "允许插件更改图形渲染器/后端——错误取值将导致黑屏，高危";
"ame317.perm.profile.read.name" = "读取配置档";
"ame317.perm.profile.read.desc" = "读取游戏实例/配置档列表";
"ame317.perm.storage.name" = "私有存储";
"ame317.perm.storage.desc" = "插件专属的键值存储（与其他插件隔离）";
"ame317.perm.net.name" = "网络访问";
"ame317.perm.net.desc" = "允许插件向任意地址发送网络请求——高危";
'''

# zh-Hant：繁体 + 台港用语（設定/網路/彈出視窗/訊息）
ZH_HANT = r'''
/* Task317 外掛系統（AmePlugin） */
"ame317.list.title" = "外掛";
"ame317.settings.entry_subtitle" = "安裝外掛套件，管理權限與執行狀態";
"ame317.list.section_installed" = "已安裝外掛";
"ame317.list.section_rows" = "外掛貢獻的啟動器列";
"ame317.list.section_about" = "關於";
"ame317.list.empty" = "尚未安裝外掛。匯入 .ameplugin 外掛套件即可開始使用。";
"ame317.list.by_author" = "作者 %@";
"ame317.list.from_plugin" = "來自外掛";
"ame317.list.api_line" = "外掛 API 版本：%ld";
"ame317.install.failed_title" = "安裝失敗";
"ame317.install.err_zip" = "無法讀取 .ameplugin 套件（已損壞或非 zip 存檔）。";
"ame317.install.err_manifest" = "套件根部未找到 manifest.json。";
"ame317.install.err_json" = "manifest.json 不是有效 JSON。";
"ame317.install.err_schema" = "manifest.json 欄位缺失或非法（含未註冊的權限 id）。";
"ame317.install.err_entry" = "進入點腳本缺失或路徑越界。";
"ame317.install.err_api" = "外掛要求的外掛 API 版本高於本啟動器。";
"ame317.install.err_move" = "外掛寫入 plugins 目錄失敗。";
"ame317.install.no_perms" = "未宣告任何權限";
"ame317.install.confirm_body" = "該外掛申請以下權限：";
"ame317.detail.section_info" = "資訊";
"ame317.detail.section_runtime" = "執行";
"ame317.detail.section_perms" = "權限";
"ame317.detail.enabled" = "啟用外掛";
"ame317.detail.broken" = "清單損壞";
"ame317.detail.not_declared" = "未在清單宣告（%@）";
"ame317.detail.uninstall" = "解除安裝外掛";
"ame317.detail.uninstall_confirm_title" = "解除安裝外掛？";
"ame317.detail.uninstall_confirm_body" = "「%@」及其已授權限將被移除，此操作無法復原。";
"ame317.bridge.denied" = "[ame] 權限被拒：外掛 %@ 未取得授權 %@";
"ame317.bridge.invalid_value" = "[ame] 非法值：%@";
"ame317.bridge.bad_url" = "[ame] 無效 URL";
"ame317.common.ok" = "好";
/* Task317 權限群組 */
"ame317.perm.events.name" = "啟動器事件";
"ame317.perm.events.desc" = "接收啟動器啟動、遊戲開始/結束、前景/背景切換等事件";
"ame317.perm.ui.dialog.name" = "顯示對話框";
"ame317.perm.ui.dialog.desc" = "允許外掛彈出對話框與輕量提示";
"ame317.perm.ui.rows.name" = "新增啟動器列";
"ame317.perm.ui.rows.desc" = "允許外掛向主頁貢獻可點按的入口列";
"ame317.perm.ui.theme.name" = "覆寫主題";
"ame317.perm.ui.theme.desc" = "允許外掛覆寫啟動器配色權杖（可能改變外觀）——高風險";
"ame317.perm.settings.read.name" = "讀取設定";
"ame317.perm.settings.read.desc" = "讀取啟動器偏好設定（唯讀）";
"ame317.perm.settings.write.name" = "修改設定";
"ame317.perm.settings.write.desc" = "允許外掛更改啟動器偏好——高風險";
"ame317.perm.renderer.read.name" = "讀取渲染器設定";
"ame317.perm.renderer.read.desc" = "讀取目前渲染器與後端選擇";
"ame317.perm.renderer.write.name" = "切換渲染器";
"ame317.perm.renderer.write.desc" = "允許外掛更改圖形渲染器/後端——錯誤取值將導致黑屏，高風險";
"ame317.perm.profile.read.name" = "讀取設定檔";
"ame317.perm.profile.read.desc" = "讀取遊戲實例/設定檔清單";
"ame317.perm.storage.name" = "私有儲存";
"ame317.perm.storage.desc" = "外掛專屬的鍵值儲存（與其他外掛隔離）";
"ame317.perm.net.name" = "網路存取";
"ame317.perm.net.desc" = "允許外掛向任意位址傳送網路請求——高風險";
'''

TABLES = {'en': EN, 'zh-Hans': ZH, 'zh-CN': ZH, 'zh-Hant': ZH_HANT}

def keys_of(block):
    return set(re.findall(r'"(ame317\.[a-zA-Z0-9_.]+)"', block))

def existing_keys(text):
    return set(re.findall(r'"([a-zA-Z0-9_.]+)"\s*=', text))

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
