#import "FabricUtils.h"
#import "PLMirrorCenter.h"
#import "PLProfiles.h"
#import "utils.h"

extern NSMutableArray *localVersionList; // Task302 谱系：本地版本注册表（安装器家族共用 extern）

/// Task336 内部：async GET（NSURLSession 原生，候选轮询用；AFNetworking 由
/// 安装器 TU 自持，本工具层保持零重依赖）。completion 后台线程回调；
/// json 为已解析的 NSDictionary 或 NSArray（Modrinth 版本查询返回数组）
static void ame336_asyncGet(NSURL *url, void (^completion)(id json, NSError *error)) {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 20;
    cfg.timeoutIntervalForResource = 40;
    cfg.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        @"Accept": @"*/*"
    };
    [[[NSURLSession sessionWithConfiguration:cfg]
        dataTaskWithURL:url
      completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error || !data) {
            completion(nil, error ?: [NSError errorWithDomain:@"FabricUtils" code:-1
                                                     userInfo:@{NSLocalizedDescriptionKey: @"empty response"}]);
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]] && ![json isKindOfClass:[NSArray class]]) {
            completion(nil, [NSError errorWithDomain:@"FabricUtils" code:-2
                                            userInfo:@{NSLocalizedDescriptionKey: @"unexpected payload"}]);
            return;
        }
        completion(json, nil);
    }] resume];
}

/// Task336 内部：profile json 候选轮询（PLMirrorCenter 策略序，首中即返）
static void ame336_fetchProfile(NSArray<NSURL *> *candidates, void (^completion)(NSDictionary *json, NSError *error)) {
    if (candidates.count == 0) {
        completion(nil, [NSError errorWithDomain:@"FabricUtils" code:-3
                                       userInfo:@{NSLocalizedDescriptionKey: @"no mirror candidates"}]);
        return;
    }
    __block NSUInteger idx = 0;
    __block void (^tryNext)(void);
    tryNext = ^{
        if (idx >= candidates.count) {
            tryNext = nil; // 断自持环
            completion(nil, [NSError errorWithDomain:@"FabricUtils" code:-4
                                            userInfo:@{NSLocalizedDescriptionKey: @"all candidates failed"}]);
            return;
        }
        NSURL *url = candidates[idx];
        idx++;
        ame336_asyncGet(url, ^(NSDictionary *json, NSError *error) {
            if (json) {
                tryNext = nil; // 断自持环
                completion(json, nil);
            } else {
                tryNext(); // __block 变量运行期取值，递归安全
            }
        });
    };
    tryNext();
}

@implementation FabricUtils

+ (NSDictionary *)endpoints {
    return @{
        @"Fabric": @{
            @"game": @"https://meta.fabricmc.net/v2/versions/game",
            @"loader": @"https://meta.fabricmc.net/v2/versions/loader",
            @"icon": @"https://avatars.githubusercontent.com/u/21025855?s=64",
            @"json": @"https://meta.fabricmc.net/v2/versions/loader/%@/%@/profile/json"
        },
        // ★ Task335：Legacy Fabric（meta.legacyfabric.net v2，与 Fabric meta v2
        // 同构：game/loader 列表 + profile/json 端点；2026-10 实测 1.3–1.13 域内
        // 全链可用；ZL2 LegacyFabricVersions 同源）
        @"Legacy Fabric": @{
            @"game": @"https://meta.legacyfabric.net/v2/versions/game",
            @"loader": @"https://meta.legacyfabric.net/v2/versions/loader",
            @"icon": @"https://avatars.githubusercontent.com/u/21025855?s=64",
            @"json": @"https://meta.legacyfabric.net/v2/versions/loader/%@/%@/profile/json"
        },
        @"Quilt": @{
            @"game": @"https://meta.quiltmc.org/v3/versions/game",
            @"loader": @"https://meta.quiltmc.org/v3/versions/loader",
            @"icon": @"https://raw.githubusercontent.com/QuiltMC/art/master/brand/64png/quilt_logo_transparent.png",
            @"json": @"https://meta.quiltmc.org/v3/versions/loader/%@/%@/profile/json"
        }
    };
}

/// 统一经 PLMirrorCenter（ModLoader 类型）生成候选：
/// 候选顺序由 download.modLoaderSource 策略（official_first / mirror_first）决定，
/// Fabric meta → BMCLAPI /fabric-meta，Quilt meta → BMCLAPI /quilt-meta，
/// 调用方按顺序尝试，失败即换下一候选。
+ (NSArray<NSURL *> *)candidateURLsForVendor:(NSString *)vendor endpoint:(NSString *)endpoint {
    NSString *template = self.endpoints[vendor][endpoint];
    if (![template isKindOfClass:[NSString class]]) return @[];
    return [PLMirrorCenter candidateURLsForOriginalURL:[NSURL URLWithString:template]
                                          resourceType:PLMirrorResourceTypeModLoader];
}

