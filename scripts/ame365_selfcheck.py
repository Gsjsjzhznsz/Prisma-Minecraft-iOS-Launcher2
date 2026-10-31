#!/usr/bin/env python3
# ame365_selfcheck.py -- Task 365 门禁（插件提示词独立化 + 自修复三件套）
# 用户拍板："单独开个插件提示词，用户说要生成插件 AI 才会看另一个提示词，避免太
# 消耗 token"；"补齐所有 API，目标是整个启动器完全可以修改没有限制，特别是 JIT
# 和游戏启动部分，启动器崩溃用户直接找 AI 修"。
# A 桥面四新 API（JSExport 协议声明 + 实现 + 权限执法 + 门面接线）
# B 权限注册表 16→20 + 四语言 i18n 40 键
# C 提示词 v6（瘦身高保真：契约+铁律+20 项行；巨型 API 块移出）+ v5 留档逐字节 + 迁移链
# D get_plugin_docs 文档工具（注册/只读/全量内容锚）
# E 反向探针：文档里的每个 ame.* 名必须真实存在于门面/桥面（防文档漂移）
# F 自修复三件套接线实锚（JIT 四态/内置轨/启动链/日志四源）
# S 病灶变体反向比对（必翻红项注入检查）
import io, re, subprocess, sys

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
aiset = read("Natives/AI/AiSettings.m")
ptool = read("Natives/AI/AiPluginWriterTool.m")
dtool = read("Natives/AI/AiPluginDocsTool.m")
dhead = read("Natives/AI/AiPluginDocsTool.h")
boot = read("Natives/AI/AiToolBootstrapper.m")
agent = read("Natives/AI/AiAgent.m")

# ══ A 桥面 ═══════════════════════════════════════════════════
check('A1 .h JSExport 四声明 + nullable 限定',
      "- (nullable NSDictionary *)getJITState;" in bh
      and "- (void)enableJIT:(JSValue *)cb;" in bh
      and "- (void)launchGameWithProfile:(NSDictionary *)opts callback:(JSValue *)cb;" in bh
      and "- (nullable NSString *)readLog:(NSString *)which limit:(double)maxLines;" in bh)
check('A2 .m 四实现 + 权限执法点（jit.read/jit.write/game.launch/logs.read 各一道闸）',
      'ame317_requirePerm:@"jit.read"' in bm
      and 'ame317_requirePerm:@"jit.write"' in bm
      and 'ame317_requirePerm:@"game.launch"' in bm
      and 'ame317_requirePerm:@"logs.read"' in bm
      and "- (NSDictionary *)getJITState {" in bm
      and "- (void)enableJIT:(JSValue *)cb {" in bm
      and "- (void)launchGameWithProfile:(NSDictionary *)opts callback:(JSValue *)cb {" in bm
      and "- (NSString *)readLog:(NSString *)which limit:(double)maxLines {" in bm)
check('A3 私有方法跨类消费前向声明（★r2 口径：类别定义须完整 @interface——导入 ZL2HomeViewController.h，@class 不够）',
      "@interface ZL2ShellViewController (Ame365Bridge)" in bm
      and "@interface ZL2HomeViewController (Ame365Bridge)" in bm
      and '#import "ZL2HomeViewController.h"' in bm
      and "- (UIViewController *)ame_childForIndex:(NSInteger)index;" in bm
      and "- (void)launchButtonTapped;" in bm)
check('A4 门面接线（JSExport 整形名逐一对齐 Task331 规则）',
      'raw.getJITState()' in rt
      and 'raw.enableJIT(cb||function(){})' in rt
      and 'raw.launchGameWithProfileCallback(p||{},cb||function(){})' in rt
      and 'raw.readLogLimit(' in rt
      and "ame.jit={" in rt and "ame.launchGame=" in rt and "ame.readLog=" in rt)
check('A5 StikDebug 头导入（Task291/294 JIT 面）',
      '#import "StikDebugViewController.h"' in bm)

