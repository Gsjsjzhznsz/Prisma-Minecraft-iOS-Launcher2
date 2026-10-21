//
// ZL2VersionIndex.m — 版本索引服务实现（7.0-UI-11）
//
// 逻辑来源：LauncherRootViewController initializeVersionLists / fetchRemoteVersionList
// （Task218 PLMirrorCenter 候选链）/ findVersionInRemoteList:（Task72 磁盘兜底）
// 三段 1:1 抽取，不引入新语义；唯一新增行为是"查找期在途等待"（见 .h 注）。
//
// 并发模型（设计定稿，两版演进）：
//   - _ame_lookupQueue 串行队列：查找请求与磁盘扫描在这里排队（避免重复扫描）；
//   - _ame_cond（NSCondition）：远程清单/标志位唯一锁——所有读写都在锁内，
//     完成回调（URLSession 队列）持锁落袋并 broadcast；等待方 waitUntilDate
//     期间释放锁，绝不占着串行队列睡眠（v1 在串行队列上 sleep 轮询会让
//     完成回调的置位块排队排在睡眠块后面 = 等待恒超时的自锁死，已废）；
//   - setPrefObject 保持主线程（旧 Task218 语义），不持 _ame_cond。
//
// 红线遵守：iOS 14.0 API（NSURLSession/NSJSONSerialization/NSCondition 基础
// 设施）；纯服务无 UI；通知只观察不发送；日志前缀 [ZL2VersionIndex] 可 grep。
//

#import "ZL2VersionIndex.h"
#import "PLMirrorCenter.h"
#import "LauncherPreferences.h"   // setPrefObject（internal.latest_version）

#pragma mark - 私有状态（除 _ame_lookupQueue 外全部由 _ame_cond 保护）

// 远程清单缓存（锁内读写；写点 = 种子重建 + manifest 落袋）
static NSMutableArray<NSDictionary *> *_ame_remoteList = nil;
// 清单是否已落定（成功失败都算"落定"，查找不再等待）
static BOOL _ame_remoteLoaded = NO;
// 在途拉取去重
static BOOL _ame_fetching = NO;
static NSCondition *_ame_cond = nil;
// 查找/扫描串行队列
static dispatch_queue_t _ame_lookupQueue = nil;
// 在途等待上限（秒）：清单网络候选链（官方 + 镜像）的保守预算
static const NSTimeInterval ZL2VersionIndexRemoteWaitBudget = 10.0;

NSString * const ZL2VersionIndexLogTag = @"[ZL2VersionIndex]";

@implementation ZL2VersionIndex

+ (instancetype)sharedIndex {
    static ZL2VersionIndex *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZL2VersionIndex alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        static dispatch_once_t onceSetup;
        dispatch_once(&onceSetup, ^{
            _ame_remoteList = [NSMutableArray new];
            _ame_cond = [NSCondition new];
            _ame_lookupQueue = dispatch_queue_create("ame.zl2.versionindex.lookup", DISPATCH_QUEUE_SERIAL);
        });
        // 启动链契约：查找请求（ZL2Home 启动按钮 → launchGame 发出）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame_onFindVersion:)
                                                     name:@"FindVersionInRemoteList"
                                                   object:nil];
        // 实例列表变动（下载完成落盘等）→ 远程清单重取（旧 reloadVersionLists
        // 的远程半边；本地半边本服务逐次即时扫描，无快照无过期）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame_onReloadProfiles)
                                                     name:@"ReloadProfileList"
                                                   object:nil];
        NSLog(@"%@ service online (FindVersionInRemoteList observer installed)", ZL2VersionIndexLogTag);
    }
    return self;
}

#pragma mark - 预热

- (void)warmUp {
    dispatch_async(_ame_lookupQueue, ^{
        [self ame_fetchRemoteListIfNeeded];
    });
}

#pragma mark - 通知入口

- (void)ame_onFindVersion:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *versionId = userInfo[@"versionId"];
    void (^callback)(NSDictionary *) = userInfo[@"callback"];

    if (!versionId || !callback) {
        NSLog(@"%@ find request missing versionId/callback -- ignored", ZL2VersionIndexLogTag);
        return;
    }

    void (^copiedCallback)(NSDictionary *) = [callback copy];
    NSString *wantedId = [versionId copy];

    dispatch_async(_ame_lookupQueue, ^{
        [self ame_lookup:wantedId callback:copiedCallback];
    });
}

