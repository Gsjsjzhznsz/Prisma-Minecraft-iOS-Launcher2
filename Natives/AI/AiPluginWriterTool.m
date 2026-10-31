//
//  AiPluginWriterTool.m
//  Prisma
//
//  create_plugin（Task 327）。params 契约：
//    id          必填  ^[a-z0-9][a-z0-9._-]{2,63}$（与 manifest 校验同规）
//    name        必填  显示名 ≤64 字
//    description 选填  一句话说明（详情页/安装确认展示）
//    permissions 选填  权限 id 数组（必须 ⊆ AmePluginPermissions 注册表）
//    code        必填  main.js 全文（≤200KB；顶层 IIFE 包裹推荐）
//    overwrite   选填  同 id 已存在时是否覆盖（默认 false）
//  落盘即校验（manifestForPlugin 终审），失败清理半成品目录。
//  授权口径 = Task317 首装默认：普通权限授予、高危权限拒绝（详情页可改），
//  随后 setPluginEnabled:YES 即时装载（无需重启）。
//

#import "AiPluginWriterTool.h"
#import "AmePluginPermissions.h"
#import "AmePluginManager.h"
#import "AmePluginRuntime.h"

@implementation AiPluginWriterTool

- (NSString *)name {
    return @"create_plugin";
}

- (NSString *)summary {
    return
    @"为启动器编写并安装一个插件（AmePlugin，JavaScript）。安装后立即装载，"
    @"效果出现在 设置 → 插件功能 区（管理页亦可启停/授权）。\n"
    @"参数：id（小写字母数字._-，3-64 字符）、name（显示名）、description（说明）、"
    @"permissions（权限数组，可选值：events/ui.dialog/ui.rows/ui.theme/ui.views/"
    @"settings.read/settings.write/renderer.read/renderer.write/profile.read/storage/"
    @"net/ui.nav/profile.write/files.game；高危权限安装后默认未授权，需用户在插件详情页开启）、"
    @"code（main.js 全文）、overwrite（同 id 覆盖，默认 false）。\n"
    @"插件运行环境（全局对象 ame）：\n"
    @"· ame.on(event, fn)/ame.off(event)：订阅事件。event ∈ app.launch / "
    @"app.foreground / app.background / profile.changed / profile.listChanged / "
    @"game.starting / game.exited(payload=退出码)；回调签名 fn(event, payload)。\n"
    @"· ame.addLauncherRow({id,title,subtitle}, onTap)：在 设置 → 插件功能 区"
    @"贡献一行按钮（插件可见效果的主通道；id 在插件内唯一）。\n"
    @"· ame.dialog({title,body,confirm,cancel,destructive}, function(ok){})：弹窗。\n"
    @"· ame.toast(text)：轻提示。\n"
    @"· ame.storage.get(k)/set(k,v)/remove(k)/keys()：插件私有持久化（JSON 值）。\n"
    @"· ame.log(text)：日志。\n"
    @"· ame.fetch(url, opts?, cb)：网络 GET/POST/PUT/DELETE/HEAD，opts={method,headers,body}，"
    @"cb(err, resp)，resp={status,body}，30 秒超时（net 高危）。\n"
    @"· ame.setThemeToken({primary:'#RRGGBB',...})：28 个色令牌整包换肤，"
    @"色值 #RRGGBB 或 #RRGGBBAA（ui.theme 高危）。\n"
    @"· ame.setThemeShape({...})：圆角 radiusXS/S/M/L/XL（0-40pt）与字阶 "
    @"fontHeadline/TitleLarge/TitleMedium/BodyLarge/BodyMedium/LabelLarge/LabelMedium"
    @"（{size:8-40, weight:regular/medium/semibold/bold 或 400-700}）。\n"
    @"· ame.setThemeLayout({...})：13 个排版刻度（searchBarHeight/chipHeight/buttonHeight/"
    @"pillHeight/pillGap/pillMinWidth/cardMarginV/cardMarginH/cardInsetX/Top/Bottom/"
    @"cardContentGap/dialogInset，各有钳制区间）。\n"
    @"· ame.setThemeStructure({shellLayout:'topbar'|'navigationview'})：壳层导航骨架换蓝图。\n"
    @"  （主题四家族均 ui.theme 高危：立即全界面生效、持久化重放、传空 {} 撤销本插件覆盖。）\n"
    @"· ame.views（ui.views 高危）——查询并操纵启动器界面任意原生元素：\n"
    @"  - ame.views.find({cls?,text?,ident?,tag?,limit?}) → [{handle,cls,text,frame:{x,y,w,h},"
    @"alpha,hidden,enabled}]（cls/text 子串匹配；handle 会话内有效；游戏渲染面禁查改）。\n"
    @"  - ame.views.apply(handle,{x?,y?,w?,h?,alpha?,hidden?,cornerRadius?,text?,bg?,enabled?})："
    @"移动/缩放/隐藏/改文字/染色（bg=#RRGGBB/#RRGGBBAA；坐标=父视图坐标 pt）。\n"
    @"  - ame.views.on(handle,'tap'|'pan'|'longpress'|'swipe',fn)：挂手势；pan 事件 "
    @"ev={state:'began/changed/ended/cancelled',dx,dy,tx,ty,frame:{x,y,w,h},x,y}（dx/dy=增量，"
    @"tx/ty=自按下累计）。\n"
    @"  - ame.views.reset(handle)：还原本插件对该元素的改动+摘除本插件手势。\n"
    @"  元素拖拽标准写法：var h=ame.views.find({text:'启动'})[0].handle; var st=null; "
    @"ame.views.on(h,'pan',function(ev){if(ev.state==='began'){st={x:ev.frame.x,y:ev.frame.y};}"
    @"else if(ev.state==='changed'){ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});}});\n"
    @"· ame.getRenderer()/ame.setRenderer({renderer|backend})：渲染器读/切换（写高危，下次启动生效）。\n"
    @"· ame.getPref(k)/ame.setPref(k,v)：启动器偏好读写（settings.write 高危）。\n"
    @"· ame.getProfiles()：实例列表。\n"
    @"· ame.openPage('home'|'download'|'versions'|'accounts'|'settings'|'multiplayer'|'ai')：切页。\n"
    @"· ame.createProfile({name,version?,gameDir?})/ame.deleteProfile(name)：实例增删（高危）。\n"
    @"· ame.listFiles(p)/ame.readFile(p)/ame.writeFile(p,text,append?)/ame.removeFile(p)："
    @"当前实例游戏目录文件沙盒（高危，禁 .. 与绝对路径，读≤2MB 写≤4MB，仅空目录可删）。\n"
    @"示例：启动计数器 —— ame.on('game.starting',function(){var s=ame.storage.get('n')||0;"
    @"ame.storage.set('n',s+1);}); ame.addLauncherRow({id:'show',title:'启动统计'},function(){"
    @"ame.dialog({title:'统计',body:'累计启动 '+(ame.storage.get('n')||0)+' 次'});});\n"
    @"注意：代码必须是纯 JS（无 require/import）；顶层用 (function(){...})(); 包裹；"
    @"ame API 调用失败会抛异常，可 try/catch 引导用户去插件详情页授权。";
}