# ══ B 权限注册表 + i18n ═══════════════════════════════════════
check('B1 注册表 33 实体（★Task366 重锚：20 + 13 扩容组）+ ame.super 居首',
      pm.count('initWithId:@"') == 33
      and pm.index('initWithId:@"ame.super"') < pm.index('initWithId:@"events"'))
check('B2 危险位正确（jit.read/log.read 安全；jit.write/game.launch 高危）',
      'initWithId:@"jit.read"      danger:NO' in pm
      and 'initWithId:@"jit.write"     danger:YES' in pm
      and 'initWithId:@"game.launch"   danger:YES' in pm
      and 'initWithId:@"logs.read"     danger:NO' in pm)
i18n_ok = True
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN"]:
    t = read(f"Natives/resources/{lang}.lproj/Localizable.strings")
    n = len(re.findall(r'^"ame317\.perm\.[^"]+"\s*=', t, re.M))
    if n != 66:
        i18n_ok = False
        check(f'B3 {lang} 权限键 66（★Task366 重锚：33×name/desc）', False, f"got {n}")
check('B3 四语言权限键各 66（★Task366 重锚：33×name/desc）', i18n_ok)

# ══ C 提示词 v6 + v5 留档 + 迁移链 ════════════════════════════
v6_start = aiset.index("+ (NSString *)defaultSystemPrompt {")
v6_zone = aiset[v6_start:aiset.index("+ (NSString *)ame365_v5DefaultSystemPrompt {")]
v5_zone = aiset[aiset.index("+ (NSString *)ame365_v5DefaultSystemPrompt {"):]
v5_zone = v5_zone[:v5_zone.index("/// ★ Task364：v4 默认提示词全文")]

FRAG = re.compile(r'@?"((?:[^"\\]|\\.)*)"')
def produced(t):
    return "".join(m.group(1) for m in FRAG.finditer(t))

# ★ r1 基线口径修正：本提交合入后 HEAD 的 defaultSystemPrompt 已是 v6，
#   "HEAD=v5" 只在提交前成立。改用 pickaxe 动态定位 v5 基线 = 首个引入
#   ame365_v5DefaultSystemPrompt 的提交的父提交（该提交永不变化，跨后续
#   提交稳定）。
_intro = subprocess.run(["git", "-C", REPO, "log", "--format=%H", "-S",
                         "ame365_v5DefaultSystemPrompt", "--", "Natives/AI/AiSettings.m"],
                        capture_output=True, text=True, check=True).stdout.split()
_base = (_intro[-1] + "^") if _intro else "HEAD"
head_v5 = subprocess.run(["git", "-C", REPO, "show", f"{_base}:Natives/AI/AiSettings.m"],
                         capture_output=True, text=True, check=True).stdout.replace("\r\n", "\n")
h5 = head_v5[head_v5.index("+ (NSString *)defaultSystemPrompt {"):head_v5.index("/// ★ Task364：v4 默认提示词全文")]
check('C1 v5 留档产出串 == git HEAD v5（逐字节迁移基线铁律）',
      produced(v5_zone) == produced(h5),
      f"archive={len(produced(v5_zone))} head={len(produced(h5))}")
check('C2 v6 契约+铁律+20 项权限行在位',
      "get_plugin_docs" in produced(v6_zone) and "create_plugin 参数" in produced(v6_zone)
      and "共 33 项" in produced(v6_zone) and "jit.write†" in produced(v6_zone)
      and "game.launch†" in produced(v6_zone) and "logs.read" in produced(v6_zone))
check('C3 v6 巨型 API 块确已移出（主题四家族/视图操纵/拖拽写法不再内联）',
      "setThemeToken(色令牌表)" not in produced(v6_zone)
      and "ame.views.find" not in produced(v6_zone)
      and "元素拖拽标准写法" not in produced(v6_zone))