/// profile json 端点格式化（游戏版本 + 加载器版本）后再生成候选，
/// maven 体系 URL → BMCLAPI /maven 映射
+ (NSArray<NSURL *> *)candidateURLsForVendor:(NSString *)vendor
                             minecraftVersion:(NSString *)minecraftVersion
                               loaderVersion:(NSString *)loaderVersion {
    NSString *template = self.endpoints[vendor][@"json"];
    if (![template isKindOfClass:[NSString class]]) return @[];
    NSURL *official = [NSURL URLWithString:[NSString stringWithFormat:template, minecraftVersion, loaderVersion]];
    return [PLMirrorCenter candidateURLsForOriginalURL:official
                                          resourceType:PLMirrorResourceTypeModLoader];
}

#pragma mark - Task336：Fabric-like 三厂直装执行器（新 UI Addons 页内联安装）

/// Task336 内部：三厂 API 的 Modrinth 工程与 loader 标签（与 legacy
/// FabricInstallViewController.installFabricAPIWithCompletion 同源；
/// legacy-fabric-api 真实 loader 标签为 "legacy-fabric"，"fabric" 恒空实测）
+ (void)ame336_modrinthProjectForVendor:(NSString *)vendor
                                project:(NSString **)projectOut
                              loaderTag:(NSString **)tagOut {
    if ([vendor isEqualToString:@"Legacy Fabric"]) {
        if (projectOut) *projectOut = @"legacy-fabric-api";
        if (tagOut) *tagOut = @"legacy-fabric";
    } else if ([vendor isEqualToString:@"Quilt"]) {
        if (projectOut) *projectOut = @"qsl";
        if (tagOut) *tagOut = @"quilt";
    } else {
        if (projectOut) *projectOut = @"fabric-api";
        if (tagOut) *tagOut = @"fabric";
    }
}

/// Task336 内部：下载 API jar 到实例 mods/（primary file 优先；
/// 经 PLMirrorCenter asset-search 镜像策略）
+ (void)ame336_installAPIForVendor:(NSString *)vendor
                       gameVersion:(NSString *)gameVersion
                          profileId:(NSString *)profileId
                        completion:(void (^)(BOOL success, NSError *error))completion {
    NSString *project = nil, *loaderTag = nil;
    [self ame336_modrinthProjectForVendor:vendor project:&project loaderTag:&loaderTag];

    NSString *originalAPIURL = [NSString stringWithFormat:
        @"https://api.modrinth.com/v2/project/%@/version?game_versions=[\"%@\"]&loaders=[\"%@\"]",
        project, gameVersion, loaderTag];
    NSString *apiUrl = [PLMirrorCenter preferredURLForOriginalURL:[NSURL URLWithString:originalAPIURL]
                                                   resourceType:PLMirrorResourceTypeAssetSearch].absoluteString ?: originalAPIURL;

    // 实例 mods 目录：Task322 混居 gameDir=versions/<profileId>（本执行器 saveProfile 口径）
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *baseDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    NSString *modsPath = [[baseDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@", profileId]] stringByAppendingPathComponent:@"mods"];
    [[NSFileManager defaultManager] createDirectoryAtPath:modsPath
                              withIntermediateDirectories:YES attributes:nil error:nil];

    ame336_asyncGet([NSURL URLWithString:apiUrl], ^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSArray class]]) {
            // API 拉取失败不阻断安装主体（legacy 安装器同纪律：非关键错误继续）
            completion(YES, nil);
            return;
        }
        NSArray *versions = (NSArray *)json;
        if (versions.count == 0) {
            completion(YES, nil); // 无可用 API 版本（同 legacy：非错误）
            return;
        }
        NSDictionary *latest = versions.firstObject;
        NSArray *files = latest[@"files"];
        NSDictionary *primaryFile = nil;
        for (NSDictionary *file in files) {
            if ([file[@"primary"] boolValue]) { primaryFile = file; break; }
        }
        if (!primaryFile) primaryFile = files.firstObject;
        NSString *downloadUrl = primaryFile[@"url"];
        NSString *fileName = primaryFile[@"filename"];
        if (![downloadUrl isKindOfClass:[NSString class]] || downloadUrl.length == 0
            || ![fileName isKindOfClass:[NSString class]] || fileName.length == 0) {
            completion(YES, nil);
            return;
        }
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
            downloadTaskWithURL:[NSURL URLWithString:downloadUrl]
              completionHandler:^(NSURL *location, NSURLResponse *resp, NSError *dlError) {
            if (dlError || !location) {
                completion(YES, nil); // API 下载失败继续（非关键）
                return;
            }
            NSString *destPath = [modsPath stringByAppendingPathComponent:fileName];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            NSError *moveError = nil;
            [[NSFileManager defaultManager] moveItemAtURL:location
                                                    toURL:[NSURL fileURLWithPath:destPath]
                                                    error:&moveError];
            NSLog(@"[FabricUtils] Task336 API installed: %@ -> %@", fileName, destPath);
            completion(YES, moveError);
        }];
        [task resume];
    });
}

