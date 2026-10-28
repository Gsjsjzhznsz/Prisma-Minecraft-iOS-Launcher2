#!/usr/bin/env python3
# ame327_selfcheck.py -- Task327 门禁（四线断言制）
#   ① versions 真实文件物化（符号链接路线退役）
#   ② SDL 小窗自适应（坐标归一 + 沉降重宣告）
#   ③ 插件效果可见（设置页贡献行动态组 + 管理页指南卡）
#   ④⑤ 权限扩大 + 新桥接 API + AI 写插件
#   ⑥ i18n 四实表新键
import io, os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
fails = []
passed = 0

def rd(p):
    with io.open(os.path.join(REPO, p), "r", encoding="utf-8") as f:
        return f.read()

def check(name, cond, detail=""):
    global passed
    if cond:
        passed += 1
        print(f"  ✓ {name}")
    else:
        fails.append(name)
        print(f"  ✗ {name} {detail}")

print("== ① versions 真实文件物化 ==")
ms = rd("Natives/ModService.m")
check("ame326 链接路线退役（符号链接方法零残留）",
      ms.count("ame326_ensureInstanceVersionsLink") == 0)
check("ame327 物化方法在位", "ame327_materializeInstanceVersions" in ms)
check("物化 = 硬链接优先（linkItemAtPath）", "linkItemAtPath" in ms)
check("物化 = 拷贝兜底（copyItemAtPath）", "copyItemAtPath" in ms)
check("旧符号链接摘除守卫（NSFileTypeSymbolicLink）", "NSFileTypeSymbolicLink" in ms)
check("调用点接入 ame325 实例轴 pass",
      "ame327_materializeInstanceVersions:ame325_gdComp" in ms)
check("自指守卫在位（resolvedSharedRoot）", "resolvedSharedRoot" in ms)
check("版本实例判据（<vid>.json marker）", '%@.json' in ms and "fileExistsAtPath:ame327_srcJson" in ms)

print("== ② SDL 小窗自适应 ==")
sv = rd("Natives/SurfaceViewController.m")
check("归一助手在位", sv.count("ame327_contentPointFromRoot") >= 6)
check("悬停路径归一（surfaceOnHover）",
      "point = [self ame327_contentPointFromRoot:point];" in sv)
check("grab delta 同参考系（previousLocation:surfaceView）",
      "previousLocationInView:self.surfaceView" in sv)
check("grab delta 旧混系零残留",
      "previousLocationInView:self.rootView" not in sv)
check("热栏三处归一（dblclick/longpress/touchesBegan）",
      sv.count("ame327_contentPointFromRoot:location") >= 2 and
      "ame327_contentPointFromRoot:locationInView" in sv)
check("触控笔虚拟鼠标归一（indirect）",
      "sendTouchPoint:[self ame327_contentPointFromRoot:point]" in sv)
check("沉降排程挂 rescale 尾", "ame327_scheduleSettledReannounce:ame283_target" in sv)
check("沉降重宣告实现", "ame327_settledReannounceForSize" in sv)
check("重宣告含强制宣告（nativeSendScreenSizeForced）",
      "CallbackBridge_nativeSendScreenSizeForced(windowWidth, windowHeight);" in sv)
check("快路径锚点复位（Task279 家法）",
      "g_ame267_lastRescaledSize = CGSizeMake(0.0, 0.0);" in sv)
check("定时器 dealloc 清理", sv.count("[ame327_settleTimer invalidate]") == 2)  # schedule + dealloc
check("信念链重算五件套（phys/surface/window/ratio/fsr）-- ★Task328 重锚 ame328 核心",
      all(k in sv.split("- (BOOL)ame328_recomputeBeliefChainFromTouchViewWithRes:")[1]
          for k in ["physicalWidth = ame328_newPhysW", "ame_surfaceWidth = ame328_newSurfW",
                    "windowWidth = ame328_newWinW", "ame_windowToPhysRatio",
                    "ame166_metal_fsr_update_size(windowWidth, windowHeight);"]))