- (void)ame_onReloadProfiles {
    dispatch_async(_ame_lookupQueue, ^{
        [_ame_cond lock];
        _ame_remoteLoaded = NO;
        [_ame_cond unlock];
        NSLog(@"%@ ReloadProfileList -- refreshing remote manifest", ZL2VersionIndexLogTag);
        [self ame_fetchRemoteListIfNeeded];
    });
}

#pragma mark - 三级查找（串行队列上下文）

- (void)ame_lookup:(NSString *)versionId callback:(void (^)(NSDictionary *))callback {
    NSDictionary *versionObject = nil;

    // ① 远程清单（已落定才查；未落定留给②③的已装路径与④的在途等待）
    [_ame_cond lock];
    BOOL ame_loaded = _ame_remoteLoaded;
    [_ame_cond unlock];
    if (ame_loaded) {
        versionObject = [self ame_matchInList:versionId];
        if (versionObject) {
            NSLog(@"%@ resolved '%@' from remote manifest", ZL2VersionIndexLogTag, versionId);
            [self ame_finish:versionObject callback:callback];
            return;
        }
    }

    // ② 本地 versions/ 目录即时扫描（无快照无过期；POJAV_GAME_DIR 优先、
    //    POJAV_HOME 兜底 = ZL2VersionsViewController 无效版本判定同口径）
    versionObject = [self ame_scanLocalVersionId:versionId];
    if (versionObject) {
        NSLog(@"%@ resolved '%@' from local versions scan", ZL2VersionIndexLogTag, versionId);
        [self ame_finish:versionObject callback:callback];
        return;
    }

    // ③ <id>.json 直查磁盘兜底（Task72 语义：本地扫描口径之外仍以文件
    //    存在性为准，与既有本地版本启动路径完全一致）
    if ([self ame_versionJsonOnDisk:versionId]) {
        NSLog(@"%@ resolved '%@' via Task72 disk fallback", ZL2VersionIndexLogTag, versionId);
        [self ame_finish:@{@"id": versionId, @"type": @"custom"} callback:callback];
        return;
    }

    // ④ 未命中且清单未落定 → 在途等待（消除"秒点启动 + 未安装版本 +
    //    清单未落袋"竞态），落定后按①重查
    if (!ame_loaded && [self ame_waitForRemoteList]) {
        versionObject = [self ame_matchInList:versionId];
        if (versionObject) {
            NSLog(@"%@ resolved '%@' from remote manifest (after in-flight wait)", ZL2VersionIndexLogTag, versionId);
            [self ame_finish:versionObject callback:callback];
            return;
        }
    }

    // ⑤ 全空 → 判死（ZL2Home 弹"找不到版本信息"并恢复交互，旧语义）
    NSLog(@"%@ unresolved '%@' (loaded=%d localScan=0 disk=0)", ZL2VersionIndexLogTag, versionId, ame_loaded);
    [self ame_finish:nil callback:callback];
}

- (void)ame_finish:(NSDictionary *)versionObject callback:(void (^)(NSDictionary *))callback {
    // callback 一律回主线程（ZL2Home 回调体操作 UI 域状态；旧壳通知回调
    // 本就在主线程，语义保持）
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(versionObject);
    });
}

// 锁内清单匹配（锁内迭代杜绝并发落袋期间的枚举变异）
- (NSDictionary *)ame_matchInList:(NSString *)versionId {
    [_ame_cond lock];
    @try {
        for (NSDictionary *version in _ame_remoteList) {
            if ([version[@"id"] isEqualToString:versionId]) {
                return version;
            }
        }
    } @finally {
        [_ame_cond unlock];
    }
    return nil;
}

- (NSDictionary *)ame_scanLocalVersionId:(NSString *)versionId {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // POJAV_GAME_DIR 优先、POJAV_HOME 兜底（ZL2VersionsViewController
    // ame256 无效版本判定同款双目录口径）
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (gameDir) [roots addObject:[NSString stringWithFormat:@"%s", gameDir]];
    const char *homeDir = getenv("POJAV_HOME");
    if (homeDir) [roots addObject:[NSString stringWithFormat:@"%s", homeDir]];

    for (NSString *root in roots) {
        NSString *versionPath = [root stringByAppendingPathComponent:@"versions"];
        NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:nil];
        for (NSString *candidate in list) {
            if (![candidate isEqualToString:versionId]) continue;
            NSString *localPath = [versionPath stringByAppendingPathComponent:candidate];
            BOOL isDirectory = NO;
            if ([fileManager fileExistsAtPath:localPath isDirectory:&isDirectory] && isDirectory) {
                return @{@"id": versionId, @"type": @"custom"};
            }
        }
    }
    return nil;
}