+ (void)ame336_installFabricLikeVendor:(NSString *)vendor
                           gameVersion:(NSString *)gameVersion
                         loaderVersion:(NSString *)loaderVersion
                            installAPI:(BOOL)installAPI
                            completion:(void (^)(BOOL success, NSString *profileId, NSError *error))completion {
    // completion 统一主线程回调（内部链路 NSURLSession 回调在私有串行队列）
    void (^safeCompletion)(BOOL, NSString *, NSError *) = ^(BOOL s, NSString *pid, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(s, pid, e); });
    };
    NSArray<NSURL *> *candidates = [self candidateURLsForVendor:vendor
                                               minecraftVersion:gameVersion
                                                 loaderVersion:loaderVersion];
    ame336_fetchProfile(candidates, ^(NSDictionary *profileJson, NSError *fetchError) {
        if (!profileJson) {
            safeCompletion(NO, nil, fetchError);
            return;
        }
        NSString *profileId = [profileJson[@"id"] isKindOfClass:[NSString class]]
            ? profileJson[@"id"] : nil;
        if (profileId.length == 0) {
            safeCompletion(NO, nil, [NSError errorWithDomain:@"FabricUtils" code:-5
                                                   userInfo:@{NSLocalizedDescriptionKey: @"profile json missing id"}]);
            return;
        }

        // 版本 json 落盘（versions/<id>/<id>.json，legacy 安装器同口径）。
        // ★ Task337：POJAV_GAME_DIR 为空的兜底对表 ame336_installAPIForVendor
        // （旧写法 %s 直塞 getenv 结果，env 未设时路径变 "(null)/versions/…"）。
        const char *ame336_env = getenv("POJAV_GAME_DIR");
        NSString *ame336_gameDir = ame336_env ? [NSString stringWithUTF8String:ame336_env] : NSHomeDirectory();
        NSString *jsonPath = [ame336_gameDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"versions/%@/%@.json", profileId, profileId]];
        [[NSFileManager defaultManager] createDirectoryAtPath:jsonPath.stringByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *saveError = saveJSONToFile(profileJson, jsonPath);
        if (saveError) {
            safeCompletion(NO, nil, saveError);
            return;
        }

        // ★ Task337 线①闪退根修：profile 注册段整体主线程执行。
        //   旧写法在 NSURLSession 回调线程直接执行
        //   PLProfiles.current.selectedProfileName = profileId → 触发
        //   SelectedProfileChanged 同步通知 → 通知接收方
        //   ZL2VersionsViewController.profileListDidChange → reloadVersions →
        //   ame_rebuildList（AutoLayout）在后台线程执行 =
        //   NSInternalInconsistencyException（装机 1.8.9 Legacy Fabric 实锤
        //   latestlog 栈：CFNetwork → ame336_asyncGet → setSelectedProfileName
        //   → CFXNotificationPost → ame_rebuildList → CoreAutoLayout throw）。
        //   localVersionList 注册/saveProfile 一并主线程序列化（注册表是
        //   UI 读面，写方收口主队列；入队序在 safeCompletion 之前 → 完成
        //   回调必然晚于注册，时序安全）。
        dispatch_async(dispatch_get_main_queue(), ^{
            [localVersionList addObject:@{@"id": profileId, @"type": @"custom"}];

            // profile 注册（★ Task322 混居口径 gameDir=versions/<id>；旧表单
            // /game 分居层不再延续——Task322 已退役 game/ 层）
            NSMutableDictionary *profile = [NSMutableDictionary dictionary];
            profile[@"name"] = profileId;
            profile[@"lastVersionId"] = profileId;
            profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@", profileId];
            profile[@"type"] = @"custom";
            profile[@"created"] = [NSDate date].description;
            [PLProfiles.current saveProfile:profile withName:profileId];
            PLProfiles.current.selectedProfileName = profileId;
        });
        NSLog(@"[FabricUtils] Task336 fabric-like installed: %@ %@/%@ (api=%d)",
              vendor, gameVersion, loaderVersion, installAPI);

        if (!installAPI) {
            safeCompletion(YES, profileId, nil);
            return;
        }
        [self ame336_installAPIForVendor:vendor gameVersion:gameVersion profileId:profileId
                              completion:^(BOOL success, NSError *apiError) {
            safeCompletion(YES, profileId, apiError); // API 失败不翻转安装主体成败
        }];
    });
}

@end