check("沉降重宣告委托 ame328 核心（单一事实源）",
      "ame328_recomputeBeliefChainFromTouchViewWithRes:ame327_res" in
      sv.split("- (void)ame327_settledReannounceForSize:")[1]
         .split("- (BOOL)ame328_recomputeBeliefChainFromTouchViewWithRes:")[0])

print("== ③ 插件效果可见 ==")
sp = rd("Natives/ZL2SettingPages.m")
check("贡献行动态组构建", "ame327_rebuildPluginRowsGroup" in sp)
check("消费 allContributedRows", "[AmePluginRuntime allContributedRows]" in sp)
check("点按转 invokeRowTap", "[AmePluginRuntime invokeRowTap:rowId]" in sp)
check("viewWillAppear 重建", "[self ame327_rebuildPluginRowsGroup];" in sp.split("viewWillAppear")[1] if "viewWillAppear" in sp else False)
pl = rd("Natives/ZL2PluginListViewController.m")
check("管理页指南区（section 4）", "return 4;" in pl)
check("指南文案键接入", "ame327.plugin.guide.body" in pl)

print("== ④⑤ 权限扩大 + 新桥接 API + AI 写插件 ==")
pm = rd("Natives/AmePluginPermissions.m")
for pid in ["ui.nav", "profile.write", "files.game"]:
    check(f"权限注册表 +{pid}", f'initWithId:@"{pid}"' in pm)
bh = rd("Natives/AmePluginBridge.h")
check("桥接头声明新 API", all(k in bh for k in
      ["openPage", "createProfile", "deleteProfile",
       "listGameFiles", "readGameFile", "writeGameFile", "removeGameFile"]))
bm = rd("Natives/AmePluginBridge.m")
check("导航走 ZL2ShellNavigate 契约", "ZL2ShellNavigateNotification" in bm)
check("导航页映射 0-6", all(k in bm for k in ['@"home": @0', '@"ai": @6']))
check("档案写守卫（Default/选中不删）",
      '@"(Default)"' in bm and "selectedProfileName" in bm)
check("文件沙盒守卫（.. 拒绝）", 'stringIsEqualToString:@".."' in bm.replace('[ame327_seg isEqualToString:@".."]', 'stringIsEqualToString:@".."'))
check("文件限额（读2MB/写4MB）",
      "2 * 1024 * 1024" in bm and "4 * 1024 * 1024" in bm)
check("symlink 逃逸守卫", "stringByResolvingSymlinksInPath" in bm)
rt = rd("Natives/AmePluginRuntime.m")
check("facade 新 API（openPage/writeGameFileContentAppend 等）",
      all(k in rt for k in ["ame.openPage", "ame.createProfile", "ame.deleteProfile",
                            "ame.listFiles", "ame.readFile", "ame.writeFile",
                            "ame.removeFile", "writeGameFileContentAppend"]))
wtool_h = os.path.exists(os.path.join(REPO, "Natives/AI/AiPluginWriterTool.h"))
wtool_m = rd("Natives/AI/AiPluginWriterTool.m")
check("AiPluginWriterTool.h/.m 在位", wtool_h and "create_plugin" in wtool_m)
check("工具 = ControlledWrite", "AiToolPermissionControlledWrite" in wtool_m)
check("工具含 ame API 文档（LLM 可照写）",
      "addLauncherRow" in wtool_m and "game.starting" in wtool_m)
check("终审校验（manifestForPlugin）+ 半成品回滚",
      "manifestForPlugin" in wtool_m and "removeItemAtPath:dir" in wtool_m)
bt = rd("Natives/AI/AiToolBootstrapper.m")
check("引导注册 create_plugin", "AiPluginWriterTool" in bt)
cm = rd("Natives/CMakeLists.txt")
check("CMakeLists 登记", "AI/AiPluginWriterTool.m" in cm)

