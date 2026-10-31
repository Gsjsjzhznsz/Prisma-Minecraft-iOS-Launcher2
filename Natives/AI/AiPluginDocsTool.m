//
//  AiPluginDocsTool.m
//  Prisma
//
//  get_plugin_docs（Task365）。只读无副作用（AiToolPermissionReadOnly，
//  免确认零摩擦）；返回文本 = 插件系统全量 API 参考（与基础系统提示词
//  【七】章拆分的另一 половина：v5 时代该章全文塞在每条消息的系统提示词
//  里，插件话题缺席时纯烧 token；v6 起移入本工具按需返回）。
//  文档内容与 AmePluginBridge/Runtime 真实能力面逐条对齐——ame365_selfcheck
//  S 区反向探针会抽出文档里的每个 ame.* 名核对桥面/门面真实存在，防止
//  文档漂移（"提示词给了不存在的 API"与"存在但文档没给"同罪）。
//

#import "AiPluginDocsTool.h"

@implementation AiPluginDocsTool

- (NSString *)name {
    return @"get_plugin_docs";
}

- (NSString *)summary {
    return
    @"获取 Prisma 插件系统全量 API 参考文档（写/改任何插件前必读）。返回内容："
    @"create_plugin 参数契约、20 项权限表、ame.* 全部 API（事件/主题四家族/"
    @"视图操纵与元素拖拽/JIT 控制/游戏启动触发/日志读取/设置/渲染器/实例/"
    @"存储/网络/文件沙盒）、标准写法与示例。"
    @"仅当用户要求编写插件、修改插件、用插件改启动器界面或自修复启动器时调用；"
    @"一次会话调用一次即可。";
}

- (AiToolPermission)permission {
    return AiToolPermissionReadOnly;
}

