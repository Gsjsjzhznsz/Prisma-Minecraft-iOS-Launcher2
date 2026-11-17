#!/usr/bin/env python3
# ame344_selfcheck.py -- Task344 三线门禁（zip 导入插件防回写 / 插件旧代清单自愈 / 旧设置全量迁移新UI）
# A 线A：DataTransfer 导入/兄弟迁移跳过插件根 + main.m 旧位残留收编
# B 线B：AmePluginRuntime 开机自愈（权限谱系映射重写 / 官方全量授 / 不可修隔离）
# C 线C：新UI设置左轨 8→10（AI/调试新屏）+ 六落位面旧设置键迁移
# D 结构护栏 + --selftest 反向验证（内存注入病灶变体必翻红，零仓内触碰）
# 断言口径：字符串字面量类模式走原始文本；括号平衡走 strip_code 剥离文本
import os, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

def strip_code(text):
    """真代码剥离（块注释→字符串→行注释单遍扫描；ame337/343 判例剥器）"""
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

def plugins_skip_probes(raw):
    """插件根跳过四探针（导入/迁移循环共用判据）"""
    return ('[rel isEqualToString:@"plugins"]' in raw
            and '[rel hasPrefix:@"plugins/"]' in raw
            and '[rel isEqualToString:@"Prisma2/plugins"]' in raw
            and '[rel hasPrefix:@"Prisma2/plugins/"]' in raw
            and "skipDescendants" in raw
            and "ame344_skippedPluginFiles++" in raw)

# ══ A 线A 导入/迁移防回写 ═══════════════════════════════════════
dt = read("Natives/DataTransferService.m")

print("== A 线A 导入/兄弟迁移插件根排除 ==")
# A1-A2 导入合并循环：两处插件根跳过（切片定位 ame217 导入函数体）
imp_i = dt.index("- (void)ame217_performImportFromZipAtURL:(NSURL *)zipURL {")
import_region = dt[imp_i:dt.index("#pragma mark - Alert helpers", imp_i)]
check("A1 导入循环跳过 plugins/ 与 Prisma2/plugins/", plugins_skip_probes(import_region))
check("A2 导入循环 skipDescendants+计数", "skipDescendants" in import_region
      and "ame344_skippedPluginFiles++" in import_region)
# A3 导入摘要日志带 Task344 跳过注记
check("A3 导入日志 Task344 插件跳过注记",
      "Task344: %ld plugin file(s) skipped" in dt)
# A4 兄弟迁移循环同口径
mig_i = dt.index("ame321_migrateFromSiblingHome")
mig_region = dt[mig_i:]
check("A4 兄弟迁移循环跳过两处插件根", plugins_skip_probes(mig_region))
check("A5 迁移完成日志带 pluginSkipped 计数", "pluginSkipped=%ld" in dt)
# A6 main.m 旧位残留收编（增量 adopt + 现役版优先 + 根清除）
mm = read("Natives/main.m")
check("A6 main.m 旧位 plugins 增量收编（adopt+keptCurrent）",
      "ame344_adopted" in mm and "ame344_keptCurrent" in mm
      and "stray legacy plugins/ root adopted" in mm)
check("A7 收编纪律：现役根存在时旧位不整体 move（else 分支）",
      "keeps legacy layout this launch" in mm
      and mm.index("ame344_adopted") > mm.index("plugins migration failed"))

# ══ B 线B 插件旧代清单自愈 ═══════════════════════════════════════
rt = read("Natives/AmePluginRuntime.m")

print("== B 线B 插件开机自愈 ==")
boot_i = rt.index("+ (void)bootIfNeeded")
loop_i = rt.index("for (NSString *pid in [AmePluginManager installedPluginIds])", boot_i)
check("B1 ame344_healLegacyPluginDirs 存在且 bootAll 先于装载循环调用",
      "[self ame344_healLegacyPluginDirs]" in rt[boot_i:loop_i]
      and "ame344_healLegacyPluginDirs" in rt[:boot_i])
check("B2 谱系映射三件（notify→ui.dialog+ui.rows / theme.write→ui.theme / files.plugin→storage）",
      '@"notify"' in rt and '@"theme.write"' in rt and '@"files.plugin"' in rt
      and '@"ui.dialog", @"ui.rows"' in rt and '@"ui.theme"' in rt and '@"storage"' in rt)
