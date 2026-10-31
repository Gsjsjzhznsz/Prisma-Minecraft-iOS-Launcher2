#pragma once
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// AmePluginBridge（Task 317）
// -------------------------------------------------------------------
// 注入每个插件 JSContext 的 `ame` 对象。桥边界=权限唯一执法点：
//   每个 API 派发前先查 AmePluginPermissions，拒绝即抛 JS 异常。
// JS 调用形态（JSC 自动 ObjC↔JS 桥）：
//   ame.log("…") / ame.toast("…")
//   ame.on("game.starting", fn) / ame.off("game.starting")
//   ame.dialog({title, body, confirm, cancel}, function(ok){…})
//   ame.addLauncherRow({id, title, subtitle}, onTap)
//   ame.setThemeToken({primary:"#RRGGBB"})
//   ame.getPref("video.renderer") / ame.setPref("k", v)
//   ame.getRenderer() / ame.setRenderer({renderer:"mg", backend:"gles"})
//   ame.storage.get(k) / .set(k,v) / .remove(k) / .keys()
//   ame.fetch(url, {method, headers}, function(err, resp){…})
//   ame.getProfiles()
//   ame.openPage("home|download|versions|accounts|settings|multiplayer|ai")
//   ame.createProfile({name, version?, gameDir?}) / ame.deleteProfile(name)
//   ame.listFiles(p) / ame.readFile(p) / ame.writeFile(p, text, append?)
//     / ame.removeFile(p)     —— 均沙盒于当前实例游戏目录（files.game）
// ═══════════════════════════════════════════════════════════════════

// ★ Task331：桥面 JSExport 化 —— 设备装机 adb63d33 终审定性：JSC 的
//   ObjC↔JS 桥【只导出 JSExport 协议声明的方法】（Apple JSExport 契约；
//   未采纳协议的自定义类实例在 JS 侧是不透明对象，全部自定义方法
//   undefined）。AmePluginBridge 此前零协议采纳 → ameRaw.log/on/
//   addLauncherRowHandler/… 全链 undefined → 门面（ame317_facadeSource）
//   一经调用即 TypeError → 四内置件顶层 ame.* 首调即炸，行为面（行注册/
//   尾日志/事件/存储）整体静默或异常——插件系统自 Task317 上线以来在
//   设备端从未真正可用（CI/门禁均为 node 桩冒烟，从未覆盖 ObjC 桥面）。
//   JS 名整形规则 = selector 去冒号拼接、首段后各段首字母大写——与门面
//   既定调用名逐一对齐（log/onHandler/dialogCallback/addLauncherRowHandler/
//   setPrefValue/storageSetValue/fetchOptionsCallback/writeGameFileContentAppend）。
//   注意 storage.set：selector storageSet:value: 整形为 storageSetValue，
//   门面 Task331 同步改调 raw.storageSetValue（原名 storageSet 两参调用
//   在 JSExport 语义下必 undefined）。
@protocol AmePluginBridgeJSExport <JSExport>
- (void)log:(NSString *)msg;
- (void)toast:(NSString *)text;
- (void)dialog:(NSDictionary *)spec callback:(JSValue *)cb;
- (void)on:(NSString *)event handler:(JSValue *)cb;
- (void)off:(NSString *)event;
- (void)addLauncherRow:(NSDictionary *)spec handler:(JSValue *)cb;
- (BOOL)setThemeToken:(NSDictionary *)tokens;
// ★ Task341：形状/字体令牌覆盖（ui.theme 同权限；半径 pt 数值 + 字体阶
//   {size, weight} 混合键空间，白名单在 ZL2Theme 侧）。JSExport 协议声明
//   必不可缺——JSC 桥只导出协议声明的方法（Task332 判例）。
- (BOOL)setThemeShape:(NSDictionary *)tokens;
// ★ Task343：布局令牌覆盖（ui.theme 同权限；数值键空间 {searchBarHeight,
//   chipHeight, card*, pill*, dialogInset, buttonHeight} = pt 数值，白名单
//   + 钳制在 ZL2Theme 侧）。JSExport 协议声明必不可缺（Task332 判例）。
- (BOOL)setThemeLayout:(NSDictionary *)tokens;
// ★ Task347：结构令牌覆盖（ui.theme 同权限；字符串键空间 {shellLayout:
//   "topbar"|"navigationview"} = 壳层导航骨架蓝图，白名单在 ZL2Theme 侧）。
//   JSExport 协议声明必不可缺（Task332 判例）。
- (BOOL)setThemeStructure:(NSDictionary *)tokens;
// ★ Task364：视图操纵家族（ui.views 高危）——用户点题"插件可以随便改启动
//   器任何地方，AI 写元素拖拽插件都不行"的根因补齐：桥面此前只有主题令牌
//   （改样式）没有任何视图级 API（找元素/移动/隐藏/挂手势），拖拽类插件
//   结构性写不出。四方法全部走 ame317_requirePerm:@"ui.views" 执法；句柄
//   = viewsFind 返回的数字 id（弱引用注册表，视图释放即失效）；游戏渲染
//   面子树（SurfaceView/GameSurfaceView/ScrollableSurfaceView）内置禁改
//   名单，查询跳过、改写拒绝。JSExport 协议声明必不可缺（Task332 判例）。
//   JS 名整形（Task331 规则）：viewsFind / viewsApplyProps /
//   viewsOnEventHandler / viewsReset。
- (nullable NSArray *)viewsFind:(NSDictionary *)filter;
- (BOOL)viewsApply:(double)handle props:(NSDictionary *)props;
- (BOOL)viewsOn:(double)handle event:(NSString *)event handler:(JSValue *)cb;
- (BOOL)viewsReset:(double)handle;
// 空值限定与类接口逐字镜像（NS_ASSUME_NONNULL 区；拒绝时返 nil 的方法
// 协议侧必须显式 nullable，否则类采纳时 nullability conflict 编译报错）
- (nullable id)getPref:(NSString *)key;
- (BOOL)setPref:(NSString *)key value:(id)value;
- (nullable NSDictionary *)getRenderer;
- (BOOL)setRenderer:(NSDictionary *)cfg;
- (nullable NSArray *)getProfiles;
- (nullable id)storageGet:(NSString *)key;
- (BOOL)storageSet:(NSString *)key value:(id)value;
- (BOOL)storageRemove:(NSString *)key;
- (NSArray *)storageKeys;
- (void)fetch:(NSString *)urlString options:(NSDictionary *)opts callback:(JSValue *)cb;
- (void)openPage:(NSString *)pageId;
- (BOOL)createProfile:(NSDictionary *)spec;
- (BOOL)deleteProfile:(NSString *)name;
- (nullable NSArray<NSDictionary *> *)listGameFiles:(NSString *)relPath;
- (nullable NSString *)readGameFile:(NSString *)relPath;
- (BOOL)writeGameFile:(NSString *)relPath content:(NSString *)content append:(BOOL)append;
- (BOOL)removeGameFile:(NSString *)relPath;