+ (NSString *)pluginApiDocs {
    return
    @"═══ Prisma 插件系统全量 API 参考（ame 插件 = JavaScript，装好即运行）═══\n"
    @"\n"
    @"【0. 写插件铁律】\n"
    @"· 代码必须是纯 JS：无 require/import/浏览器对象；顶层用 (function(){...})(); 包裹；全文 ≤200KB。\n"
    @"· API 调用未经授权会抛异常：用 try/catch 捕获，并引导用户到 插件管理 → 对应插件 → 详情页 开启权限（高危权限安装后默认拒绝）。\n"
    @"· 插件效果出现在 设置 → 插件功能 区——每个插件必须至少 addLauncherRow 贡献一行，让用户看得见点得着。\n"
    @"· create_plugin 参数：id（小写字母/数字/._-，3-64 字符，全局唯一）、name（显示名 ≤64 字）、description（说明）、permissions（权限 id 数组，见【1】）、code（main.js 全文）、overwrite（同 id 覆盖，默认 false）。\n"
    @"· 多插件同名主题覆盖后写者胜；插件停用/卸载自动还原其视图改动与主题覆盖。\n"
    @"\n"
    @"【1. 权限表（共 20 项，†=高危：默认拒绝，需用户在插件详情页手动开启）】\n"
    @"events / ui.dialog / ui.rows / ui.theme† / ui.views† / settings.read / settings.write† / renderer.read / renderer.write† / profile.read / profile.write† / storage / net† / ui.nav / files.game† / jit.read / jit.write† / game.launch† / logs.read（另：ame.super 总权限=完全接管，用户显式开启后全部闸放行，永不自动授予）。\n"
    @"\n"
    @"【2. 事件（events）】ame.on(event, function(event,payload){}) / ame.off(event)。event ∈ app.launch / app.foreground / app.background / profile.changed / profile.listChanged / game.starting / game.exited（payload=退出码，0=正常）。\n"
    @"\n"
    @"【3. 界面贡献（ui.rows）】ame.addLauncherRow({id,title,subtitle}, onTap) —— 在 插件功能 区贡献按钮行（id 插件内唯一）。\n"
    @"【4. 弹窗与提示（ui.dialog）】ame.dialog({title,body,confirm?,cancel?,destructive?}, function(ok){})；ame.toast(text)；ame.log(text)。\n"
    @"【5. 页面导航（ui.nav）】ame.openPage(id)，id ∈ home/download/versions/accounts/settings/multiplayer/ai。\n"
    @"\n"
    @"【6. 主题四家族（ui.theme†；立即全界面生效、持久化重放、传空 {} 撤销本插件该族覆盖）】\n"
    @"· ame.setThemeToken(色令牌表)：28 个色令牌整包换肤，值 '#RRGGBB'/'#RRGGBBAA'——primary/secondary/tertiary 各 onX+containerX 四件套、surface/onSurface/surfaceVariant/onSurfaceVariant、surfaceContainer 五档+surfaceBright、outline/outlineVariant、error/errorContainer/success/warning。\n"
    @"· ame.setThemeShape(形状/字阶表)：radiusXS/S/M/L/XL（0-40pt）；fontHeadline/fontTitleLarge/fontTitleMedium/fontBodyLarge/fontBodyMedium/fontLabelLarge/fontLabelMedium，值 {size:8-40, weight:regular/medium/semibold/bold 或 400-700}。\n"
    @"· ame.setThemeLayout(排版刻度表)：13 个布局刻度——searchBarHeight 32-64 / chipHeight 24-48 / buttonHeight 28-64 / pillHeight 20-56 / pillGap 0-32 / pillMinWidth 32-160 / cardMarginV 0-24 / cardMarginH 0-40 / cardInsetX·cardInsetTop·cardInsetBottom 0-40 / cardContentGap 0-24 / dialogInset 8-48。\n"
    @"· ame.setThemeStructure({shellLayout:'topbar'|'navigationview'})：壳层导航骨架换蓝图（顶栏制 ↔ 左窗格制）。\n"
    @"\n"
    @"【7. 视图操纵（ui.views†）——查询并操纵启动器界面任意原生元素（自修复主通道：界面遮挡/错位/按钮点不到可直接修）】\n"
    @"· ame.views.find({cls?,text?,ident?,tag?,limit?}) → [{handle,cls,text,frame:{x,y,w,h},alpha,hidden,enabled}]（cls/text 大小写不敏感子串；ident/tag 精确；handle 本次装载会话内有效）。\n"
    @"· ame.views.apply(handle,{x?,y?,w?,h?,alpha?,hidden?,cornerRadius?,text?,bg?,enabled?})：移动/缩放/隐藏/改文字/染色（bg=#RRGGBB(AA)；坐标=父视图坐标 pt，数值有钳制）。\n"
    @"· ame.views.on(handle,'tap'|'pan'|'longpress'|'swipe',function(ev){})：挂手势。pan 事件 ev={state:'began/changed/ended/cancelled',dx,dy,tx,ty,frame:{x,y,w,h},x,y}（dx/dy=距上次事件位移、tx/ty=自按下累计，窗口坐标系零漂移）。\n"
    @"· ame.views.reset(handle)：还原本插件对该元素全部改动并摘除本插件手势。\n"
    @"· 禁改名单：游戏渲染面子树（SurfaceView/GameSurfaceView/ScrollableSurfaceView）查询跳过、改写拒绝——插件碰渲染面=游戏黑屏。\n"
    @"· 元素拖拽标准写法：var h=ame.views.find({text:'启动'})[0].handle; var st=null; ame.views.on(h,'pan',function(ev){if(ev.state==='began'){st={x:ev.frame.x,y:ev.frame.y};}else if(ev.state==='changed'){ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});}});\n"
    @"· 布局改动用 ame.storage 持久化 {cls,text}→偏移 并在 app.launch 重放 = 随启动生效的布局插件。\n"
    @"\n"
    @"【8. JIT 控制（jit.read / jit.write†）——游戏黑屏/闪退多为 JIT 未开启】\n"
    @"· ame.jit.state() → {enabled:bool, setupState:'enabled'|'ready'|'waitingConfiguration'|'unavailable', builtinTrackAvailable:bool, scheme:string}（scheme=当前 JIT 方案偏好，如 auto/builtin/stikjit）。\n"
    @"· ame.jit.enable(function(res){}) → res={success:bool, message:string}：触发内置轨开启（与 设置 → 调试 开启按钮同链，iOS 17.4+ 且配对文件在位时可用）。setupState=unavailable/waitingConfiguration 时引导用户到 设置 → 调试 配置。\n"
    @"\n"
    @"【9. 游戏启动（game.launch†）】\n"
    @"· ame.launchGame(profile?, function(res){}) —— res={ok:bool, message:string}。走主页启动按钮完整链路：版本校验 → 补全下载 → JIT 门禁等待 → 启动游戏；profile 缺省=当前选中实例，传实例名可切换选中（如 ame.launchGame('1.20.1 Fabric 2026.08.26', cb)）。游戏运行中拒绝重复启动；启动成功/退出后 game.starting / game.exited 事件照常广播。\n"
    @"\n"
    @"【10. 日志读取（logs.read）——崩溃自诊断主输入】\n"
    @"· ame.readLog(which, lines) → 日志尾部文本。which ∈ 'launcher'（启动器日志 latestlog.txt，含游戏 stdout/stderr 重定向，诊断首选）| 'launcherOld'（上次启动）| 'game'（实例 logs/latest.log）| 'crash'（最新崩溃报告全文头）。lines 行数默认 200 上限 1000。\n"
    @"· 自修复标准姿势：ame.on('game.exited',function(ev,code){ if(code!==0){ var tail=ame.readLog('launcher',300); /* 分析关键字如 Exception/FATAL 后 */ ame.dialog({title:'游戏异常退出',body:'退出码 '+code+'，已记录日志尾段，可让 AI 助手继续分析'}); } });\n"
    @"\n"
    @"【11. 启动器设置（settings.read / settings.write†）】ame.getPref(key) / ame.setPref(key,value)：键名限字母数字._- 且 ≤128；plugin.* 前缀禁写；按 JS 值类型自动落盘（与设置页同源同效）。常用键：video.renderer、mobileglues.renderer_backend、debug.jit_enabler、general.ram_allocation。\n"
    @"【12. 渲染器（renderer.read / renderer.write†）】ame.getRenderer() → {renderer,backend,effective,available}；ame.setRenderer({renderer}) 或 ({backend})（backend ∈ mobilegl/mobileglues_gles/mithril；下次启动生效）。\n"
    @"【13. 实例档案（profile.read / profile.write†）】ame.getProfiles() → [{name,version,gameDir}]；ame.createProfile({name,version?,gameDir?})；ame.deleteProfile(name)（(Default) 与当前选中拒绝删除）。\n"
    @"【14. 私有存储（storage）】ame.storage.get/set/remove/keys，JSON 值，4MB 上限。\n"
    @"【15. 网络（net†）】ame.fetch(url, opts?, cb)，opts={method:GET/POST/PUT/DELETE/HEAD, headers:{}, body:'字符串'}，cb(err,resp)，resp={status,body}；30 秒超时。\n"
    @"【16. 游戏目录文件沙盒（files.game†）】仅当前实例游戏目录内相对路径（禁 .. 与绝对路径与软链逃逸）：ame.listFiles(目录) → [{name,isDir,size}]；ame.readFile(路径)（≤2MB）；ame.writeFile(路径,文本,append?)（≤4MB，父目录自动创建）；ame.removeFile(路径)（仅空目录或文件）。\n"
    @"\n"
    @"【17. 示例：启动计数器】ame.on('game.starting',function(){var s=ame.storage.get('n')||0;ame.storage.set('n',s+1);}); ame.addLauncherRow({id:'show',title:'启动统计'},function(){ame.dialog({title:'统计',body:'累计启动 '+(ame.storage.get('n')||0)+' 次'});});\n"
    @"官方插件仓库内置演示件（插件仓库页可查源码）：launch-counter（事件+存储）、modrinth-hot（网络）、renderer-quickswitch（渲染器）、theme-sunset（主题全家族）、fluent-ui（主题/结构全家桶参考实现）、element-drag（视图操纵/拖拽参考实现）。\n";
}

#pragma mark - 执行

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    completion([AiPluginDocsTool pluginApiDocs], nil);
}

@end