print("== ⑥ i18n 四实表 ==")
for lang in ["en", "zh-Hans", "zh-CN", "zh-Hant"]:
    t = rd(f"Natives/resources/{lang}.lproj/Localizable.strings")
    check(f"{lang} 表 9 新键齐备",
          all(k in t for k in ["ame317.perm.ui.nav.name", "ame317.perm.profile.write.name",
                               "ame317.perm.files.game.name", "ame327.plugin.rows.title",
                               "ame327.plugin.guide.title", "ame327.plugin.guide.body"]))

print("== ⑦ Task328 四联 ==")
# ⑦A versions 空目录：诱饵骨架清扫
check("诱饵骨架清扫方法在位", "ame328_pruneDecoyVersionSkeletons" in ms)
check("清扫接入全量骨架 pass 尾", "[ModService ame328_pruneDecoyVersionSkeletons];" in ms)
check("清扫守卫：六目录全空才构成诱饵形态",
      "ame328_empty.count != ame328_six.count" in ms)
check("清扫守卫：版本轴 claim + 实例轴接管对冲",
      "ame328_claimed && !ame328_instanceBound" in ms)
# ⑦B SDL 小窗 + 分辨率即时应用
check("小窗首入即时武装（布局路径跳过去抖）",
      "ame261_runAdaptiveGeometryResync];" in sv and
      "Task328：自由窗即时武装" in sv)
check("分辨率会话内即时应用方法在位",
      "ame328_applyResolutionInSession" in sv)
check("应用方法双分支（自由窗核心 / 全屏全链）",
      "ame267_isFullscreenWindow] || g_ame267_freeformScaled" in sv and
      "[self updateSavedResolution];" in sv.split("- (BOOL)ame328_applyResolutionInSession:")[1].split("@end")[0])
nav = rd("Natives/SurfaceViewController+Navigation.m")
# ★Task340：断言同步 Task339 r1 热修新调用形式（NSInteger 点语法退役）
check("游戏内菜单接入即时应用 + applied 键",
      "ame328_applyResolutionInSession:(float)value / 100.0" in nav and
      'game.menu.resolution.applied' in nav)
# ⑦C 插件效果直达
check("设置页插件组上移至外观组后（新位点 + 组3 尾零残留）",
      "[self ame_addGroup:group1];\n    // ★ Task328：插件贡献行动态组上移" in sp and
      "[self ame327_rebuildPluginRowsGroup];" not in
      sp.split("[group3 ame_addRows:@[backgroundRow", 1)[1]
        .split("- (void)ame327_rebuildPluginRowsGroup", 1)[0])
check("插件组标题带计数（ASCII 括号拼接）",
      '%@ (%ld)"' in sp and "ame327.plugin.rows.title" in sp)
hm = rd("Natives/ZL2HomeViewController.m")
check("主页插件 chip 在位", "pluginChipButton" in hm and "ame328_pluginChipTapped" in hm)
check("chip = 两段同步通知（壳切页 + 枢纽定点）",
      'postNotificationName:@"ZL2ShellNavigate"' in hm and
      'postNotificationName:@"ZL2SettingsSelectPage"' in hm)
sh = rd("Natives/ZL2SettingsViewController.m")
check("设置枢纽监听定点通知", "ame328_selectSubPage" in sh and
      'name:@"ZL2SettingsSelectPage"' in sh)
check("chip 计数 = allContributedRows", "[[AmePluginRuntime allContributedRows] count]" in hm)
# ⑦D AI 提示词 v3
ai = rd("Natives/AI/AiSettings.m")
check("默认提示词含插件开发章", "【七、插件系统（AmePlugin）" in ai)
check("v2 基线留档（迁移比对）", "ame328_v2DefaultSystemPrompt" in ai)
check("迁移写版本号 3", "setInteger:3 forKey:kSystemPromptVersionKey" in ai)
check("create_plugin 与提示词 API 同源（addLauncherRow 主通道）",
      "addLauncherRow" in ai)

print(f"\n== ame327 selfcheck: {passed} passed / {len(fails)} failed ==")
if fails:
    print("FAILED:", fails)
    sys.exit(1)
print("ALL GREEN")
