#!/usr/bin/env python3
# ame366_selfcheck.py -- Task 366 门禁（插件 API 全量扩容：桥面 40→118 方法 / 权限 20→33 组 / 事件 7→11 种 / 文档 v7）
# 用户拍板："可以改的东西还是太多了，少说 API 也应该要有几百个。"
# A 桥面：JSExport 118 方法计数 + 新家族代表实现与执法点
# B 权限：33 组注册 + 13 新组 danger 位 + 四语言 i18n 66 键
# C 提示词 v7：33 项行 / v6 逐字归档 / 迁移链 v6→v7 / v5 归档不受扰
# D 文档：v7 头 + 118/33/106 计数 + 18 新家族锚 + 键目录抽查 + writer 同步
# E 反向探针（泛化版）：文档 ame.* 顶层名与全部命名空间成员 ⊆ 门面
# F 接线实锚：事件四路 / lastExit / 主题读取器 / 键枚举链 / FS 守卫
# S 病灶反向：v7 不含 v6 残留 / JSExport 协议齐全 / raw 名成对存在
import io, re, sys

REPO = "/home/z/my-project/repo-prisma2"

def read(p):
    with io.open(REPO + "/" + p, encoding="utf-8", newline="") as f:
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

bh = read("Natives/AmePluginBridge.h")
bm = read("Natives/AmePluginBridge.m")
pm = read("Natives/AmePluginPermissions.m")
rt = read("Natives/AmePluginRuntime.m")
rth = read("Natives/AmePluginRuntime.h")
aiset = read("Natives/AI/AiSettings.m")
ptool = read("Natives/AI/AiPluginWriterTool.m")
dtool = read("Natives/AI/AiPluginDocsTool.m")
dhead = read("Natives/AI/AiPluginDocsTool.h")
plh = read("Natives/PLPreferences.h")
plm = read("Natives/PLPreferences.m")
lph = read("Natives/LauncherPreferences.h")
lpm = read("Natives/LauncherPreferences.m")

# ══ A 桥面 ═══════════════════════════════════════════════════
proto = bh[bh.index("@protocol AmePluginBridgeJSExport"):bh.index("@interface AmePluginBridge : NSObject")]
n_methods = len(re.findall(r"^- \(", proto, re.M))
check('A1 JSExport 协议方法总数 118（35 既有 + 83 扩容）', n_methods == 118, f"got {n_methods}")

new_impls = [
    ("getAppInfo", "- (nullable NSDictionary *)getAppInfo {"),
    ("viewsBatch", "- (BOOL)viewsBatch:(NSArray *)ops {"),
    ("viewsApplyStyle", "- (BOOL)viewsApplyStyle:(double)handle props:(NSDictionary *)props {"),
    ("dialogPrompt", "- (void)dialogPrompt:(NSDictionary *)spec callback:(JSValue *)cb {"),
    ("clipboardGetText", "- (nullable NSString *)clipboardGetText {"),
    ("listPrefKeys", "- (nullable NSArray *)listPrefKeys:(NSString *)prefix {"),
    ("renameProfile", "- (BOOL)renameProfile:(NSString *)oldName to:(NSString *)newName {"),
    ("getGameState", "- (nullable NSDictionary *)getGameState {"),
    ("setJITScheme", "- (BOOL)setJITScheme:(NSString *)scheme {"),
    ("searchLog", "- (nullable NSArray *)searchLog:(NSString *)which pattern:(NSString *)pattern limit:(double)limit {"),
    ("listModsWithProfile", "- (nullable NSArray *)listModsWithProfile:(NSString *)profileName {"),
    ("listWorldsForProfile", "- (nullable NSArray *)listWorldsForProfile:(NSString *)profileName {"),
    ("getAccountList", "- (nullable NSArray *)getAccountList {"),
    ("aiAsk", "- (void)aiAsk:(NSString *)prompt callback:(JSValue *)cb {"),
    ("listControlLayouts", "- (nullable NSArray *)listControlLayouts {"),
    ("fsMove", "- (BOOL)fsMove:(NSString *)fromPath to:(NSString *)toPath {"),
    ("downloadWithURL", "- (void)downloadWithURL:(NSString *)urlString to:(NSString *)relPath callback:(JSValue *)cb {"),
    ("analyzeLatestHsErr", "- (nullable NSDictionary *)analyzeLatestHsErr {"),
]
a2_ok = all(decl in bm for _, decl in new_impls)
a2_h = all(re.search(re.escape(name) + r'[;:(]', proto) for name, _ in new_impls)
check('A2 18 个新家族代表：协议声明 + 实现齐备', a2_ok and a2_h)