check("B3 预校验先行（validateManifestDictionary fixed 后才落盘）",
      "validateManifestDictionary:fixed" in rt
      and rt.index("validateManifestDictionary:fixed") < rt.index("writeToFile:mfPath atomically"))
check("B4 官方件镜像安装期语义（.repo-official.json → replaceGrants 全量授 + 启用）",
      ".repo-official.json" in rt and "replaceGrants:" in rt
      and "setPluginEnabled:YES pluginId:pid" in rt)
check("B5 第三方仅迁移既有授权键（不代授不代启用）",
      "grantsForPlugin:pid" in rt and "flushState" in rt)
check("B6 不可自愈隐藏隔离（.ame344-corrupt- 命名 + moveItem）",
      ".ame344-corrupt-%@-%@" in rt and "moveItemAtPath:dir toPath:dst" in rt)
check("B7 损坏跳过日志带 errCode 原因", "errCode=%ld" in rt)

# ══ C 线C 旧设置全量迁移 ═══════════════════════════════════════
sv = read("Natives/ZL2SettingsViewController.m")
pages = read("Natives/ZL2SettingPages.m")
pages_h = read("Natives/ZL2SettingPages.h")

print("== C 线C 设置枢纽（Task432 重锚：左轨 10→8 组收敛）==")
# ★第 12 期整改批次二①重锚（Task432 八组口径）：Task432 把左轨 10 项收敛为
# 8 项——AI/调试两轨项从左轨摘除（sparkles/ladybug 图标退场），可达性改由
# case 4 启动器页尾子类 ZL2LauncherSettingsTailPage 尾部入口组 push 接住
# （ame432_appendTailGroup + ame432_tailRowTapped，真实现零退役）；divider
# 1:1 对齐 ZL2 SettingsScreen.kt settingItems（Java 管理/关于 division）。
check("C1 左轨 8 项（Task432 重锚：Java管理/控制管理/关于轨项齐备；AI/调试轨项摘除但页尾入口接住真实现）",
      '@"ame369.settab.java_manager"' in sv and '@"wrench.and.screwdriver"' in sv
      and '@"ame369.settab.control_manager"' in sv and '@"square.on.square"' in sv
      and '@"ame369.settab.about"' in sv and '@"info.circle"' in sv
      and 'sparkles' not in sv and 'ladybug' not in sv
      and 'ZL2LauncherSettingsTailPage' in sv and 'ame432_appendTailGroup' in sv
      and '[[ZL2AISettingsPage alloc] init]' in sv and '[[ZL2DebugSettingsPage alloc] init]' in sv)
check("C2 组分隔线两处（Task432 八组口径：i==4||i==6，旧三处 i==8 位退场）",
      "i == 4 || i == 6" in sv and "i == 4 || i == 6 || i == 8" not in sv)
check("C3 页面映射 case4=启动器尾页 case5=Java管理 case6=控制管理 case7=About（Task432 八组重锚；AI/Debug 由页尾 push 接住）",
      "page = [[ZL2LauncherSettingsTailPage alloc] init]" in sv
      and "case 5: page = [[ZL2JavaManagerSettingsPage alloc] init]" in sv
      and "case 6: page = [[ZL2ControlManagerSettingsPage alloc] init]" in sv
      and "case 7: page = [[ZL2AboutSettingsPage alloc] init]" in sv)
check("C4 越界闸 >7（Task432 八组口径：showPageAtIndex + ame328_selectSubPage）",
      "ame328_index > 7" in sv and "index > 7" in sv
      and "index > 9" not in sv and "ame328_index > 9" not in sv)
check("C5 头文件声明新屏", "ZL2AISettingsPage" in pages_h and "ZL2DebugSettingsPage" in pages_h)
check("C6 新屏实现落位", "@implementation ZL2AISettingsPage" in pages
      and "@implementation ZL2DebugSettingsPage" in pages)

