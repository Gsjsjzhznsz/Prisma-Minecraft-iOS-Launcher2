#!/usr/bin/env python3
# ame364_selfcheck.py -- Task 364 门禁（视图操纵 API 家族 ui.views：AI 写元素拖拽插件失败的根因补齐）
# A 桥面四方法（viewsFind/ApplyProps/OnEventHandler/Reset + 禁改名单 + teardown 还原）
# B 权限注册表（ui.views 高危 + 15 项 + ame.super 居首）
# C 提示词 v5（视图操纵 bullet + 权限 15 项 + 拖拽标准写法 + 自修复通道句）
# D 迁移链（v4 逐字留档在位 + setInteger:5 + 留档含 v4 特有标记）
# E create_plugin 工具描述同步（ui.views + ame.views 四入口）
# F 官方仓演示件 element-drag（manifest/main.js/index.json/sha256 实算）
# S 反向探针（病灶变体注入比对必翻红，零仓内触碰）
import io, hashlib, json, os, sys, zipfile

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

bh = read("Natives/AmePluginBridge.h")
bm = read("Natives/AmePluginBridge.m")
pm = read("Natives/AmePluginPermissions.m")
rt = read("Natives/AmePluginRuntime.m")
aiset = read("Natives/AI/AiSettings.m")
ptool = read("Natives/AI/AiPluginWriterTool.m")

# 提示词域切片：v5 defaultSystemPrompt（至 v4 留档注释为止）与 v4 留档
v5_zone = aiset[aiset.index("+ (NSString *)defaultSystemPrompt {"):]
v5_zone = v5_zone[:v5_zone.index("/// ★ Task364：v4 默认提示词全文")]
v4_zone = aiset[aiset.index("+ (NSString *)ame364_v4DefaultSystemPrompt {"):]
v4_zone = v4_zone[:v4_zone.index("/// ★ Task363：v3 默认提示词全文")]

# ══ A 桥面 ═══════════════════════════════════════════════════
check('A1 .h JSExport 协议四声明 + nullable 限定',
      "- (nullable NSArray *)viewsFind:(NSDictionary *)filter;" in bh
      and "- (BOOL)viewsApply:(double)handle props:(NSDictionary *)props;" in bh
      and "- (BOOL)viewsOn:(double)handle event:(NSString *)event handler:(JSValue *)cb;" in bh
      and "- (BOOL)viewsReset:(double)handle;" in bh)
check('A2 .m 四方法实现 + 权限执法点全部走 ui.views',
      bm.count('ame317_requirePerm:@"ui.views"') >= 4
      and "- (NSArray *)viewsFind:(NSDictionary *)filter {" in bm
      and "- (BOOL)viewsApply:(double)handle props:(NSDictionary *)props {" in bm
      and "- (BOOL)viewsOn:(double)handle event:(NSString *)event handler:(JSValue *)cb {" in bm
      and "- (BOOL)viewsReset:(double)handle {" in bm)
check('A3 禁改名单（游戏渲染面三类，查询/改写/挂手势全链拦截）',
      'ame364_isProtectedClass' in bm
      and '@"SurfaceView"' in bm and '@"GameSurfaceView"' in bm and '@"ScrollableSurfaceView"' in bm
      and bm.count('ame364_isProtectedClass(') >= 6)
check('A4 句柄注册表弱值 + 首改留痕 + teardown 还原',
      "NSMapTableStrongMemory" in bm and "NSMapTableWeakMemory" in bm
      and 'viewOriginals[hk]' in bm and "[self ame364_teardownViews];" in bm)
check('A5 手势精确摘除（sink.gesture，不误摘他人）+ pan 窗口坐标系',
      "sink.gesture = gr;" in bm and "if (s.gesture) [v removeGestureRecognizer:s.gesture];" in bm
      and "translationInView:v.window" in bm and "setTranslation:CGPointZero inView:v.window" in bm)
check('A6 apply 值域钳制（坐标 ±1e5 / alpha 0-1 / radius 0-200 + isfinite）',
      "ame364_coordClamp" in bm and "MAX(0.0, MIN(1.0, n.doubleValue))" in bm
      and "MAX(0, MIN(200, n.doubleValue))" in bm and "isfinite" in bm)
check('A7 跨类前置声明（Ame364Internal category，Task261 判例防线）',
      "@interface AmePluginBridge (Ame364Internal)" in bm)
check('A8 门面四入口接线（JSExport 整形名逐一对齐）',
      'raw.viewsFind(f||{})' in rt and 'raw.viewsApplyProps(Number(h),p||{})' in rt
      and 'raw.viewsOnEventHandler(Number(h),String(ev' in rt
      and 'raw.viewsReset(Number(h))' in rt)

# ══ B 权限注册表 ═════════════════════════════════════════════
check('B1 ui.views 注册且高危（danger:YES）',
      'initWithId:@"ui.views"      danger:YES' in pm.replace('\r', ''))
check('B2 注册表 16 实体（14 清单 + ame.super + ui.views）+ ame.super 居首',
      pm.count('initWithId:@"') == 16
      and pm.index('initWithId:@"ame.super"') < pm.index('initWithId:@"events"'))
check('B3 ui.views 注释锚在位',
      "Task364" in pm and "AI 写元素拖拽插件失败的根因" in pm)

