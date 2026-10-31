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
    @"★ 必读前置：调用本工具之前，必须先调用 get_plugin_docs 获取插件全量 API "
    @"参考（ame.* 全部 API、20 项权限表、主题令牌/视图操纵/JIT 控制/游戏启动/"
    @"日志读取、元素拖拽与自修复标准写法、官方示例件）。API 名与签名一律以该"
    @"文档为准，绝不允许凭记忆编造——写错一个 API 名，插件就静默失效。\n"
    @"参数：id（小写字母数字._-，3-64 字符）、name（显示名）、description（说明）、"
    @"permissions（权限数组，可选值：events/ui.dialog/ui.rows/ui.theme/ui.views/"
    @"settings.read/settings.write/renderer.read/renderer.write/profile.read/storage/"
    @"net/ui.nav/profile.write/files.game/jit.read/jit.write/game.launch/logs.read；"
    @"† 高危权限安装后默认未授权，需用户在插件详情页开启）、"
    @"code（main.js 全文：纯 JS、无 require/import、顶层用 (function(){...})(); 包裹、≤200KB）、"
    @"overwrite（同 id 覆盖，默认 false）。\n"
    @"能力面速览（详情以 get_plugin_docs 为准）：ame.on/off 订阅七种事件"
    @"（app.launch/app.foreground/app.background/profile.changed/profile.listChanged/"
    @"game.starting/game.exited）；ame.addLauncherRow 贡献插件功能行；ame.dialog/"
    @"toast 弹窗提示；ame.openPage 七页导航；主题四家族 setThemeToken/Shape/Layout/"
    @"Structure 整包换肤重排版；ame.views.find/apply/on/reset 查询并操纵任意原生"
    @"元素（移动/缩放/隐藏/改文字/挂手势，元素拖拽主通路）；ame.jit.state()/"
    @"ame.jit.enable(cb) JIT 状态与开启；ame.launchGame(profile?,cb) 触发完整游戏"
    @"启动链；ame.readLog(which,lines) 读启动器/游戏/崩溃日志尾部（自诊断）；"
    @"ame.getPref/setPref 设置读写；ame.getRenderer/setRenderer 渲染器；"
    @"ame.getProfiles/createProfile/deleteProfile 实例档案；ame.storage 私有存储；"
    @"ame.fetch 网络；ame.listFiles/readFile/writeFile/removeFile 游戏目录文件沙盒。\n"
    @"注意：调用未授权 API 会抛异常，可 try/catch 引导用户去插件详情页授权；"
    @"每个插件应至少 addLauncherRow 贡献一行让用户可见可点。";
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