check('C4 v6 其余章节逐字节不动（安装章/资源章/行为纪律原样）',
      "【一、用户想安装 Minecraft 时——必须先问清楚，不要直接装】" in produced(v6_zone)
      and "【行为纪律】" in produced(v6_zone)
      and "Sodium，必须连带安装 Podium 或 Podium Port" in produced(v6_zone))
check('C5 迁移链 v5→v6 支 + 终版号 6（幂等写一次）',
      "[ame267_saved isEqualToString:[self ame365_v5DefaultSystemPrompt]]" in aiset
      and "Task365: v5 default system prompt auto-upgraded to v6" in aiset
      and "[ame267_d setInteger:7 forKey:kSystemPromptVersionKey];" in aiset
      and "[ame267_d setInteger:5 forKey:kSystemPromptVersionKey];" not in aiset)
check('C6 v5 留档体量核（≈v5 全文，未截断）',
      len(produced(v5_zone)) > 5000 and "视图操纵" in produced(v5_zone)
      and "共 15 项" in produced(v5_zone))

# ══ D get_plugin_docs 文档工具 ════════════════════════════════
check('D1 工具注册 + 只读免确认 + 协议实现',
      '[registry registerTool:[[AiPluginDocsTool alloc] init]];' in boot
      and "AiToolPermissionReadOnly" in dtool
      and 'return @"get_plugin_docs";' in dtool
      and '<AiTool>' in dhead)
check('D2 文档含自修复三件套全量 API（jit/launch/log 签名与语义）',
      "ame.jit.state()" in dtool and "setupState ∈ enabled/ready/waitingConfiguration/unavailable" in dtool
      and "ame.jit.enable(function(res){})" in dtool and "res={success,message}" in dtool
      and "ame.launchGame(profile?, function(res){})" in dtool and "res={ok,message}" in dtool
      and "ame.readLog(which, lines)" in dtool and "'launcherOld'" in dtool and "'crash'" in dtool)
check('D3 文档含主题四家族/视图操纵/拖拽标准写法（v5 全量面平移）',
      "ame.setThemeToken(色令牌表)" in dtool and "ame.theme.setLayout(排版刻度表)" in dtool
      and "ame.theme.setStructure({shellLayout:'topbar'|'navigationview'})" in dtool
      and "ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});" in dtool
      and "SurfaceView/GameSurfaceView/ScrollableSurfaceView" in dtool)
check('D4 文档含权限 20 项表 + create_plugin 契约 + 官方演示件',
      "共 33 项" in dtool and "ame.super" in dtool
      and "create_plugin 参数" in dtool and "(function(){...})();" in dtool
      and "element-drag" in dtool and "launch-counter" in dtool)
check('D5 create_plugin 描述同步（文档前置铁律 + ★Task366 33 项权限值域 + 三件套速览）',
      "get_plugin_docs" in ptool and "jit.read/jit.write/game.read/game.launch/" in ptool
      and "ame.jit.state/enable/setScheme/schemes" in ptool and "ame.launchGame(profile?,cb)" in ptool
      and "ame.logs read/list/search" in ptool)
check('D6 AiAgent 动态注入句（工具能力附录点名 get_plugin_docs）',
      "get_plugin_docs" in agent and "静默失效" in agent)

# ══ E 反向探针：文档 ame.* 面与门面/桥面实存对齐（防文档漂移） ══
facade = rt[rt.index('static NSString *ame317_facadeSource(void)'):]
facade = facade[:facade.index('#pragma mark - 装载 / 卸载')]
docs_text = produced(dtool)
doc_top = set(re.findall(r'ame\.([a-zA-Z]+)\s*[\(.=]', docs_text))
facade_top = set(re.findall(r'ame\.([a-zA-Z]+)\s*=', facade))
facade_top |= set(re.findall(r'ame\.([a-zA-Z]+)\.', facade))  # ★Task366：命名空间点链成员
missing_top = sorted(doc_top - facade_top)
check('E1 文档 ame.* 顶层名 ⊆ 门面顶层名', not missing_top, f"missing={missing_top}")
doc_ns = {}
for m in re.finditer(r'ame\.(views|jit|storage)\.([a-zA-Z]+)', docs_text):
    doc_ns.setdefault(m.group(1), set()).add(m.group(2))