print("== C 线C 迁移键覆盖面（六落位面代表键） ==")
MIGRATED_KEYS = [
    # 渲染器屏（video 渲染 + mobileglues 全族）
    "video.fsr1_setting", "video.fsr_rcas_sharpness", "video.disable_game_vsync",
    "video.performance_hud", "mobileglues.renderer_backend", "mobileglues.enable_no_error",
    "mobileglues.enable_ext_timer_query", "mobileglues.enable_ext_compute_shader",
    "mobileglues.enable_ext_direct_state_access", "mobileglues.max_glsl_cache_size",
    "mobileglues.multidraw_mode", "mobileglues.angle_depth_clear_fix_mode",
    "mobileglues.custom_gl_version",
    # 游戏屏（音频/兼容）
    "video.silence_other_audio", "video.silence_with_switch", "video.allow_microphone",
    "general.legacy_compatibility", "general.cosmetica",
    # 控制屏（键鼠/手势/陀螺仪/实例工具）
    "control.slideable_hotbar", "control.gesture_mouse", "control.gesture_hotbar",
    "control.fluid_button_slide", "control.virtmouse_enable", "control.button_scale",
    "control.mouse_scale", "control.mouse_speed", "control.press_duration",
    "control.two_finger_keyboard", "control.auto_keyboard_sdl", "control.disable_haptics",
    "control.gyroscope_enable", "control.gyroscope_invert_x_axis",
    "control.gyroscope_sensitivity", "control.hardware_hide", "control.recording_hide",
    "control.auto_control_update_check",
    # action-only 行（无偏好键，探测其 i18n 标题键）
    "preference.title.custom_mouse_pointer", "preference.title.reset_mouse_pointer",
    "preference.title.mc_toggle_sprint", "preference.title.keybind_sync",
    # 启动器屏（外观进阶/杂项/数据/下载源）——★Ame361 重锚：伪玻璃透明度/
    # 界面缩放/文字缩放三行读写改走 LGC 中枢（行 UI 仍在位，general.* 旧键名
    # 退役），断言改锚 LGC 读写入口同源函数
    "general.interface_style", "LGCSetPseudoGlassTransparency", "LGCSetUIScaleMultiplier",
    "LGCSetTextScaleMultiplier", "general.hidden_sidebar", "general.accent_color",
    "general.text_color", "general.card_color", "general.check_sha",
    "general.multi_threaded", "general.debug_logging",
    "general.announcement_preview_level", "download.mod_mirror",
    # action-only 行（CF key / 应用图标 / 数据管理六件）
    "preference.title.curseforge_api_key", "preference.title.appicon",
    "preference.title.data_export", "preference.title.data_import",
    "preference.title.data_sibling_import", "preference.title.erase_demo_data",
    "preference.title.reset_warnings", "preference.title.reset_settings",
    # AI 屏——★Ame361 重锚：markdown 开关直连 AiSettings（ai.markdown_enabled
    # 旧键名退役，消费方 AiSettings.markdownEnabled 同源）
    "ai.safety_mode", "setMarkdownEnabled",
    # 调试屏
    "debug.jit_enabler", "debug.jit26_script_disable", "debug.mirror_codecache_disable",
    "debug.debug_universal_script_jit", "debug.debug_always_attached_jit",
    "debug.debug_skip_wait_jit", "debug.debug_hide_home_indicator",
    "debug.debug_ipad_ui", "debug.debug_auto_correction",
]
missing_keys = [k for k in MIGRATED_KEYS if k not in pages]
check("C7 迁移键全量在位（66 代表键；Ame361 三行换族键重锚 LGC 入口，行 UI 仍在位）", not missing_keys,
      "missing: " + ", ".join(missing_keys[:8]))

print("== C 线C 复杂 handler 移植完整性 ==")
check("C8 ame229 键位同步链四件套平移",
      all(m in pages for m in [
          "ame229_allInstanceOptionsPaths", "ame229_linesOfOptions",
          "ame229_keybindsOfOptions", "ame229_writeToggleSprint",
          "ame229_syncKeybindsAcrossInstances"]))
check("C9 ame261 兄弟迁移入口平移（Smart/Overwrite 双模）",
      "ame261_siblingImportTapped" in pages
      and "Ame321SiblingMigrationModeSmart" in pages
      and "Ame321SiblingMigrationModeOverwrite" in pages)
check("C10 颜色选择器链（openColorPicker + didFinish + hex 往返）",
      "ame344_openColorPickerForKey" in pages
      and "colorPickerViewControllerDidFinish" in pages
      and "ame_pages_hexFromColor" in pages)
check("C11 应用图标链（CustomIconManager 三件）",
      "hasCustomIcon" in pages and "removeCustomIcon" in pages
      and "setCustomIconWithCompletion" in pages)