perms_new = ["game.read", "mods.read", "mods.write", "worlds.read", "worlds.write",
             "accounts.read", "downloads.read", "controls.read", "controls.write",
             "fs.launcher", "ai.call", "notify", "clipboard.read"]
a3_ok = all(('ame317_requirePerm:@"%s"' % p) in bm for p in perms_new)
check('A3 13 个新权限执法点全在位（桥边界唯一执法点）', a3_ok)

facade = rt[rt.index('static NSString *ame317_facadeSource(void)'):]
facade = facade[:facade.index('#pragma mark - 装载 / 卸载')]
a4_pairs = ["raw.getAppInfo()", "raw.viewsBatch(", "raw.dialogPromptCallback(",
            "raw.dialogSheetCallback(", "raw.notifyWithTitleBody(", "raw.clipboardGetText()",
            "raw.listPrefKeys(", "raw.renameProfileTo(", "raw.getProfileKeyProfile(",
            "raw.getGameState()", "raw.setJITScheme(", "raw.searchLogPatternLimit(",
            "raw.listModsWithProfile(", "raw.listWorldsForProfile(", "raw.getAccountList()",
            "raw.aiAskCallback(", "raw.listControlLayouts()", "raw.fsMoveTo(",
            "raw.downloadWithURLToCallback(", "raw.analyzeLatestHsErr()",
            "raw.getThemeTokens()", "raw.setMemoryAllocation("]
a4_ok = all(x in facade for x in a4_pairs)
a4_ns = all(("ame.%s={" % ns) in facade for ns in
            ["app", "notify", "clipboard", "theme", "settings", "profiles",
             "game", "logs", "mods", "shaders", "worlds", "accounts", "downloads",
             "ai", "controls", "fs", "crash", "net"])
# dialog 双形态：顶层函数契约保留（四内置件消费）+ 三成员函数挂载（对象字面量覆盖 = 回归，冒烟实锤）
a4_dialog = ("ame.dialog=function(spec,cb)" in facade
             and "ame.dialog.prompt=function" in facade
             and "ame.dialog.sheet=function" in facade
             and "ame.dialog.dismissAll=function" in facade)
check('A4 门面接线（22 raw 名 + 18 命名空间对象 + dialog 双形态）', a4_ok and a4_ns and a4_dialog)

check('A5 扩容导入面（mach/UserNotifications/ModService/ShaderService/CrashAnalyzer/AI 五头/Runtime）',
      '#import <mach/mach.h>' in bm and '#import <UserNotifications/UserNotifications.h>' in bm
      and '#import "ModService.h"' in bm and '#import "ShaderService.h"' in bm
      and '#import "CrashAnalyzer.h"' in bm and '#import "AI/AiProviderStore.h"' in bm
      and '#import "AmePluginRuntime.h"' in bm)

# ══ B 权限注册表 + i18n ═══════════════════════════════════════
check('B1 注册表 33 实体 + ame.super 居首',
      pm.count('initWithId:@"') == 33
      and pm.index('initWithId:@"ame.super"') < pm.index('initWithId:@"events"'))
check('B2 13 新组 danger 位正确（8 安全 + 5 高危：mods.write/worlds.write/controls.write/fs.launcher/ai.call/clipboard.read）',
      'initWithId:@"game.read"     danger:NO' in pm
      and 'initWithId:@"mods.write"    danger:YES' in pm
      and 'initWithId:@"worlds.write"  danger:YES' in pm
      and 'initWithId:@"accounts.read" danger:NO' in pm
      and 'initWithId:@"controls.write" danger:YES' in pm
      and 'initWithId:@"fs.launcher"   danger:YES' in pm
      and 'initWithId:@"ai.call"       danger:YES' in pm
      and 'initWithId:@"notify"        danger:NO' in pm
      and 'initWithId:@"clipboard.read" danger:YES' in pm)
i18n_ok = True
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN"]:
    t = read(f"Natives/resources/{lang}.lproj/Localizable.strings")
    n = len(re.findall(r'^"ame317\.perm\.[^"]+"\s*=', t, re.M))
    if n != 66:
        i18n_ok = False
        check(f'B3 {lang} 权限键 66（33×name/desc）', False, f"got {n}")
check('B3 四语言权限键各 66（33×name/desc）', i18n_ok)

# ══ C 提示词 v7 + v6 归档 + 迁移链 ════════════════════════════
FRAG = re.compile(r'@?"((?:[^"\\]|\\.)*)"')
def produced(t):
    return "".join(m.group(1) for m in FRAG.finditer(t))

v7_start = aiset.index("+ (NSString *)defaultSystemPrompt {")
v7_zone = aiset[v7_start:aiset.index("+ (NSString *)ame366_v6DefaultSystemPrompt {")]
v6_arch_start = aiset.index("+ (NSString *)ame366_v6DefaultSystemPrompt {")
v6_zone = aiset[v6_arch_start:aiset.index("/// ★ Task365：v5 默认提示词全文（")]