- (BOOL)ame_versionJsonOnDisk:(NSString *)versionId {
    if (versionId.length == 0) return NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (!gameDir) return NO;
    NSString *versionJsonPath = [NSString stringWithFormat:@"%s/versions/%@/%@.json",
                                 gameDir, versionId, versionId];
    BOOL isDir = NO;
    return [fileManager fileExistsAtPath:versionJsonPath isDirectory:&isDir] && !isDir;
}

// 限时等待清单落定（NSCondition.waitUntilDate 期间释放锁；绝不占串行
// 队列睡眠——完成回调的置位块要能进得来，v1 自锁死教训见文件头）
- (BOOL)ame_waitForRemoteList {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:ZL2VersionIndexRemoteWaitBudget];
    [_ame_cond lock];
    @try {
        if (!_ame_fetching) {
            // 拉取未在途：先发起（startFetch 调用方已持锁的变体走不走都行，
            // 这里统一放锁外重入——fetch 内部自己加锁）
            [_ame_cond unlock];
            [self ame_fetchRemoteListIfNeeded];
            [_ame_cond lock];
        }
        while (!_ame_remoteLoaded) {
            NSTimeInterval remaining = [deadline timeIntervalSinceNow];
            if (remaining <= 0) break;
            [_ame_cond waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:remaining]];
        }
        return _ame_remoteLoaded;
    } @finally {
        [_ame_cond unlock];
    }
}

#pragma mark - 远程清单拉取（Task218 候选链 1:1）

- (void)ame_fetchRemoteListIfNeeded {
    [_ame_cond lock];
    @try {
        if (_ame_remoteLoaded || _ame_fetching) return;
        _ame_fetching = YES;

        // 种子条目（旧 initializeVersionLists 同款；真清单回来后追加）
        [_ame_remoteList removeAllObjects];
        [_ame_remoteList addObjectsFromArray:@[
            @{@"id": @"latest-release", @"type": @"release"},
            @{@"id": @"latest-snapshot", @"type": @"snapshot"}
        ]];
        // 注：latest-* 非可下载实体（downloadVersion 需真 URL），仅保留旧
        // 列表展示语义；查找路径不会因种子误报命中（种子 id 不在实例里）。
    } @finally {
        [_ame_cond unlock];
    }
    [self ame_startFetchCandidates];
}

// 网络候选链（锁外执行；落袋/落定段持锁 + broadcast 唤醒等待方）
- (void)ame_startFetchCandidates {
    NSURL *official = [NSURL URLWithString:@"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"];
    NSArray<NSURL *> *candidates = [PLMirrorCenter candidateURLsForOriginalURL:official
                                                                  resourceType:PLMirrorResourceTypeGameFile];
    if (candidates.count == 0) {
        candidates = @[official];
    }
    __block NSMutableArray<NSURL *> *remaining = [candidates mutableCopy];
    __block void (^tryNext)(void) = ^{ };
    tryNext = ^{
        if (remaining.count == 0) {
            [_ame_cond lock];
            _ame_fetching = NO;
            _ame_remoteLoaded = YES;   // 失败也"落定"：等待方立即醒来走判死
            [_ame_cond broadcast];
            [_ame_cond unlock];
            NSLog(@"%@ version manifest: all %lu candidates failed", ZL2VersionIndexLogTag,
                  (unsigned long)candidates.count);
            return;
        }
        NSURL *url = remaining.firstObject;
        [remaining removeObjectAtIndex:0];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error) {
                NSError *jsonError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (json && json[@"versions"]) {
                    // Task218 语义：latest 写偏好（主线程）；清单本体持锁落袋
                    setPrefObject(@"internal.latest_version", json[@"latest"]);
                    NSArray<NSDictionary *> *versions = json[@"versions"];
                    [_ame_cond lock];
                    [_ame_remoteList addObjectsFromArray:versions];
                    _ame_fetching = NO;
                    _ame_remoteLoaded = YES;
                    NSLog(@"%@ loaded %lu remote versions from %@",
                          ZL2VersionIndexLogTag, (unsigned long)_ame_remoteList.count, url.host);
                    [_ame_cond signal];
                    [_ame_cond broadcast];
                    [_ame_cond unlock];
                    return;
                }
            }
            NSLog(@"%@ manifest fetch failed on %@ (%@) -- trying next candidate",
                  ZL2VersionIndexLogTag, url.host, error.localizedDescription ?: @"non-JSON");
            tryNext();
        }];
        [task resume];
    };
    tryNext();
}

@end