check("C12 基类 ame_presentVC 上移（仅基类一份）+ 鼠标指针图片选择委托",
      pages.count("- (void)ame_presentVC:(UIViewController *)vc {") == 1
      and "imagePickerController:(UIImagePickerController *)picker" in pages
      and "ame344_pickingMousePointer" in pages)
check("C13 游戏会话闸（ame_pages_whenNotInGame → currentVC/SurfaceViewController）",
      "ame_pages_whenNotInGame" in pages and "SurfaceViewController" in pages)

# ══ D 结构护栏 ═══════════════════════════════════════════════
print("== D 结构护栏 ==")
for f in ["Natives/ZL2SettingPages.m", "Natives/ZL2SettingsViewController.m",
          "Natives/DataTransferService.m", "Natives/AmePluginRuntime.m", "Natives/main.m"]:
    code = strip_code(read(f))
    check(f"D {os.path.basename(f)} 括号平衡", code.count("{") == code.count("}")
          and code.count("(") == code.count(")"),
          f"{{}}={code.count('{')}/{code.count('}')} ()={code.count('(')}/{code.count(')')}")
# ★ Task343-ci 第十二例防复发：smoke 链接面（ZL2PagesStub）桩齐挂载
stub = read("Natives/Preview/ZL2PagesStub.m")
check("D smoke 桩面新页齐挂载（ZL2PagesStub 含 AI/Debug 两桩）",
      "@interface ZL2AISettingsPage : ZL2SettingPageStubBase" in stub
      and "@interface ZL2DebugSettingsPage : ZL2SettingPageStubBase" in stub)
# AI/调试页声明在 .h、实现在 .m、消费在枢纽（三方对拍）
check("D 新屏三方对拍（h声明/m实现/枢纽消费）",
      pages_h.count("ZL2AISettingsPage") >= 1 and pages_h.count("ZL2DebugSettingsPage") >= 1
      and sv.count("ZL2AISettingsPage") >= 1 and sv.count("ZL2DebugSettingsPage") >= 1)

# ══ --selftest 反向验证 ═══════════════════════════════════════
if "--selftest" in sys.argv:
    print("== --selftest 反向探针（病灶注入必翻红）==")
    red = 0
    # S-A1 导入跳过摘除 → A1 必翻红
    dt_bad = dt.replace('[rel isEqualToString:@"plugins"]', 'NO')
    if not plugins_skip_probes(dt[dt.index("ame217_performImportFromZipAtURL"):
                                  dt.index("ame217_showToastOrAlert")].replace(
                                      '[rel isEqualToString:@"plugins"]', 'NO')):
        print("  RED  S-A1 导入插件根跳过摘除被捕获"); red += 1
    else:
        print("  GREEN(BAD) S-A1 未捕获")
    # S-B1 谱系映射摘除 → B2 必翻红
    rt_bad = rt.replace('@[NSString stringWithFormat', '@[NSString stringWithFormat')  # 保形
    rt_bad = rt.replace('@"theme.write"', '@"theme.writeX"')
    if not ('@"theme.write"' in rt_bad):
        print("  RED  S-B1 谱系映射摘除被捕获"); red += 1
    else:
        print("  GREEN(BAD) S-B1 未捕获")
    # S-C1 左轨轨项摘除 → C1 必翻红（Task432 重锚：探针换锚 Java 管理轨项图标）
    sv_bad = sv.replace('@"wrench.and.screwdriver"', '@"wrench.and.screwdriverX"')
    if not ('@"wrench.and.screwdriver"' in sv_bad):
        print("  RED  S-C1 轨项摘除被捕获"); red += 1
    else:
        print("  GREEN(BAD) S-C1 未捕获")
    # S-D1 括号失衡 → D 组必翻红
    bad = strip_code(pages) + "{"
    if bad.count("{") != bad.count("}"):
        print("  RED  S-D1 括号失衡被捕获"); red += 1
    else:
        print("  GREEN(BAD) S-D1 未捕获")
    print(f"--selftest: {red}/4 翻红" + ("（OK）" if red == 4 else "（存在未捕获病灶，门禁失效！）"))
    sys.exit(0 if red == 4 else 1)

print(f"ame344_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("FAILURES:", ", ".join(fails))
sys.exit(1 if fails else 0)