check('C1 v7 现役含 33 项权限行 + 扩容代表（fs.launcher†/ai.call†/clipboard.read†）',
      "权限共 33 项" in produced(v7_zone)
      and "fs.launcher†" in produced(v7_zone) and "ai.call†" in produced(v7_zone)
      and "clipboard.read†" in produced(v7_zone) and "game.read" in produced(v7_zone))
check('C2 v6 归档在位且为逐字节原文（归档内仍含 "共 20 项" 不变式）',
      "+ (NSString *)ame366_v6DefaultSystemPrompt {" in aiset
      and "共 20 项" in produced(v6_zone) and "ame.views.find" not in produced(v6_zone))
check('C3 迁移链 v6→v7（归档匹配删档回落 + setInteger:7 + setInteger:6 缺席）',
      "[ame267_saved isEqualToString:[self ame366_v6DefaultSystemPrompt]]" in aiset
      and "Task366: v6 default system prompt auto-upgraded to v7" in aiset
      and "[ame267_d setInteger:7 forKey:kSystemPromptVersionKey];" in aiset
      and "[ame267_d setInteger:6 forKey:kSystemPromptVersionKey];" not in aiset)
check('C4 v5 归档不受扰（ame365_v5DefaultSystemPrompt 在位）',
      "+ (NSString *)ame365_v5DefaultSystemPrompt {" in aiset
      and "共 15 项" in aiset)

# ══ D 文档（get_plugin_docs = 插件提示词正文）═════════════════
docs_text = produced(dtool)
check('D1 文档 v7 头 + 三计数锚（118 方法 / 33 权限 / 106 键×2=212）',
      "全量 API 参考 v7" in docs_text
      and "桥面方法 118" in docs_text and "共 33 项" in docs_text
      and "106 键 × get/set = 212" in docs_text)
d2_anchors = ["ame.app.info()", "ame.views.batch", "ame.views.applyStyle", "ame.dialog.prompt",
              "ame.dialog.sheet", "ame.notify.haptic", "ame.clipboard.get", "ame.theme.getTokens",
              "ame.settings.keys", "ame.profiles.setKey", "ame.game.lastExit", "ame.jit.setScheme",
              "ame.jit.schemes", "ame.logs.search", "ame.mods.list", "ame.shaders.list",
              "ame.worlds.list", "ame.accounts.list", "ame.ai.ask", "ame.controls.list",
              "ame.fs.move", "ame.net.download", "ame.crash.analyzeLatest"]
d2_missing = [a for a in d2_anchors if a not in docs_text]
check('D2 文档含 23 个新家族 API 锚', not d2_missing, f"missing={d2_missing}")
check('D3 文档含自修复姿势（game.crash→readLog→ai.ask 闭环）+ 拖拽写法 + 凭据脱敏铁律',
      "ame.on('game.crash'" in docs_text and "ame.ai.ask(" in docs_text
      and "ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});" in docs_text
      and "凭据字段永不进入 JS" in docs_text)
d4_keys = ["general.ram_allocation", "java.java_args", "video.renderer",
           "mobileglues.renderer_backend", "control.default_ctrl", "debug.jit_enabler"]
d4_missing = [k for k in d4_keys if k not in docs_text]
check('D4 文档键目录抽查（RAM/JVM 参数/渲染器/触控布局/JIT）', not d4_missing, f"missing={d4_missing}")
check('D5 writer 摘要同步（118 方法 + 33 项权限 + 新速览）',
      "118 个方法" in ptool and "33 项权限表" in ptool
      and "ame.views 14 方法" in ptool and "ame.ai.ask 自修复问答" in ptool)

# ══ E 反向探针（泛化版：全部命名空间）═════════════════════════
doc_top = set(re.findall(r'ame\.([a-zA-Z]+)\s*[\(.=]', docs_text))
facade_top = set(re.findall(r'ame\.([a-zA-Z]+)\s*=', facade))
facade_top |= set(re.findall(r'ame\.([a-zA-Z]+)\.', facade))
missing_top = sorted(doc_top - facade_top)
check('E1 文档 ame.* 顶层名 ⊆ 门面顶层名（含点链）', not missing_top, f"missing={missing_top}")

ALL_NS = ["views", "jit", "storage", "dialog", "notify", "clipboard", "theme", "settings",
          "profiles", "game", "logs", "mods", "shaders", "worlds", "accounts", "downloads",
          "ai", "controls", "fs", "crash", "app"]