// ★ Task365：自修复三件套（用户点题"特别是 JIT 和游戏启动部分"+"启动器崩溃
//   用户直接找 AI 修"）。JSExport 协议声明必不可缺（Task332 判例）。JS 名
//   整形（Task331 规则）：getJITState / enableJIT /
//   launchGameWithProfileCallback / readLogLimit。
//   ame.jit.state()（jit.read 安全）→ {enabled,setupState,builtinTrackAvailable,scheme}
//   ame.jit.enable(cb)（jit.write 高危）→ cb({success,message})（内置轨开启）
//   ame.launchGame(profile?, cb)（game.launch 高危）→ cb({ok,message})，
//     走主页完整启动链（版本校验→JIT 门禁→换根启动）；游戏运行中拒绝
//   ame.readLog(which, lines)（logs.read 安全）→ 日志尾部文本，
//     which ∈ launcher|launcherOld|game|crash，lines 默认 200 上限 1000
- (nullable NSDictionary *)getJITState;
- (void)enableJIT:(JSValue *)cb;
- (void)launchGameWithProfile:(NSDictionary *)opts callback:(JSValue *)cb;
- (nullable NSString *)readLog:(NSString *)which limit:(double)maxLines;
@end

@interface AmePluginBridge : NSObject <AmePluginBridgeJSExport>

/// 所属插件 id（权限查询键）
@property (nonatomic, copy, readonly) NSString *pluginId;
/// manifest 声明的权限（用于快速短路：未声明直接拒，连查询都不必）
@property (nonatomic, copy, readonly) NSArray<NSString *> *declaredPermissions;

- (instancetype)initWithPluginId:(NSString *)pluginId
            declaredPermissions:(NSArray<NSString *> *)permissions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 事件回调注册表运行时互访（Runtime 派发用）
/// 返回该事件的全部 JS 回调（主线程调用后即失效持引用者负责）
- (NSArray<JSValue *> *)handlersForEvent:(NSString *)event;
/// 注册插件贡献行（Runtime/列表页互访；返回行 id，重复 id 覆盖）
- (NSArray<NSDictionary *> *)contributedRows;
- (void)invokeRowTap:(NSString *)rowId;
/// 插件停用/卸载：清事件表/贡献行（主题令牌还原由 Runtime 统一调）
- (void)teardown;
/// 读插件私有存储（Runtime 装载期主题重放用；内部含 storage 权限门）
- (nullable id)storageGet:(NSString *)key;

#pragma mark - Task327 权限扩大 API

/// 页面导航（ui.nav）：切换启动器主页面（ZL2ShellNavigate 通知契约）
- (void)openPage:(NSString *)pageId;
/// 实例档案写（profile.write，高危）：创建/删除实例档案 + ReloadProfileList
- (BOOL)createProfile:(NSDictionary *)spec;
- (BOOL)deleteProfile:(NSString *)name;
/// 游戏目录文件沙盒（files.game，高危）：当前实例 POJAV_GAME_DIR 内
/// 相对路径读写删列（路径守卫 + 大小限额；symlink 逃逸拒绝）
- (nullable NSArray<NSDictionary *> *)listGameFiles:(NSString *)relPath;
- (nullable NSString *)readGameFile:(NSString *)relPath;
- (BOOL)writeGameFile:(NSString *)relPath
              content:(NSString *)content
               append:(BOOL)append;
- (BOOL)removeGameFile:(NSString *)relPath;

@end

NS_ASSUME_NONNULL_END