- (AiToolPermission)permission {
    return AiToolPermissionControlledWrite;
}

#pragma mark - 执行

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    NSString *pluginId = [self ame327_str:params[@"id"]];
    NSString *displayName = [self ame327_str:params[@"name"]];
    NSString *description = [self ame327_str:params[@"description"]] ?: @"";
    NSString *code = [self ame327_str:params[@"code"]];
    BOOL overwrite = [params[@"overwrite"] boolValue];

    void (^fail)(NSString *) = ^(NSString *msg) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:4200
                                        userInfo:@{NSLocalizedDescriptionKey: msg}]);
    };

    // ① id 校验（与 AmePluginManager manifest 校验同规）
    if (pluginId.length < 3 || pluginId.length > 64) return fail(@"id 长度须为 3-64");
    NSCharacterSet *ok0 = [NSCharacterSet characterSetWithCharactersInString:
                           @"abcdefghijklmnopqrstuvwxyz0123456789"];
    if (![ok0 characterIsMember:[pluginId characterAtIndex:0]]) return fail(@"id 须以小写字母或数字开头");
    NSCharacterSet *okAll = [NSCharacterSet characterSetWithCharactersInString:
                             @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    for (NSUInteger i = 0; i < pluginId.length; i++) {
        if (![okAll characterIsMember:[pluginId characterAtIndex:i]]) {
            return fail(@"id 仅允许小写字母/数字/._-");
        }
    }
    if (displayName.length == 0 || displayName.length > 64) return fail(@"name 必填且 ≤64 字");
    if (code.length == 0) return fail(@"code 必填（main.js 全文）");
    if ([code lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 200 * 1024) {
        return fail(@"code 超过 200KB 上限");
    }

    // ② 权限白名单校验
    NSMutableArray<NSString *> *perms = [NSMutableArray array];
    id permsRaw = params[@"permissions"];
    if (permsRaw != nil) {
        if (![permsRaw isKindOfClass:[NSArray class]]) return fail(@"permissions 须为数组");
        for (id p in (NSArray *)permsRaw) {
            if (![p isKindOfClass:[NSString class]]) return fail(@"permissions 元素须为字符串");
            if (![AmePluginPermissions isValidPermissionId:p]) {
                return fail([NSString stringWithFormat:@"未知权限 id：%@", p]);
            }
            if (![perms containsObject:p]) [perms addObject:p];
        }
    }

    // ③ 目录冲突守卫
    NSString *root = ame317_pluginsRootDir();
    NSString *dir = [root stringByAppendingPathComponent:pluginId];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:dir] && !overwrite) {
        return fail([NSString stringWithFormat:@"插件 %@ 已存在（覆盖请传 overwrite=true）", pluginId]);
    }
    if (![fm fileExistsAtPath:root]) {
        [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if ([fm fileExistsAtPath:dir] && ![fm removeItemAtPath:dir error:nil]) {
        return fail(@"旧插件目录清理失败");
    }
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) {
        return fail(@"插件目录创建失败");
    }

    // ④ manifest 落盘
    NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
    manifest[@"id"] = pluginId;
    manifest[@"name"] = displayName;
    manifest[@"version"] = @"1.0.0";
    manifest[@"author"] = @"AI 助手";
    if (description.length) manifest[@"description"] = description;
    manifest[@"entry"] = @"main.js";
    manifest[@"permissions"] = perms;
    manifest[@"minApi"] = @1;
    NSData *mData = [NSJSONSerialization dataWithJSONObject:manifest
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:nil];
    if (!mData || ![mData writeToFile:[dir stringByAppendingPathComponent:@"manifest.json"]
                             atomically:YES]) {
        [fm removeItemAtPath:dir error:nil];
        return fail(@"manifest 写入失败");
    }

    // ⑤ main.js 落盘
    NSData *cData = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!cData || ![cData writeToFile:[dir stringByAppendingPathComponent:@"main.js"]
                             atomically:YES]) {
        [fm removeItemAtPath:dir error:nil];
        return fail(@"main.js 写入失败");
    }

    // ⑥ 终审校验（与 zip 安装链同一事实源；失败清理半成品）
    AmePluginManifest *m = [AmePluginManager manifestForPlugin:pluginId];
    if (!m || ![AmePluginManager entryPathForPlugin:pluginId]) {
        [fm removeItemAtPath:dir error:nil];
        return fail(@"manifest 终审未通过（schema/权限白名单），已回滚");
    }

    // ⑦ 首装授权（Task317 口径：普通授予/高危拒绝）+ 即时装载
    NSMutableDictionary<NSString *, NSNumber *> *grants = [NSMutableDictionary dictionary];
    for (NSString *p in m.permissions) {
        grants[p] = @([AmePluginPermissions isDangerous:p] ? 0 : 1);
    }
    [AmePluginPermissions replaceGrants:grants forPlugin:m.pluginId];
    [AmePluginPermissions flushState];
    [AmePluginRuntime setPluginEnabled:m.pluginId enabled:YES];

    // ⑧ 结果报告（LLM 语义收口：告知效果位置与高危权限状态）
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *p in m.permissions) {
        [lines addObject:[NSString stringWithFormat:@"%@%@",
            [AmePluginPermissions isDangerous:p] ? @"⚠(需详情页授权) " : @"· ", p]];
    }
    NSString *permText = lines.count ? [lines componentsJoinedByString:@"\n"] : @"（无）";
    NSString *result = [NSString stringWithFormat:
        @"插件已创建并装载。\n"
        @"名称：%@（id: %@，v1.0.0）\n"
        @"权限：%@%@\n"
        @"效果位置：设置 → 插件功能 区（本插件贡献的行会出现在那里）。\n"
        @"⚠(需详情页授权) 标记的权限当前未授权，调用会抛异常——引导用户到 "
        @"设置 → 插件管理 → %@ → 详情页 打开对应开关。",
        displayName, pluginId, permText,
        (grants.count && [self ame327_hasDanger:grants]) ?
            @"\n（含高危权限，安装后默认拒绝）" : @"", displayName];
    completion(result, nil);
}

- (BOOL)ame327_hasDanger:(NSDictionary<NSString *, NSNumber *> *)grants {
    for (NSString *p in grants) {
        if ([AmePluginPermissions isDangerous:p]) return YES;
    }
    return NO;
}

- (NSString *)ame327_str:(id)raw {
    return [raw isKindOfClass:[NSString class]] ? raw : nil;
}

@end