facade_ns = {}
for ns in ("views", "jit", "storage"):
    blk = re.search(r'ame\.' + ns + r'=\{(.*?)\};', facade, re.S)
    members = set()
    if blk:
        members |= set(re.findall(r'([a-zA-Z]+):function', blk.group(1)))
    # ★Task366：对象字面量外的点链外挂成员（ame.views.animate=...）
    members |= set(re.findall(r'ame\.' + ns + r'\.([a-zA-Z]+)\s*=', facade))
    facade_ns[ns] = members
ns_missing = {k: sorted(v - facade_ns.get(k, set())) for k, v in doc_ns.items()
              if not v.issubset(facade_ns.get(k, set()))}
check('E2 文档命名空间成员 ⊆ 门面命名空间成员（views/jit/storage）',
      not ns_missing, f"missing={ns_missing}")
check('E3 文档零引用未实现 API（launchGameWithArgs/readGamePrefs 等幽灵名）',
      "ame.readGamePrefs" not in docs_text and "ame.launchGameWithArgs" not in docs_text
      and "ame.system(" not in docs_text)

# ══ F 自修复三件套接线实锚 ═══════════════════════════════════
check('F1 JIT 面接线（四态映射/内置轨可用性/共享开启入口/方案偏好键）',
      "ame291_setupState" in bm and "Ame291JITSetupStateEnabled" in bm
      and "ame294_builtinTrackAvailable" in bm
      and "ame294_enableBuiltinJITWithCompletion" in bm
      and 'getPrefObject(@"debug.jit_enabler")' in bm)
check('F2 JIT 回调主线程化（dispatch_async main + ame317_callCallback 契约）',
      bm.index("dispatch_async(dispatch_get_main_queue()") < bm.index("- (void)enableJIT:")
      or "dispatch_async(dispatch_get_main_queue(), ^{" in bm.split("- (void)enableJIT:")[1][:200])
check('F3 启动链走主页同款入口（游戏运行中拒绝 + Shell/Home 判型 + launchButtonTapped）',
      'isEqualToString:@"SurfaceViewController"' in bm
      and '[root isKindOfClass:[ZL2ShellViewController class]]' in bm
      and "ame_childForIndex:0" in bm
      and "launchButtonTapped];" in bm)
check('F4 日志四源路径（launcher/launcherOld/game/crash + 尾读封顶）',
      '@"latestlog.txt"' in bm and '@"latestlog.old.txt"' in bm
      and '@"logs/latest.log"' in bm and '@"crash-reports"' in bm
      and "48 * 1024" in bm and "substringToIndex:2000" in bm)

# ══ S 病灶变体反向比对 ═══════════════════════════════════════
check('S1 v6 不含 v5 残留（15 项权限行/巨型令牌表），v5 留档不含 v6 特有（get_plugin_docs）',
      "共 15 项" not in produced(v6_zone) and "setThemeToken(色令牌表)" not in produced(v6_zone)
      and "get_plugin_docs" not in produced(v5_zone))
check('S2 桥面方法全在 JSExport 协议（Task332 判例：协议外方法 JS 侧必 undefined）',
      all(m in bh for m in [
          "getJITState", "enableJIT:", "launchGameWithProfile:",
          "readLog:(NSString *)which limit:(double)maxLines;"]))
check('S3 门面 JIT 双参错位探针（enable 必单参 cb，launchGame 必兼容函数首参）',
      "enable:function(cb){return raw.enableJIT(cb||function(){});}" in rt
      and "if(typeof p==='function'){cb=p;p={};}" in rt)

print(f"\name365_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print("  FAIL:", f)
    sys.exit(1)