doc_ns = {}
for m in re.finditer(r'ame\.([a-zA-Z]+)\.([a-zA-Z]+)', docs_text):
    doc_ns.setdefault(m.group(1), set()).add(m.group(2))
facade_ns = {}
for ns in ALL_NS:
    members = set()
    blk = re.search(r'ame\.' + ns + r'=\{(.*?)\};', facade, re.S)
    if blk:
        members |= set(re.findall(r'([a-zA-Z]+):function', blk.group(1)))
    members |= set(re.findall(r'ame\.' + ns + r'\.([a-zA-Z]+)\s*=', facade))
    facade_ns[ns] = members
ns_missing = {k: sorted(v - facade_ns.get(k, set())) for k, v in doc_ns.items()
              if v and not v.issubset(facade_ns.get(k, set())) and k in ALL_NS}
check('E2 文档全部 21 命名空间成员 ⊆ 门面成员', not ns_missing, f"missing={ns_missing}")

# ══ F 接线实锚 ═══════════════════════════════════════════════
check('F1 Runtime 事件四路（page.changed/account.changed/app.lowMemory/game.crash）',
      'ZL2ShellNavigateNotification' in rt and '"page.changed"' in rt
      and '"UpdateAccountInfo"' in rt and '"account.changed"' in rt
      and 'UIApplicationDidReceiveMemoryWarningNotification' in rt and '"app.lowMemory"' in rt
      and '"game.crash"' in rt)
check('F2 lastExit 记录 + 主题覆盖读取器（.h 声明 + .m 实现 + 桥消费）',
      "+ (nullable NSDictionary *)ame366_lastGameExit;" in rth
      and "+ (nullable NSDictionary *)ame366_lastGameExit {" in rt
      and "ame366_lastExitRecord" in rt
      and "+ (nullable NSDictionary *)ame366_themeOverrides:(NSString *)kind" in rth
      and "rt.themeTokensByPlugin[pluginId]" in rt
      and "[AmePluginRuntime ame366_lastGameExit]" in bm
      and "[AmePluginRuntime ame366_themeOverrides:" in bm)
check('F3 设置键枚举链（PLPreferences 递归 → LauncherPreferences C 面 → 桥 listPrefKeys）',
      "- (NSArray<NSString *> *)ame366_registeredDottedKeys" in plh
      and "ame366_walkKeys" in plm
      and "NSArray<NSString *> *ame366_registeredPrefKeys(void);" in lph
      and "return [pref ame366_registeredDottedKeys];" in lpm
      and "ame366_registeredPrefKeys()" in bm)
check('F4 FS 沙盒守卫（.. 拒绝 + symlink 逃逸拒绝 + 空目录才可删）',
      "ame366_homePathFor" in bm and 'hasPrefix:resolvedBase' in bm
      and '".."' in bm and "仅空目录可删" in bm)

# ══ S 病灶变体反向比对 ═══════════════════════════════════════
check('S1 v7 现役不含 v6 残留（20 项行只在归档），v6 归档不含 v7 特有（33 项行）',
      "共 20 项" not in produced(v7_zone) and "权限共 33 项" not in produced(v6_zone))
check('S2 新方法全在 JSExport 协议（Task332 判例：协议外方法 JS 侧必 undefined）',
      all(x in proto for x in ["viewsBatch:(NSArray *)ops", "dialogPrompt:(NSDictionary *)spec callback:(JSValue *)cb",
          "clipboardGetText", "listPrefKeys:(NSString *)prefix", "renameProfile:(NSString *)oldName to:",
          "setJITScheme:(NSString *)scheme", "aiAsk:(NSString *)prompt callback:(JSValue *)cb",
          "downloadWithURL:(NSString *)urlString to:(NSString *)relPath callback:(JSValue *)cb",
          "fsMove:(NSString *)fromPath to:(NSString *)toPath", "analyzeLatestHsErr"]))
raw_names = ["getAppInfo", "viewsBatch", "dialogPromptCallback", "dialogSheetCallback",
             "notifyWithTitleBody", "clipboardGetText", "listPrefKeys", "renameProfileTo",
             "getProfileKeyProfile", "setProfileKeyValueProfile", "getGameState",
             "setJITScheme", "searchLogPatternLimit", "listModsWithProfile",
             "listWorldsForProfile", "getAccountList", "aiAskCallback",
             "listControlLayouts", "fsMoveTo", "downloadWithURLToCallback",
             "analyzeLatestHsErr", "getThemeTokens"]
s3_pairs = [n for n in raw_names if ("raw." + n) not in facade]
check('S3 门面 22 个新 raw 名与桥面成对存在（无幽灵名）', not s3_pairs, f"facade 缺失={s3_pairs}")

print(f"\name366_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print("  FAIL:", f)
    sys.exit(1)