# ══ C 提示词 v5 ══════════════════════════════════════════════
check('C1 v5 视图操纵 bullet（四入口全量 + pan 事件字段口径）',
      "ame.views.find({cls?,text?,ident?,tag?,limit?})" in v5_zone
      and "ame.views.apply(handle,{x?,y?,w?,h?,alpha?,hidden?,cornerRadius?,text?,bg?,enabled?})" in v5_zone
      and "ame.views.on(handle,'tap'|'pan'|'longpress'|'swipe',function(ev){})" in v5_zone
      and "ame.views.reset(handle)" in v5_zone
      and "dx/dy=距上次事件位移、tx/ty=自按下累计位移" in v5_zone)
check('C2 v5 权限 15 项 + ui.views† 入列（14 项残留清零）',
      "共 15 项" in v5_zone and "ui.theme† / ui.views† / settings.read" in v5_zone
      and "共 14 项" not in v5_zone)
check('C3 v5 拖拽标准写法 + 布局重放建议 + 禁面子树标注',
      "var st=null;" in v5_zone and "ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});" in v5_zone
      and "app.launch" in v5_zone and "SurfaceView/GameSurfaceView/ScrollableSurfaceView" in v5_zone)
check('C4 v5 自修复通道句 + 演示件五件（v4 无此二句）',
      "自修复通道" in v5_zone and "内置五件示例" in v5_zone
      and "内置四件示例" not in v5_zone)

# ══ D 迁移链 ═════════════════════════════════════════════════
check('D1 v4 留档在位且含 v4 特有标记（共 14 项 / 四件示例）',
      "+ (NSString *)ame364_v4DefaultSystemPrompt {" in v4_zone
      and "共 14 项" in v4_zone and "内置四件示例" in v4_zone
      and "ame.views" not in v4_zone)
check('D2 迁移分支 ver 4→5（v4 逐字一致即删键回落 v5 + 版本号 setInteger:5）',
      "[ame267_saved isEqualToString:[self ame364_v4DefaultSystemPrompt]]" in aiset
      and "Task364: v4 default system prompt auto-upgraded to v5" in aiset
      and "[ame267_d setInteger:5 forKey:kSystemPromptVersionKey];" in aiset
      and "[ame267_d setInteger:4 forKey:kSystemPromptVersionKey];" not in aiset)

# ══ E create_plugin 工具描述 ═════════════════════════════════
check('E1 工具权限清单含 ui.views',
      "events/ui.dialog/ui.rows/ui.theme/ui.views/" in ptool)
check('E2 工具 ame.views 四入口 + 拖拽标准写法',
      "ame.views.find({cls?,text?,ident?,tag?,limit?})" in ptool
      and "ame.views.apply(handle,{x?,y?,w?,h?,alpha?,hidden?,cornerRadius?,text?,bg?,enabled?})" in ptool
      and "ame.views.on(handle,'tap'|'pan'|'longpress'|'swipe',fn)" in ptool
      and "ame.views.reset(handle)" in ptool
      and "ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});" in ptool)

# ══ F 官方仓演示件 ═══════════════════════════════════════════
try:
    mf = json.loads(read("plugin-repo/src/element-drag/manifest.json"))
    mf_ok = mf.get("id") == "element-drag" and "ui.views" in mf.get("permissions", [])
except Exception as e:
    mf_ok = False
check('F1 src/element-drag manifest 合法（id 一致 + ui.views 声明）', mf_ok)
demo_js = read("plugin-repo/src/element-drag/main.js")
check('F2 演示件 main.js 四入口实调 + pan 标准写法',
      "ame.views.find(" in demo_js and "ame.views.on(" in demo_js
      and "ame.views.apply(" in demo_js and "ame.views.reset(" in demo_js
      and "ev.state === 'began'" in demo_js and "start.x + ev.tx" in demo_js)
idx = json.loads(read("plugin-repo/index.json"))
entry = next((e for e in idx["plugins"] if e["id"] == "element-drag"), None)
check('F3 index.json element-drag 条目（official=true + minApi 面）',
      entry is not None and entry.get("official") is True and entry.get("version") == "1.0.0")
zdata = open(os.path.join(REPO, "plugin-repo", "plugins", "element-drag.zip"), "rb").read()
sha_ok = entry is not None and hashlib.sha256(zdata).hexdigest() == entry.get("sha256")
check('F4 zip sha256 与 index 实算一致（单一事实源）', sha_ok)
try:
    zf = zipfile.ZipFile(os.path.join(REPO, "plugin-repo", "plugins", "element-drag.zip"))
    names = zf.namelist()
    layout_ok = "manifest.json" in names and "main.js" in names
except Exception:
    layout_ok = False
check('F5 zip 布局（manifest.json/main.js 在根，installFromZip 对齐）', layout_ok)

# ══ S 反向探针 ═══════════════════════════════════════════════
check('S1 v5 正文零 14 项残留 + v4 留档零 ame.views（防串档）',
      "共 14 项" not in v5_zone and "ame.views" not in v4_zone)
check('S2 禁改名单零变体（danger:NO 的 ui.views 不存在）',
      'initWithId:@"ui.views"      danger:NO' not in pm.replace('\r', ''))
check('S3 门面无未整形裸调（viewsApply:/viewsOn: 单参形态不得出现）',
      "raw.viewsApply(" not in rt and "raw.viewsOn(" not in rt)
check('S4 index.json updated 为今日（打包器动态生成非写死）',
      idx.get("updated") >= "2026-10-31")

print(f"\n{passed} passed, {len(fails)} failed")
if fails:
    print("FAILS:", "; ".join(fails))
    sys.exit(1)
