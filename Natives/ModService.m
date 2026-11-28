#import "utils.h"
#import "ZL2GamePath.h" // ★Task473: ZL2 版本隔离系统单入口
//
//  ModService.m
//  AmethystMods
//
//  修改：增加文件修改时间缓存，大幅提升扫描速度
//  修改：文件下载改走 PLDownloadClient 统一下载器（镜像候选 + SHA1 校验 + 断点续传），
//        移除自建 NSURLSession 下载 delegate（spec optimize-download-system Task 4.2 / 5.1 / 5.2）
//

#import "ModService.h"
// ★ Task274-h S14：CommonCrypto import 随零调用 sha1ForFileAtPath 删除（全文件 CC_ 族
//   仅该方法使用，rg 亲证）
#import <UIKit/UIKit.h>
#import "PLProfiles.h"
#import "ModpackImportService.h"  // Task275 F6: ame269_isImportBusy 让路守卫
#import "UnzipKit.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "LauncherPreferences.h"
#import "PLDownloadClient.h"
#import "PLMirrorCenter.h"

@interface ModService ()
// ---- PLDownloadClient 下载跟踪（key = DownloadTaskItem.taskId，即 PLDownloadRequest.taskIdentifier）----
@property (nonatomic, strong) NSLock *downloadStateLock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DownloadTaskItem *> *downloadTaskItems;
// 强持有当前 operation：pause 后 PLDownloadClient 会移除内部 task 映射，
// 需由 Service 保活，DownloadTaskManager 的 rawTask（weak）才能继续 pause/resume
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadOperation *> *downloadOperations;
// 重试代数：retryHandler 重建请求后旧 operation 的迟到回调（如取消）按此丢弃
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadGenerations;
// 进度累计（PLDownloadClient 为 delta 语义，含镜像切换/重试的负 delta 回退，直接累加即可）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadAccumulatedBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadTotalBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *downloadLastSpeeds;
// 请求描述缓存：retryHandler 复用同一请求（同 taskIdentifier 可复用断点语义）
@property (nonatomic, strong) NSMutableDictionary<NSString *, PLDownloadRequest *> *downloadRequests;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void(^)(NSProgress *)> *downloadProgressHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModDownloadHandler> *downloadCompletionHandlers;

// 缓存
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModItem *> *metadataCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *checkpointTimes;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;


@end

@implementation ModService

#pragma mark - ★Task473: ZL2 版本隔离系统单入口路由（上游 Version.getGameDir 同构；Task472 共享根收口点原位继承）
- (nullable NSString *)resolveAbsoluteGameDirForProfile:(NSString *)profileName {
    // ★Task473: 全部 mods 落点经 ZL2GamePath 单入口（版本级隔离开 → versions/<vid>/；
    //   否则实例自定义路径 / 主游戏根）——与启动 chdir 同源。
    return [ZL2GamePath gameDirForProfile:profileName];
}

// ---------- TOML 解析（未修改）----------
- (nullable id)parseTomlValue:(NSString *)valPart inLines:(NSArray<NSString *> *)lines atIndex:(NSUInteger *)i {
    NSString *trimmedVal = [valPart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *delimiter = nil;
    if ([trimmedVal hasPrefix:@"'''"]) delimiter = @"'''";
    else if ([trimmedVal hasPrefix:@"\"\"\""]) delimiter = @"\"\"\"";

    if (delimiter) {
        NSMutableString *multiLineContent = [[trimmedVal substringFromIndex:3] mutableCopy];
        if ([multiLineContent hasSuffix:delimiter]) {
            return [multiLineContent substringToIndex:multiLineContent.length - 3];
        } else {
            NSMutableArray<NSString *> *contentLines = [NSMutableArray array];
            [contentLines addObject:multiLineContent];
            (*i)++;
            while (*i < lines.count) {
                NSString *nextLine = lines[*i];
                NSRange endDelimiterRange = [nextLine rangeOfString:delimiter];
                if (endDelimiterRange.location != NSNotFound) {
                    [contentLines addObject:[nextLine substringToIndex:endDelimiterRange.location]];
                    break;
                } else {
                    [contentLines addObject:nextLine];
                }
                (*i)++;
            }
            return [contentLines componentsJoinedByString:@"\n"];
        }
    }

    if (([trimmedVal hasPrefix:@"\""] && [trimmedVal hasSuffix:@"\""]) ||
        ([trimmedVal hasPrefix:@"'"] && [trimmedVal hasSuffix:@"'"])) {
        if (trimmedVal.length > 1) {
            return [trimmedVal substringWithRange:NSMakeRange(1, trimmedVal.length - 2)];
        }
        return @"";
    }
    return trimmedVal;
}

- (NSDictionary<NSString *, id> *)parseTomlString:(NSString *)s {
    if (!s) return nil;
    NSMutableDictionary<NSString *, id> *root = [NSMutableDictionary dictionary];
    NSMutableDictionary *currentTable = root;
    NSString *currentTableName = nil;
    NSArray<NSString *> *lines = [s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"#"] || trimmed.length == 0) continue;

        if ([trimmed hasPrefix:@"[["] && [trimmed hasSuffix:@"]]"]) {
            currentTableName = [trimmed substringWithRange:NSMakeRange(2, trimmed.length - 4)];
            NSMutableArray *array = root[currentTableName] ?: [NSMutableArray array];
            root[currentTableName] = array;
            currentTable = [NSMutableDictionary dictionary];
            [array addObject:currentTable];
            continue;
        } else if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            currentTableName = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
            currentTable = [NSMutableDictionary dictionary];
            root[currentTableName] = currentTable;
            continue;
        }

        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location != NSNotFound) {
            NSString *key = [[trimmed substringToIndex:eqRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *valPart = [trimmed substringFromIndex:NSMaxRange(eqRange)];
            id value = [self parseTomlValue:valPart inLines:lines atIndex:&i];
            if (value) {
                currentTable[key] = value;
            }
        }
    }
    return root;
}

// ---------- 初始化 ----------
+ (instancetype)sharedService {
    static ModService *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[ModService alloc] init];
    });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _onlineSearchEnabled = NO;

        // 下载已改走 [PLDownloadClient sharedClient]（镜像候选 + SHA1 校验 + 断点续传），
        // 不再自建 NSURLSession download delegate
        _downloadStateLock = [[NSLock alloc] init];
        _downloadTaskItems = [NSMutableDictionary dictionary];
        _downloadOperations = [NSMutableDictionary dictionary];
        _downloadGenerations = [NSMutableDictionary dictionary];
        _downloadAccumulatedBytes = [NSMutableDictionary dictionary];
        _downloadTotalBytes = [NSMutableDictionary dictionary];
        _downloadLastSpeeds = [NSMutableDictionary dictionary];
        _downloadRequests = [NSMutableDictionary dictionary];
        _downloadProgressHandlers = [NSMutableDictionary dictionary];
        _downloadCompletionHandlers = [NSMutableDictionary dictionary];

        // 初始化缓存
        _metadataCache = [NSMutableDictionary dictionary];
        _checkpointTimes = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.amethyst.modcache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

// ---------- 辅助方法 ----------
// ★ Task274-h S14：sha1ForFileAtPath 零调用副本已删除（rg 亲证全文件仅此 1 处定义
//   零调用；活副本在 ModpackExportService:939 有分块实现）。
// ★ Task270（屎山 A1）：逐字节克隆收敛 utils.m 单点 AMEIconCachePathForURL（行为零变更）。
- (NSString *)iconCachePathForURL:(NSString *)urlString {
    return AMEIconCachePathForURL(urlString, @"mod_icons");
}

- (nullable NSData *)readFileFromJar:(NSString *)jarPath entryName:(NSString *)entryName {
    if (!jarPath || !entryName) return nil;
    NSError *err = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jarPath error:&err];
    if (!archive || err) return nil;
    NSData *data = [archive extractDataFromFile:entryName error:&err];
    return data;
}

/// ★ Task327：实例 versions/ 真实文件物化（FCL 观感终态，替代 Task326 符号链接）。
///   病历（Task326 自留 + 装机 c7c3f81 两轮复访"依旧空目录"）：Task326 用
///   【绝对路径符号链接】把实例 versions/ 指向共享 versions —— 进程内自洽
///   （FolderBrowser/MC 解析正常），但 iOS 文件 App（FileProvider）不跟随
///   符号链接，且 LiveContainer 映射树下的绝对链接在进程外视图里必然断链
///   = 用户在文件 App 里看到的 instances/<id>/versions/ 永远是空目录。
///   修法 = 真实文件落盘：共享 versions/<vid>/ 的 <vid>.json 与 <vid>.jar
///   逐版本物化进实例 versions/<vid>/。优先硬链接（同容器同卷零拷贝零
///   额外空间，文件 App 呈现为普通文件），失败回退整拷贝（json KB 级、
///   jar 至多 ~25MB，实例数有限可接受）。纪律：
///   · 只增不删：实例侧已存在同名文件（真实用户数据）绝不触碰；
///   · 共享 versions 仍是唯一事实源（Java 侧 Tools.java DIR_HOME_VERSION
///     读共享目录，实例侧文件是 FCL 观感层，不参与启动解析）；
///   · 旧 Task326 符号链接（本工具前代自产物）就地摘除换实体目录；
///   · 自指守卫：gameDir 解析后与 POJAV_GAME_DIR 同址（default 实例=
///     共享根本体）绝不物化（防 versions→自身 环）；
///   · 共享 versions 缺失先建（标准层目录，恒安全）；
///   · 非版本实例（无 <vid>.json 标记）跳过（残根/杂项不入）。
+ (void)ame327_materializeInstanceVersions:(NSString *)gameDirAbsolute
                                        fm:(NSFileManager *)fm {
    const char *ame327_env = getenv("POJAV_GAME_DIR");
    if (!ame327_env || !*ame327_env) return;
    // ★ Task329/483：版本轴形态守卫 —— gameDir 已是版本隔离目录（<root>/
    // versions/<vid>，Task473 隔离与 ame329 统一后的形态）时绝不再物化：
    // 否则会在版本目录里再套一层 versions/<vid>/<vid>.json 嵌套垃圾。
    // ★Task483：旧 instances/<id>/ 前缀判据随 instances 布局退役，改为
    // 通用形态判据——gameDir 路径中出现 "versions" 组件即视为版本轴形态
    // （与共享根形态互斥；lasm/versions 纯目录同样命中跳过）。
    NSArray<NSString *> *ame327_comps = [gameDirAbsolute stringByStandardizingPath]
        .pathComponents;
    NSUInteger ame327_vIdx = [ame327_comps indexOfObject:@"versions"];
    if (ame327_vIdx != NSNotFound && ame327_vIdx > 0) {
        return;
    }
    NSString *sharedVersions = [[NSString stringWithUTF8String:ame327_env]
                                stringByAppendingPathComponent:@"versions"];
    NSString *resolvedGame = [gameDirAbsolute stringByResolvingSymlinksInPath];
    NSString *resolvedSharedRoot = [[sharedVersions stringByDeletingLastPathComponent]
                                    stringByResolvingSymlinksInPath];
    if ([resolvedGame isEqualToString:resolvedSharedRoot]) return;   // 自指守卫
    NSString *shell = [gameDirAbsolute stringByAppendingPathComponent:@"versions"];
    // 共享 versions 缺失先建（标准层目录，恒安全）
    BOOL ame327_sharedIsDir = NO;
    if (![fm fileExistsAtPath:sharedVersions isDirectory:&ame327_sharedIsDir]) {
        [fm createDirectoryAtPath:sharedVersions
          withIntermediateDirectories:YES attributes:nil error:nil];
    }
    // 旧符号链接（Task326 自产物）→ 摘除换实体目录；真实目录保留（只增不删）
    NSDictionary *ame327_attrs = [fm attributesOfItemAtPath:shell error:nil];
    if (ame327_attrs) {
        NSString *ame327_type = [ame327_attrs objectForKey:NSFileType];
        if ([ame327_type isEqualToString:NSFileTypeSymbolicLink]) {
            if ([fm removeItemAtPath:shell error:nil]) {
                NSLog(@"[Ame327] instance versions legacy symlink removed (materialize takes over): %@/versions",
                      shell.lastPathComponent);
            }
        } else if (![ame327_type isEqualToString:NSFileTypeDirectory]) {
            return;   // 异常形态（普通文件等）不碰
        }
    }
    if (![fm createDirectoryAtPath:shell withIntermediateDirectories:YES attributes:nil error:nil]) return;
    // 逐版本物化（json + jar；loader 档无 jar 属正常跳过）
    NSArray<NSString *> *ame327_vids = [fm contentsOfDirectoryAtPath:sharedVersions error:nil];
    NSInteger ame327_made = 0;
    for (NSString *ame327_vid in ame327_vids) {
        if ([ame327_vid hasPrefix:@"."]) continue;
        NSString *ame327_srcDir = [sharedVersions stringByAppendingPathComponent:ame327_vid];
        NSString *ame327_srcJson = [ame327_srcDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", ame327_vid]];
        if (![fm fileExistsAtPath:ame327_srcJson]) continue;   // 非版本实例
        NSString *ame327_dstDir = [shell stringByAppendingPathComponent:ame327_vid];
        if (![fm fileExistsAtPath:ame327_dstDir]) {
            if (![fm createDirectoryAtPath:ame327_dstDir
               withIntermediateDirectories:YES attributes:nil error:nil]) continue;
        }
        NSArray<NSString *> *ame327_files = @[
            [NSString stringWithFormat:@"%@.json", ame327_vid],
            [NSString stringWithFormat:@"%@.jar", ame327_vid],
        ];
        for (NSString *ame327_fname in ame327_files) {
            NSString *ame327_src = [ame327_srcDir stringByAppendingPathComponent:ame327_fname];
            if (![fm fileExistsAtPath:ame327_src]) continue;   // jar 缺席正常
            NSString *ame327_dst = [ame327_dstDir stringByAppendingPathComponent:ame327_fname];
            if ([fm fileExistsAtPath:ame327_dst]) continue;   // 只增不删
            // 优先硬链接（同容器同卷：零拷贝零空间，文件 App 呈现为普通文件）
            BOOL ame327_ok = [fm linkItemAtPath:ame327_src toPath:ame327_dst error:nil];
            if (!ame327_ok) {
                NSError *ame327_cpErr = nil;
                ame327_ok = [fm copyItemAtPath:ame327_src toPath:ame327_dst error:&ame327_cpErr];
                if (!ame327_ok) {
                    NSLog(@"[Ame327] materialize %@/%@ failed: %@",
                          ame327_vid, ame327_fname,
                          ame327_cpErr.localizedDescription ?: @"unknown");
                    continue;
                }
            }
            ame327_made++;
        }
    }
    if (ame327_made > 0) {
        NSLog(@"[Ame327] instance versions materialized: %@/versions (%ld file(s), hardlink-first, FCL visibility)",
              gameDirAbsolute.lastPathComponent, (long)ame327_made);
    }
}

/// ★ Task328：诱饵版本骨架清扫（"versions 空目录"第四轮复访根因收口；用户
///   装机 777e82c 截图实锤：versions/<vid>/ 内 mods/saves/config/resourcepacks/
///   shaderpacks/screenshots 六目录全部"0项"）。来源链 = Task271 默认隔离
///   清扫给安装期自动建档的 profile 写入 gameDir=versions/<vid>（Task324
///   判据①命中）→ 骨架建立 → 该版本随后被整合包实例（gameDir = 绝对路径
///   instances/<id>，Task325 实例轴）接管启动 → 版本目录骨架成了永不生效
///   的诱饵：用户在文件 App 打开版本目录只见一堆空文件夹（真实数据在实例
///   目录），观感 = "versions 空目录"。
///   口径：六目录【全部存在且全部为空】（非隐藏项计空）才构成诱饵形态，
///   且无任何【仍然生效】的版本轴 claim——claim 判据 = 存在 gameDir 为
///   versions/<vid>/（或旧 game 叶子）的 profile，且同 lastVersionId 下
///   【无】绝对路径 gameDir 的 profile（实例轴/自定义目录接管 = 版本轴
///   claim 失效，ghost 档不保骨架）。任一目录有真实内容 = 事实上隔离
///   （Task324 判据②），整组绝不触碰。空目录零数据语义可无损再生：日后
///   用户显式启用该版本隔离，ame324 骨架链一启动即重建。幂等零副作用。
+ (void)ame328_pruneDecoyVersionSkeletons {
    const char *ame328_env = getenv("POJAV_GAME_DIR");
    if (!ame328_env || !*ame328_env) return;
    NSString *ame328_base = [NSString stringWithUTF8String:ame328_env];
    if (ame328_base.length == 0) return;
    NSFileManager *ame328_fm = [NSFileManager defaultManager];
    NSString *ame328_versions = [ame328_base stringByAppendingPathComponent:@"versions"];
    NSArray<NSString *> *ame328_vdirs = [ame328_fm contentsOfDirectoryAtPath:ame328_versions error:nil];
    NSInteger ame328_pruned = 0;
    for (NSString *ame328_vd in ame328_vdirs) {
        if ([ame328_vd hasPrefix:@"."]) continue;
        NSString *ame328_vdir = [ame328_versions stringByAppendingPathComponent:ame328_vd];
        BOOL ame328_isDir = NO;
        if (![ame328_fm fileExistsAtPath:ame328_vdir isDirectory:&ame328_isDir] || !ame328_isDir) continue;
        // 诱饵形态①：六目录全部存在且全部为空（任一缺失 = 非骨架形态不碰；
        // 任一有内容 = 事实上隔离，绝不触碰）
        NSArray<NSString *> *ame328_six = @[@"mods", @"saves", @"config", @"resourcepacks", @"shaderpacks", @"screenshots"];
        BOOL ame328_allEmpty = YES;
        NSMutableArray<NSString *> *ame328_empty = [NSMutableArray array];
        for (NSString *ame328_leaf in ame328_six) {
            NSString *ame328_p = [ame328_vdir stringByAppendingPathComponent:ame328_leaf];
            BOOL ame328_leafDir = NO;
            if (![ame328_fm fileExistsAtPath:ame328_p isDirectory:&ame328_leafDir] || !ame328_leafDir) {
                ame328_allEmpty = NO;
                break;
            }
            NSArray<NSString *> *ame328_entries = [ame328_fm contentsOfDirectoryAtPath:ame328_p error:nil];
            for (NSString *ame328_e in ame328_entries) {
                if (![ame328_e hasPrefix:@"."]) { ame328_allEmpty = NO; break; }
            }
            if (!ame328_allEmpty) break;
            [ame328_empty addObject:ame328_p];
        }
        if (!ame328_allEmpty || ame328_empty.count != ame328_six.count) continue;
        // 诱饵形态②：无仍然生效的版本轴 claim（实例轴/自定义目录接管或
        // ghost 档 = 摘除；显式隔离用户 = 保留）
        BOOL ame328_claimed = NO;
        BOOL ame328_instanceBound = NO;
        NSString *ame328_flat = [NSString stringWithFormat:@"versions/%@", ame328_vd];
        NSString *ame328_leafOld = [NSString stringWithFormat:@"versions/%@/game", ame328_vd];
        for (NSDictionary *ame328_prof in PLProfiles.current.profiles.allValues) {
            if (![ame328_prof isKindOfClass:[NSDictionary class]]) continue;
            NSString *ame328_lvi = ame328_prof[@"lastVersionId"];
            if (![ame328_lvi isKindOfClass:[NSString class]] || ![ame328_lvi isEqualToString:ame328_vd]) continue;
            NSString *ame328_gd = ame328_prof[@"gameDir"];
            if (![ame328_gd isKindOfClass:[NSString class]] || ame328_gd.length == 0) continue;
            if (ame328_gd.isAbsolutePath) {
                ame328_instanceBound = YES;   // 实例轴/自定义目录接管
            } else if ([ame328_gd isEqualToString:ame328_flat] ||
                       [ame328_gd isEqualToString:ame328_leafOld]) {
                ame328_claimed = YES;         // 版本轴显式/清扫建档 claim
            }
        }
        if (ame328_claimed && !ame328_instanceBound) continue;
        for (NSString *ame328_p in ame328_empty) {
            if ([ame328_fm removeItemAtPath:ame328_p error:nil]) ame328_pruned++;
        }
        NSLog(@"[Ame328] decoy skeleton pruned: versions/%@ (6 empty dir(s), instance-bound/orphaned, regenerable on demand)",
              ame328_vd);
    }
    if (ame328_pruned > 0) {
        NSLog(@"[Ame328] decoy skeleton prune done: %ld dir(s) removed -- instance-bound version dirs show json+jar only (FCL parity)",
              (long)ame328_pruned);
    }
}

/// ★ Task329：递归并入助手 —— 把 src 搬进 dstDir（同名目录递归并入子项，
/// 同名文件冲突来件改名 <name>.ame329-<ts> 并置，绝不覆盖任何一方数据；
/// 目录搬空后摘壳）。movedOut 累计实际搬移条目数（含递归子项）。
static BOOL ame329_moveEntry(NSFileManager *fm, NSString *src, NSString *dstDir,
                             NSString *ts, NSInteger *movedOut) {
    NSString *name = src.lastPathComponent;
    NSString *dst = [dstDir stringByAppendingPathComponent:name];
    BOOL dstExists = NO, dstIsDir = NO, srcIsDir = NO;
    dstExists = [fm fileExistsAtPath:dst isDirectory:&dstIsDir];
    [fm fileExistsAtPath:src isDirectory:&srcIsDir];
    if (!dstExists) {
        if ([fm moveItemAtPath:src toPath:dst error:nil]) { (*movedOut)++; return YES; }
        return NO;
    }
    if (dstIsDir && srcIsDir) {
        BOOL allOK = YES;
        NSArray *children = [fm contentsOfDirectoryAtPath:src error:nil] ?: @[];
        for (NSString *child in children) {
            BOOL ok = ame329_moveEntry(fm, [src stringByAppendingPathComponent:child], dst, ts, movedOut);
            allOK = allOK && ok;
        }
        NSArray *left = [fm contentsOfDirectoryAtPath:src error:nil] ?: @[];
        if (left.count == 0) [fm removeItemAtPath:src error:nil];   // 搬空摘壳，零数据
        return allOK;
    }
    NSString *conflict = [dstDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.ame329-%@", name, ts]];
    BOOL ok = [fm moveItemAtPath:src toPath:conflict error:nil];
    if (ok) (*movedOut)++;
    return ok;
}

/// ★ Task329：版本轴统一 pass —— 整合包实例数据搬家进版本目录（真·ZL2 风格）。
/// 病历（用户五轮复访"versions 空目录"）：整合包导入走实例轴（profile
/// gameDir = 绝对 instances/<id>，Task275 F5 直通），游戏数据（saves/mods/
/// config/options.txt 等）全在实例根；versions/<vid>/ 内只有导入链创建的
/// jar/json + Task271/324 六目录骨架。用户顺 .minecraft/versions/<vid>/
/// 找数据只见空目录 —— Task326 链接 / Task327 物化 / Task328 清扫三轮都在
/// 治"观感"，数据始终不在"家"。本 pass 把实例根的游戏数据整体搬进
/// instances/<id>/versions/<vid>/（导入链已建好的版本目录），并把 profile
/// gameDir 重指到同一位置 —— 版本目录自此 = 完整隔离数据目录（PCL2/ZL2
/// 版本隔离形态），Files App 顺 .minecraft/versions/<vid>/ 直达全部数据。
/// 口径：
///   · 只认实例根形态（instances/<id> 恰两层）；已迁移形态 instances/<id>/
///     versions/<vid> 与任意自定义绝对目录被层数判据天然排除（幂等）；
///   · 搬家清单 = 版本目录内非隐藏、非共享层（versions/assets/libraries）、
///     非导入元数据（import_report.json/.ame269_backup/旧 custom_gamedir）
///     的全部根级条目（Task226 迁移清单同源口径的超集，leftovers 全带走）；
///   · 冲突绝不覆盖（见 ame329_moveEntry）；空壳/搬空目录摘除零数据；
///   · gameDir 重指条件 = 实际搬移 ≥1 项，或根已无候选但版本目录有内容
///     （上次搬移后重指失败的残留修复）；applyChanges 锁内落盘；
///   · 版本目录真身判据 = instances/<id>/versions/<vid>/<vid>.json 存在
///     （ame324 marker 同口径），json 不在 = 无主实例绝不盲搬。
+ (void)ame329_unifyInstanceDataIntoVersionAxis {
    const char *ame329_homeC = getenv("POJAV_HOME");
    if (!ame329_homeC || !*ame329_homeC) return;
    NSString *ame329_home = [NSString stringWithUTF8String:ame329_homeC];
    if (ame329_home.length == 0) return;
    NSFileManager *ame329_fm = [NSFileManager defaultManager];
    NSString *ame329_rootStd = [[ame329_home stringByAppendingPathComponent:@"instances"]
        stringByStandardizingPath];
    NSString *ame329_rootPrefix = [ame329_rootStd stringByAppendingString:@"/"];
    // 共享层 + 导入元数据 + 旧嵌套布局（Task316 ame316 迁移域）绝不触碰
    // ★ Task330：launcher_preferences.plist 强制豁免 —— PLPreferences 的
    //   instancePath 恒等 POJAV_GAME_DIR/launcher_preferences.plist
    //   （LauncherPreferences 每次访问从 env 重算），env 恒指实例根、不随
    //   版本轴重指变化 → plist 属【启动器层】非游戏数据层，搬走 = 下次
    //   启动偏好整表丢失（Task329 潜在缺陷顺修）。
    NSSet *ame329_excluded = [NSSet setWithArray:@[
        @"versions", @"assets", @"libraries",
        @"import_report.json", @".ame269_backup", @"custom_gamedir",
        @"launcher_preferences.plist"
    ]];
    NSString *ame329_ts = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSDictionary *ame329_profiles = PLProfiles.current.profiles;
    NSInteger ame329_unified = 0;
    for (NSString *ame329_name in ame329_profiles.allKeys) {
        NSDictionary *ame329_prof = ame329_profiles[ame329_name];
        if (![ame329_prof isKindOfClass:[NSDictionary class]]) continue;
        NSString *ame329_gd = ame329_prof[@"gameDir"];
        if (![ame329_gd isKindOfClass:[NSString class]] || ![ame329_gd isAbsolutePath]) continue;
        NSString *ame329_gdStd = [ame329_gd stringByStandardizingPath];
        // 判据①：恰为 instances/<id> 两层实例根
        if (![ame329_gdStd hasPrefix:ame329_rootPrefix]) continue;
        NSString *ame329_rest = [ame329_gdStd substringFromIndex:ame329_rootPrefix.length];
        if (ame329_rest.length == 0 || [ame329_rest rangeOfString:@"/"].location != NSNotFound) continue;
        // 判据②：实例根是真实目录（非符号链接；链接形态交给 ame325 旧链）
        NSDictionary *ame329_attrs = [ame329_fm attributesOfItemAtPath:ame329_gdStd error:nil];
        if (!ame329_attrs || [ame329_attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;
        BOOL ame329_isDir = NO;
        if (![ame329_fm fileExistsAtPath:ame329_gdStd isDirectory:&ame329_isDir] || !ame329_isDir) continue;
        // 判据③：lastVersionId 的版本目录真身存在（无主实例绝不盲搬）
        NSString *ame329_vid = ame329_prof[@"lastVersionId"];
        if (![ame329_vid isKindOfClass:[NSString class]] || ame329_vid.length == 0) continue;
        NSString *ame329_vdir = [ame329_gdStd stringByAppendingPathComponent:
            [NSString stringWithFormat:@"versions/%@", ame329_vid]];
        NSString *ame329_marker = [ame329_vdir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", ame329_vid]];
        if (![ame329_fm fileExistsAtPath:ame329_marker]) continue;
        // 候选搬家清单：根级非隐藏、非排除条目
        NSMutableArray<NSString *> *ame329_pending = [NSMutableArray array];
        for (NSString *ame329_item in [ame329_fm contentsOfDirectoryAtPath:ame329_gdStd error:nil]) {
            if ([ame329_item hasPrefix:@"."]) continue;
            if ([ame329_excluded containsObject:ame329_item]) continue;
            [ame329_pending addObject:ame329_item];
        }
        NSInteger ame329_moved = 0;
        if (ame329_pending.count > 0) {
            if (![ame329_fm fileExistsAtPath:ame329_vdir]) {
                [ame329_fm createDirectoryAtPath:ame329_vdir withIntermediateDirectories:YES attributes:nil error:nil];
            }
            for (NSString *ame329_item in ame329_pending) {
                ame329_moveEntry(ame329_fm,
                                 [ame329_gdStd stringByAppendingPathComponent:ame329_item],
                                 ame329_vdir, ame329_ts, &ame329_moved);
            }
        }
        // gameDir 重指：搬了东西，或根已净但版本目录有内容（上次重指失败残留修复）
        BOOL ame329_vdirHasData = NO;
        for (NSString *ame329_e in [ame329_fm contentsOfDirectoryAtPath:ame329_vdir error:nil]) {
            if ([ame329_e isEqualToString:[NSString stringWithFormat:@"%@.json", ame329_vid]]) continue;
            if ([ame329_e isEqualToString:[NSString stringWithFormat:@"%@.jar", ame329_vid]]) continue;
            if ([ame329_e hasPrefix:@"."]) continue;
            ame329_vdirHasData = YES;
            break;
        }
        BOOL ame329_needRep = (ame329_moved > 0) || (ame329_pending.count == 0 && ame329_vdirHasData);
        if (!ame329_needRep) continue;
        NSString *ame329_oldGd = ame329_gd;
        [PLProfiles.current applyChanges:^(NSMutableDictionary<NSString *, id> *ame329_profs) {
            NSMutableDictionary *ame329_p = [ame329_profs[ame329_name] mutableCopy]
                ?: [NSMutableDictionary dictionary];
            ame329_p[@"gameDir"] = ame329_vdir;
            ame329_profs[ame329_name] = ame329_p;
        }];
        ame329_unified++;
        NSLog(@"[Ame329] instance data unified into version axis: instances/%@ → versions/%@ (%ld item(s) moved, gameDir %@ → %@)",
              ame329_rest, ame329_vid, (long)ame329_moved, ame329_oldGd, ame329_vdir);
    }
    if (ame329_unified > 0) {
        NSLog(@"[Ame329] version-axis unification done: %ld profile(s) re-pointed -- versions/<vid>/ now holds full isolated data (ZL2/PCL2 parity)",
              (long)ame329_unified);
    }
    // ★ Task330：默认实例形态补口（gameDir 空/缺省的常规实例此前整支被
    //   绝对路径判据跳过 —— 装机 [Ame329] 统一日志零出现的根因）。
    [ModService ame330_unifyDefaultInstanceIntoVersionAxis];
}

/// ★ Task330：默认实例版本轴统一 —— "versions 依旧没有文件"第六轮收口。
/// 病历（装机 6f27abab latestlog 实锤）：ame329 判据①要求 profile gameDir
/// 为【绝对路径】，默认实例（gameDir 空/缺省，游戏数据活在 POJAV_GAME_DIR
/// = instances/<id> 实例根）整支被绝对路径判据 continue 跳过 —— 装机日志
/// [Ame324] 建六目录骨架 → [Ame328] 六目录全空判诱饵剪除 → versions/<vid>/
/// 恒只有 json+jar，[Ame329] 统一日志零出现。本 pass 补齐默认实例形态：
/// 生效根 = POJAV_GAME_DIR 解析（Task226 链 → instances/<id>），判据与
/// ame329 同源（两层实例根 + 真实目录 + 版本目录真身 marker），命中即把
/// 根级游戏数据搬进 versions/<vid>/ 并把 profile gameDir 重指绝对路径
/// （启动链按 profile gameDir 下发生效目录 → MC 从版本目录读写 saves/
/// mods/options.txt；版本 json/jar 本就在版本目录，POJAV_GAME_DIR/versions/
/// 解析路径不变，启动零扰动）。
/// 守卫（比 ame329 更严，防多档共根误伤）：
///   · 生效根必须恰为 instances/<id> 两层（POJAV_HOME 本体/共享根不碰）；
///   · 空值 gameDir 的 profile 有多个且 lastVersionId 不一致 = 共根歧义，
///     整轮跳过（保守优先零误伤）；全部同版本才统一搬家+统一重指；
///   · launcher_preferences.plist 豁免（PLPreferences 恒读实例根，见
///     ame329 豁免集 Task330 注）；
///   · 已迁移深层形态（gameDir=instances/<id>/versions/<vid>）不进本
///     pass（绝对路径走 ame329 判据），幂等天然成立。
+ (void)ame330_unifyDefaultInstanceIntoVersionAxis {
    const char *ame330_env = getenv("POJAV_GAME_DIR");
    const char *ame330_homeC = getenv("POJAV_HOME");
    if (!ame330_env || !*ame330_env || !ame330_homeC || !*ame330_homeC) return;
    NSString *ame330_root = [[NSString stringWithUTF8String:ame330_env]
        stringByResolvingSymlinksInPath];
    if (ame330_root.length == 0) return;
    NSString *ame330_instances = [[NSString stringWithUTF8String:ame330_homeC]
        stringByAppendingPathComponent:@"instances"];
    NSString *ame330_prefix = [[ame330_instances stringByStandardizingPath]
        stringByAppendingString:@"/"];
    if (![ame330_root hasPrefix:ame330_prefix]) return;   // 共享根/自定义根不碰
    NSString *ame330_rest = [ame330_root substringFromIndex:ame330_prefix.length];
    if (ame330_rest.length == 0 || [ame330_rest rangeOfString:@"/"].location != NSNotFound) return;
    NSFileManager *ame330_fm = [NSFileManager defaultManager];
    NSDictionary *ame330_attrs = [ame330_fm attributesOfItemAtPath:ame330_root error:nil];
    if (!ame330_attrs || ![ame330_attrs[NSFileType] isEqualToString:NSFileTypeDirectory]) return;
    // 默认形态 profile 清单（gameDir 空值/缺省/"."；其他相对路径不猜）
    NSDictionary *ame330_profiles = PLProfiles.current.profiles;
    NSMutableArray<NSString *> *ame330_names = [NSMutableArray array];
    NSMutableSet<NSString *> *ame330_vids = [NSMutableSet set];
    for (NSString *ame330_name in ame330_profiles.allKeys) {
        NSDictionary *ame330_prof = ame330_profiles[ame330_name];
        if (![ame330_prof isKindOfClass:[NSDictionary class]]) continue;
        NSString *ame330_gd = ame330_prof[@"gameDir"];
        if ([ame330_gd isKindOfClass:[NSString class]] && ame330_gd.length > 0
            && ![ame330_gd isEqualToString:@"."]) continue;
        NSString *ame330_vid = ame330_prof[@"lastVersionId"];
        if (![ame330_vid isKindOfClass:[NSString class]] || ame330_vid.length == 0) continue;
        [ame330_names addObject:ame330_name];
        [ame330_vids addObject:ame330_vid];
    }
    if (ame330_names.count == 0) return;
    if (ame330_vids.count > 1) {
        NSLog(@"[Ame330] default-instance unify skipped: %lu default profile(s) share the root with distinct versions -- ambiguous, no touch",
              (unsigned long)ame330_names.count);
        return;
    }
    NSString *ame330_vid = ame330_vids.anyObject;
    NSString *ame330_vdir = [ame330_root stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@", ame330_vid]];
    NSString *ame330_marker = [ame330_vdir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.json", ame330_vid]];
    if (![ame330_fm fileExistsAtPath:ame330_marker]) return;   // 无主实例绝不盲搬
    // 根级候选搬家清单（与 ame329 同口径：非隐藏、非共享层、非导入元数据）
    NSSet *ame330_excluded = [NSSet setWithArray:@[
        @"versions", @"assets", @"libraries",
        @"import_report.json", @".ame269_backup", @"custom_gamedir",
        @"launcher_preferences.plist"
    ]];
    NSMutableArray<NSString *> *ame330_pending = [NSMutableArray array];
    for (NSString *ame330_item in [ame330_fm contentsOfDirectoryAtPath:ame330_root error:nil]) {
        if ([ame330_item hasPrefix:@"."]) continue;
        if ([ame330_excluded containsObject:ame330_item]) continue;
        [ame330_pending addObject:ame330_item];
    }
    NSInteger ame330_moved = 0;
    NSString *ame330_ts = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    if (ame330_pending.count > 0) {
        if (![ame330_fm fileExistsAtPath:ame330_vdir]) {
            [ame330_fm createDirectoryAtPath:ame330_vdir
              withIntermediateDirectories:YES attributes:nil error:nil];
        }
        for (NSString *ame330_item in ame330_pending) {
            ame329_moveEntry(ame330_fm,
                             [ame330_root stringByAppendingPathComponent:ame330_item],
                             ame330_vdir, ame330_ts, &ame330_moved);
        }
    }
    // 重指：搬了东西，或根已净但版本目录有内容（上次重指失败残留修复）
    BOOL ame330_vdirHasData = NO;
    for (NSString *ame330_e in [ame330_fm contentsOfDirectoryAtPath:ame330_vdir error:nil]) {
        if ([ame330_e isEqualToString:[NSString stringWithFormat:@"%@.json", ame330_vid]]) continue;
        if ([ame330_e isEqualToString:[NSString stringWithFormat:@"%@.jar", ame330_vid]]) continue;
        if ([ame330_e hasPrefix:@"."]) continue;
        ame330_vdirHasData = YES;
        break;
    }
    if (ame330_moved == 0 && !(ame330_pending.count == 0 && ame330_vdirHasData)) return;
    [PLProfiles.current applyChanges:^(NSMutableDictionary<NSString *, id> *ame330_profs) {
        for (NSString *ame330_name in ame330_names) {
            NSMutableDictionary *ame330_p = [ame330_profs[ame330_name] mutableCopy]
                ?: [NSMutableDictionary dictionary];
            ame330_p[@"gameDir"] = ame330_vdir;
            ame330_profs[ame330_name] = ame330_p;
        }
    }];
    NSLog(@"[Ame330] default instance data unified into version axis: instances/%@ → versions/%@ (%ld item(s) moved, %lu profile(s) re-pointed -- PCL2/ZL2 parity)",
          ame330_rest, ame330_vid, (long)ame330_moved, (unsigned long)ame330_names.count);
}

- (nullable NSString *)existingModsFolderForProfile:(NSString *)profileName {
    // ★ Task274-h S7：nil 入参跟随当前选中实例（ame267 语义），不再落恒 miss 的
    // @"default" 字面量（真实默认键 "(Default)"；对齐 Task270 M1 服务层口径）。
    if (!profileName.length) profileName = PLProfiles.current.selectedProfileName ?: @"(Default)";
    NSString *profile = profileName;
    NSFileManager *fm = [NSFileManager defaultManager];

    // 优先用 profile gameDir（已解析为绝对路径）
    NSString *resolvedGameDir = [self resolveAbsoluteGameDirForProfile:profile];
    if (resolvedGameDir.length > 0) {
        NSString *modsPath = [resolvedGameDir stringByAppendingPathComponent:@"mods"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:modsPath isDirectory:&isDir] && isDir) {
            return modsPath;
        }
    }

    // 回退到 POJAV_GAME_DIR/mods
    const char *gameDirC = getenv("POJAV_GAME_DIR");
    if (gameDirC) {
        NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
        NSString *modsPath = [gameDir stringByAppendingPathComponent:@"mods"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:modsPath isDirectory:&isDir] && isDir) {
            return modsPath;
        }
    }
    return nil;
}

/// Task264：当前 profile 实际生效的 mods 目录（与 scanModsForProfile 同源同目录，
/// Task219 隔离优先语义）。模组管理页展示"扫描目录"提示行 + 文件 App 定点打开。
/// 用户中途放入该目录的 .jar 重扫后必然可见；此前导入按钮走 ensureModsFolderForProfile(nil)
/// 恒解析到 default 主目录，整合包实例的隔离目录永远收不到文件——中途加 mod 不显示根因。
- (nullable NSString *)ame264_effectiveModsFolderForProfile:(NSString *)profileName {
    return [self ensureModsFolderForProfile:profileName error:nil];
}

/// 获取当前 profile 的 mods 目录，不存在时自动创建
- (nullable NSString *)ensureModsFolderForProfile:(NSString *)profileName error:(NSError **)error {
    // ★ Task274-h S7：nil 入参跟随当前选中实例（ame267 语义），不再落恒 miss 的
    // @"default" 字面量（真实默认键 "(Default)"；对齐 Task270 M1 服务层口径）。
    if (!profileName.length) profileName = PLProfiles.current.selectedProfileName ?: @"(Default)";
    NSString *profile = profileName;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *modsPath = nil;

    // 优先用 profile gameDir（已解析为绝对路径）
    NSString *resolvedGameDir = [self resolveAbsoluteGameDirForProfile:profile];
    if (resolvedGameDir.length > 0) {
        modsPath = [resolvedGameDir stringByAppendingPathComponent:@"mods"];
    }

    if (!modsPath) {
        const char *gameDirC = getenv("POJAV_GAME_DIR");
        if (gameDirC) {
            NSString *gameDir = [NSString stringWithUTF8String:gameDirC];
            modsPath = [gameDir stringByAppendingPathComponent:@"mods"];
        }
    }

    if (!modsPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModService" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_105", nil)}];
        }
        return nil;
    }

    BOOL isDir = NO;
    if (![fm fileExistsAtPath:modsPath isDirectory:&isDir]) {
        // 目录不存在，创建
        NSError *createError = nil;
        [fm createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:&createError];
        if (createError) {
            if (error) *error = createError;
            return nil;
        }
        NSLog(@"[ModService] Created mods directory: %@", modsPath);
    } else if (!isDir) {
        if (error) {
            *error = [NSError errorWithDomain:@"ModService" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_451", nil), modsPath]}];
        }
        return nil;
    }
    return modsPath;
}

// ---------- 缓存方法 ----------
- (BOOL)needsRescanForPath:(NSString *)path {
    __block BOOL needs = YES;
    dispatch_sync(self.cacheQueue, ^{
        NSDate *lastScan = self.checkpointTimes[path];
        if (lastScan) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            NSDate *modifyDate = attrs[NSFileModificationDate];
            if (modifyDate && [modifyDate isEqualToDate:lastScan]) {
                needs = NO;
            }
        }
    });
    return needs;
}

- (void)updateCheckpointForPath:(NSString *)path {
    dispatch_barrier_async(self.cacheQueue, ^{
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *modifyDate = attrs[NSFileModificationDate];
        if (modifyDate) {
            self.checkpointTimes[path] = modifyDate;
        }
    });
}

- (nullable ModItem *)cachedModForPath:(NSString *)path {
    __block ModItem *item = nil;
    dispatch_sync(self.cacheQueue, ^{
        item = self.metadataCache[path];
    });
    return item;
}

- (void)cacheModItem:(ModItem *)item forPath:(NSString *)path {
    dispatch_barrier_async(self.cacheQueue, ^{
        self.metadataCache[path] = item;
    });
}

// ---------- ★Task474：整合包 payload 对账提升（ZL2 单入口第十面·导入写面） ----------
// 病历（装机 4da7866 latestlog.old.txt 实锤）：Fabulously Optimized 导入
// "Mod download completed: 50/50 succeeded, 42.13 MB"，但落盘走 Task329 实例
// 账本轴 instances/<modpackId>/mods，而 Task473 ZL2 单入口后的启动/模组页
// 读 versions/<vid>/mods（isolation=1，launch 锚 "[JavaLauncher] Task473:
// gameDir = .../versions/<vid>"）——写读分居，三扫描根 jars=0，用户
// "模组全部不见了"。ame329/ame330 实例轴对账经查全仓零调用点（死代码），
// 存量搁浅无自愈路径。
// 修法 = ①导入收尾（applyIsolationForModPackVersion 之后）payload 提升进
// [ZL2GamePath gameDirForVersion:versionId]；②启动期 sweep 救存量
// （profile.gameDir 归属判据，无主不盲搬）。冲突改名并置绝不覆盖
// （ame329_moveEntry 家法原语直接复用，零新增搬家代码路径）。

static NSArray<NSString *> *ame474_payloadItems(void) {
    static NSArray<NSString *> *ame474_items;
    static dispatch_once_t ame474_once;
    dispatch_once(&ame474_once, ^{
        ame474_items = @[@"mods", @"config", @"resourcepacks", @"shaderpacks",
                         @"texturepacks", @"saves", @"screenshots",
                         @"servers.dat", @"options.txt"];
    });
    return ame474_items;
}

+ (NSInteger)ame474_promotePayloadFrom:(NSString *)srcDir to:(NSString *)dstDir {
    if (srcDir.length == 0 || dstDir.length == 0) return 0;
    NSString *ame474_srcStd = [srcDir stringByStandardizingPath];
    NSString *ame474_dstStd = [dstDir stringByStandardizingPath];
    if (ame474_srcStd.length == 0 || [ame474_srcStd isEqualToString:ame474_dstStd]) return 0; // 同目录自搬家防呆
    NSFileManager *ame474_fm = [NSFileManager defaultManager];
    BOOL ame474_srcIsDir = NO;
    if (![ame474_fm fileExistsAtPath:ame474_srcStd isDirectory:&ame474_srcIsDir] || !ame474_srcIsDir) return 0;
    if (![ame474_fm fileExistsAtPath:ame474_dstStd]) {
        [ame474_fm createDirectoryAtPath:ame474_dstStd withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *ame474_ts = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSInteger ame474_moved = 0;
    for (NSString *ame474_item in ame474_payloadItems()) {
        NSString *ame474_src = [ame474_srcStd stringByAppendingPathComponent:ame474_item];
        if (![ame474_fm fileExistsAtPath:ame474_src]) continue;
        ame329_moveEntry(ame474_fm, ame474_src, ame474_dstStd, ame474_ts, &ame474_moved);
    }
    return ame474_moved;
}

+ (void)ame474_rescueStrandedPayload {
    const char *ame474_homeC = getenv("POJAV_HOME");
    if (!ame474_homeC || !*ame474_homeC) return;
    NSString *ame474_instances = [[NSString stringWithUTF8String:ame474_homeC]
        stringByAppendingPathComponent:@"instances"];
    NSFileManager *ame474_fm = [NSFileManager defaultManager];
    NSString *ame474_rootStd = [ame474_instances stringByStandardizingPath];
    NSString *ame474_rootPrefix = [ame474_rootStd stringByAppendingString:@"/"];
    NSDictionary *ame474_profiles = PLProfiles.current.profiles;
    NSInteger ame474_hit = 0;
    for (NSString *ame474_name in ame474_profiles.allKeys) {
        NSDictionary *ame474_prof = ame474_profiles[ame474_name];
        if (![ame474_prof isKindOfClass:[NSDictionary class]]) continue;
        NSString *ame474_gd = ame474_prof[@"gameDir"];
        if (![ame474_gd isKindOfClass:[NSString class]] || ![ame474_gd isAbsolutePath]) continue;
        NSString *ame474_gdStd = [ame474_gd stringByStandardizingPath];
        // 判据①：恰为 instances/<id> 两层实例根（深层形态 instances/<id>/versions/<vid>
        //   已被 ame371 扫描根④覆盖，不属搁浅面）
        if (![ame474_gdStd hasPrefix:ame474_rootPrefix]) continue;
        NSString *ame474_rest = [ame474_gdStd substringFromIndex:ame474_rootPrefix.length];
        if (ame474_rest.length == 0 || [ame474_rest rangeOfString:@"/"].location != NSNotFound) continue;
        if ([ame474_rest isEqualToString:@"default"]) continue; // 默认实例轴不碰
        NSDictionary *ame474_attrs = [ame474_fm attributesOfItemAtPath:ame474_gdStd error:nil];
        if (!ame474_attrs || [ame474_attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;
        BOOL ame474_dirOK = NO;
        if (![ame474_fm fileExistsAtPath:ame474_gdStd isDirectory:&ame474_dirOK] || !ame474_dirOK) continue;
        // 判据②：lastVersionId 可解析（latest-* 别名不参与实体定位，ame371 同判据）
        NSString *ame474_vid = ame474_prof[@"lastVersionId"];
        if (![ame474_vid isKindOfClass:[NSString class]] || ame474_vid.length == 0) continue;
        if ([ame474_vid hasPrefix:@"latest-"]) continue;
        // 目标根走 profile 轴单入口（gameDirForProfile）：隔离 vid → versions/<vid>；
        //   非隔离+自定义目录 → instances/<id> 本身（=src，等值守卫跳过零搬运，
        //   绝不误搬共享根造成新脱同步——消费方读哪儿就对齐哪儿）
        NSString *ame474_target = [ZL2GamePath gameDirForProfile:ame474_name];
        NSString *ame474_targetStd = [ame474_target stringByStandardizingPath];
        if ([ame474_targetStd isEqualToString:ame474_gdStd]) continue;
        NSInteger ame474_moved = [self ame474_promotePayloadFrom:ame474_gdStd to:ame474_targetStd];
        if (ame474_moved > 0) {
            ame474_hit++;
            NSLog(@"[Ame474] rescued %ld payload item(s) from instances/%@ → %@ (ZL2 单入口对账, profile=%@, vid=%@)",
                  (long)ame474_moved, ame474_rest, ame474_targetStd, ame474_name, ame474_vid);
        }
        // 搬后空壳摘除（仅剩隐藏条目时；有数据的账本目录绝不触碰）
        NSArray<NSString *> *ame474_left = [ame474_fm contentsOfDirectoryAtPath:ame474_gdStd error:nil] ?: @[];
        BOOL ame474_empty = YES;
        for (NSString *ame474_e in ame474_left) {
            if ([ame474_e hasPrefix:@"."]) continue;
            ame474_empty = NO;
            break;
        }
        if (ame474_empty) [ame474_fm removeItemAtPath:ame474_gdStd error:nil];
    }
    if (ame474_hit > 0) {
        NSLog(@"[Ame474] stranded payload rescue done: %ld instance dir(s) reconciled into ZL2 单入口根",
              (long)ame474_hit);
    }
}

// ---------- 扫描模组（核心优化）----------
// ★ Task371：版本轴多根联合扫描 —— "模组列表加载不出来"根修。
//   病历（装机 f3854ee latestlog 实锤）：模组管理页对版本轴形态只认单根
//   （相对 gameDir 按 POJAV_GAME_DIR 展开 = 全局根 Library/Application
//   Support/minecraft/versions/<vid>/mods，且缺目录即创建 —— 21:57 两条
//   Created mods directory 全局根日志），而同一版本的真实数据可能落在
//   实例轴（Task265 download dest 实锤 instances/<id>/versions/<vid>/mods，
//   JEI 就在那）或 versions/<vid>/game 变体（Forge/Fabric 直装器写入形态）
//   ——启动链 Task353 已有 ame353_versionRootForProfileName 祖先链口径，
//   扫描侧没吃 = 装哪儿扫哪儿变成"游戏读 A 页面扫 B"。
//   修法 = 有序候选根联合扫描（同文件名先到先得去重）：主根（Task219
//   隔离优先语义不变）→ ame353 版本根两种形态 → 实例轴一跳 glob
//   （Task353 ZL2VersionIndex ②' 实例树兜底同款纪律）→ 全局根两种形态。
//   仅新增【读取】面；写入面（Task265 download dest / ensureModsFolder）
//   分毫不动 = 全新安装零回归。
- (NSArray<NSString *> *)ame371_scanRootsForProfile:(NSString *)profileName {
    NSMutableArray<NSString *> *ame371_roots = [NSMutableArray array];
    void (^ame371_push)(NSString *) = ^(NSString *dir) {
        if (dir.length == 0) return;
        NSString *std = [dir stringByStandardizingPath];
        if (![ame371_roots containsObject:std]) [ame371_roots addObject:std];
    };

    // ① 主根：Task219 隔离优先解析（可能尚不存在——联合扫描里跳过不存在的根，
    //   创建语义仍归 ensureModsFolder 专属，扫描绝不造目录）
    NSString *ame371_primary = [self existingModsFolderForProfile:profileName];
    if (!ame371_primary) {
        NSString *ame371_resolved = [self resolveAbsoluteGameDirForProfile:profileName];
        if (ame371_resolved.length > 0) {
            NSString *ame371_p = [ame371_resolved stringByAppendingPathComponent:@"mods"];
            BOOL ame371_isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:ame371_p isDirectory:&ame371_isDir] && ame371_isDir) {
                ame371_primary = ame371_p;
            }
        }
    }
    ame371_push(ame371_primary);

    // ② 版本轴候选 vid（latest-* 别名不参与实体定位，ame353 同判据）
    NSString *ame371_vid = nil;
    NSDictionary *ame371_prof = PLProfiles.current.profiles[profileName ?: @""];
    if ([ame371_prof isKindOfClass:[NSDictionary class]]) {
        NSString *ame371_lv = ame371_prof[@"lastVersionId"];
        if ([ame371_lv isKindOfClass:[NSString class]] && ame371_lv.length > 0 && ![ame371_lv hasPrefix:@"latest-"]) {
            ame371_vid = ame371_lv;
        }
    }

    if (ame371_vid.length > 0) {
        NSFileManager *ame371_fm = [NSFileManager defaultManager];
        BOOL (^ame371_dirExists)(NSString *) = ^BOOL(NSString *p) {
            BOOL isDir = NO;
            return [ame371_fm fileExistsAtPath:p isDirectory:&isDir] && isDir;
        };
        NSString *(^ame371_modsIn)(NSString *) = ^NSString *(NSString *verDir) {
            NSString *m = [verDir stringByAppendingPathComponent:@"mods"];
            return ame371_dirExists(m) ? m : nil;
        };

        // ③ ame353 版本根（启动链权威口径）两种形态：R/versions/<vid>/ 与
        //    旧隔离 R/versions/<vid>/game/
        NSString *ame373_root = [PLProfiles ame353_versionRootForProfileName:profileName];
        if (ame373_root.length > 0) {
            NSString *ame371_verDir = [[ame373_root stringByAppendingPathComponent:@"versions"]
                stringByAppendingPathComponent:ame371_vid];
            ame371_push(ame371_modsIn(ame371_verDir));
            ame371_push(ame371_modsIn([ame371_verDir stringByAppendingPathComponent:@"game"]));
        }

        // ④ 实例轴一跳 sweep：POJAV_HOME/instances/*/versions/<vid>（Task353
        //    实例树兜底同款一跳纪律；Task265 下载 dest 实锤数据的真实落点）
        const char *ame371_homeC = getenv("POJAV_HOME");
        if (ame371_homeC && *ame371_homeC) {
            NSString *ame371_instances = [[NSString stringWithUTF8String:ame371_homeC]
                stringByAppendingPathComponent:@"instances"];
            for (NSString *ame371_inst in [ame371_fm contentsOfDirectoryAtPath:ame371_instances error:nil] ?: @[]) {
                if ([ame371_inst hasPrefix:@"."]) continue;
                NSString *ame371_verDir = [[[ame371_instances
                    stringByAppendingPathComponent:ame371_inst]
                    stringByAppendingPathComponent:@"versions"]
                    stringByAppendingPathComponent:ame371_vid];
                ame371_push(ame371_modsIn(ame371_verDir));
                ame371_push(ame371_modsIn([ame371_verDir stringByAppendingPathComponent:@"game"]));
            }
        }

        // ⑤ 全局根两种形态（历史混居通例 Task322 / 直装器 game 变体）
        const char *ame371_gameC = getenv("POJAV_GAME_DIR");
        if (ame371_gameC && *ame371_gameC) {
            NSString *ame371_verDir = [[[NSString stringWithUTF8String:ame371_gameC]
                stringByAppendingPathComponent:@"versions"]
                stringByAppendingPathComponent:ame371_vid];
            ame371_push(ame371_modsIn(ame371_verDir));
            ame371_push(ame371_modsIn([ame371_verDir stringByAppendingPathComponent:@"game"]));
        }
    }
    return [ame371_roots copy];
}

- (void)scanModsForProfile:(NSString *)profileName completion:(ModListHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Task219（⑪）：扫描改隔离优先——隔离 profile 只扫隔离目录（缺目录
        // 视为空列表，不再被共享目录的 mod 假装成"已安装"；下载侧同款
        // 语义，装哪儿扫哪儿）。
        // ★ Task371：改为版本轴多根联合扫描（同文件名先到先得去重）——主根
        //   语义不变，实例轴/全局根/game 变体补读，见 ame371_scanRootsForProfile。
        NSString *modsFolder = [self ensureModsFolderForProfile:profileName error:nil];
        NSArray<NSString *> *ame371_roots = [self ame371_scanRootsForProfile:profileName];
        NSMutableArray<ModItem *> *items = [NSMutableArray array];
        NSMutableSet<NSString *> *ame371_seen = [NSMutableSet set];
        dispatch_group_t group = dispatch_group_create();

        if (!modsFolder && ame371_roots.count > 0) {
            modsFolder = ame371_roots.firstObject;
        }

        if (!modsFolder || ame371_roots.count == 0) {
            NSLog(@"[ModService] Task265 scan: profile=%@ folder=(nil) jars=0", profileName ?: @"(nil)");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(items); });
            }
            return;
        }

        NSFileManager *ame371_fm = [NSFileManager defaultManager];
        for (NSString *ame371_root in ame371_roots) {
            NSArray<NSString *> *contents = [ame371_fm contentsOfDirectoryAtPath:ame371_root error:nil];
            NSUInteger ame371_rootJars = 0;
            for (NSString *fileName in contents) {
                if ([fileName.lowercaseString hasSuffix:@".jar"] || [fileName.lowercaseString hasSuffix:@".jar.disabled"]) {
                    // ★ Task371：同文件名先到先得——主根（游戏实际读取面）优先，
                    //   其余根只补缺，绝不让次根副本顶掉主根条目
                    NSString *ame371_key = fileName.lowercaseString;
                    if ([ame371_seen containsObject:ame371_key]) continue;
                    [ame371_seen addObject:ame371_key];
                    ame371_rootJars++;
                    NSString *fullPath = [ame371_root stringByAppendingPathComponent:fileName];

                    // 检查缓存
                    if (![self needsRescanForPath:fullPath]) {
                        ModItem *cached = [self cachedModForPath:fullPath];
                        if (cached) {
                            [items addObject:cached];
                            continue;
                        }
                    }

                    ModItem *mod = [[ModItem alloc] initWithFilePath:fullPath];
                    [items addObject:mod];

                    dispatch_group_enter(group);
                    [self fetchMetadataForMod:mod completion:^(ModItem *populatedMod, NSError *error) {
                        if (!error) {
                            [self cacheModItem:populatedMod forPath:fullPath];
                            [self updateCheckpointForPath:fullPath];
                        }
                        dispatch_group_leave(group);
                    }];
                }
            }
            if (ame371_roots.count > 1) {
                NSLog(@"[Ame371] scan root: profile=%@ root=%@ jars=%lu",
                      profileName ?: @"(nil)", ame371_root, (unsigned long)ame371_rootJars);
            }
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            // ★ Task265：扫描结果锚——与 download dest 锚成对，目录错位一轮日志定音
            NSLog(@"[ModService] Task265 scan: profile=%@ folder=%@ jars=%ld (ame371 roots=%lu)",
                  profileName ?: @"(nil)", modsFolder, (long)items.count,
                  (unsigned long)ame371_roots.count);
            [items sortUsingComparator:^NSComparisonResult(ModItem *obj1, ModItem *obj2) {
                NSString *name1 = obj1.displayName ?: obj1.fileName;
                NSString *name2 = obj2.displayName ?: obj2.fileName;
                return [name1 localizedCaseInsensitiveCompare:name2];
            }];
            if (completion) completion(items);
        });
    });
}

// ---------- 元数据获取（原逻辑，仅被上面调用）----------
- (void)fetchMetadataForMod:(ModItem *)mod completion:(ModMetadataHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Fabric
            NSData *fabricData = [self readFileFromJar:mod.filePath entryName:@"fabric.mod.json"];
            if (fabricData) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:fabricData options:0 error:nil];
                if ([json isKindOfClass:[NSDictionary class]]) {
                    mod.isFabric = YES;
                    mod.onlineID = json[@"id"];
                    mod.version = json[@"version"];
                    mod.displayName = json[@"name"];
                    mod.modDescription = json[@"description"];
                    mod.author = [json[@"authors"] componentsJoinedByString:@", "];

                    NSDictionary *deps = json[@"depends"];
                    if ([deps isKindOfClass:[NSDictionary class]] && [deps[@"minecraft"] isKindOfClass:[NSString class]]) {
                        mod.gameVersion = deps[@"minecraft"];
                    }

                    // ★Task413 jar 内链接提取（第 22 轮复诉「模组在线查询回归的
                    //   模组链接…除非 jar 里面写的链接不是 cf 或者 mod 源的网站
                    //   才跳转」）：fabric.mod.json contact.homepage 为主页链接
                    //   源（ModItem.homepage 既有字段首度接线；cardTapped 按
                    //   cf/modrinth 域分流内跳/外跳）
                    NSDictionary *contact = json[@"contact"];
                    if ([contact isKindOfClass:[NSDictionary class]] &&
                        [contact[@"homepage"] isKindOfClass:[NSString class]]) {
                        mod.homepage = contact[@"homepage"];
                    }

                    NSString *iconPath = json[@"icon"];
                    if ([iconPath isKindOfClass:[NSString class]]) {
                        NSData *iconData = [self readFileFromJar:mod.filePath entryName:iconPath];
                        if (iconData) mod.icon = [[UIImage alloc] initWithData:iconData];
                    }
                    if (completion) completion(mod, nil);
                    return;
                }
            }

            // Forge / NeoForge
            NSData *tomlData = [self readFileFromJar:mod.filePath entryName:@"META-INF/mods.toml"];
            if (tomlData) {
                mod.isForge = YES;
            } else {
                tomlData = [self readFileFromJar:mod.filePath entryName:@"META-INF/neoforge.mods.toml"];
                if (tomlData) mod.isNeoForge = YES;
            }

            if (tomlData) {
                NSString *tomlString = [[NSString alloc] initWithData:tomlData encoding:NSUTF8StringEncoding];
                NSDictionary<NSString *, id> *toml = [self parseTomlString:tomlString];
                NSArray *mods = toml[@"mods"];
                if ([mods isKindOfClass:[NSArray class]] && mods.count > 0) {
                    NSDictionary *modInfo = mods.firstObject;
                    if ([modInfo isKindOfClass:[NSDictionary class]]) {
                        mod.onlineID = modInfo[@"modId"];
                        mod.version = modInfo[@"version"];
                        mod.displayName = modInfo[@"displayName"];
                        mod.modDescription = modInfo[@"description"];
                        mod.author = modInfo[@"authors"];

                        // ★Task413 jar 内链接提取（mods.toml displayURL；同上
                        //   cardTapped 域分流口径）
                        if ([modInfo[@"displayURL"] isKindOfClass:[NSString class]]) {
                            mod.homepage = modInfo[@"displayURL"];
                        }

                        NSArray *deps = nil;
                        for (NSString *key in toml) {
                            if ([key hasPrefix:@"dependencies"]) {
                                deps = toml[key];
                                break;
                            }
                        }
                        if ([deps isKindOfClass:[NSArray class]]) {
                            for (NSDictionary *depInfo in deps) {
                                if ([depInfo isKindOfClass:[NSDictionary class]] && [depInfo[@"modId"] isEqualToString:@"minecraft"]) {
                                    mod.gameVersion = depInfo[@"versionRange"];
                                    break;
                                }
                            }
                        }

                        NSString *logoFile = modInfo[@"logoFile"];
                        if (logoFile.length > 0) {
                            NSData *logoData = [self readFileFromJar:mod.filePath entryName:logoFile];
                            if (logoData) mod.icon = [[UIImage alloc] initWithData:logoData];
                        }
                        if (completion) completion(mod, nil);
                        return;
                    }
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[ModService] CRITICAL: Exception while parsing %@: %@", mod.fileName, exception);
        }

        // ★Task413 旧版 Forge 兼容：mcmod.info 补遗（fabric/neo-toml 均缺席时）
        //   ——「url」字段 = jar 内主页链接第三源（cardTapped 域分流同口径）；
        //   元数据主体（名称/图标）仍按旧口径零变动（mcmod 只补链接缺席面）。
        @try {
            if (mod.homepage.length == 0) {
                NSData *mcmodData = [self readFileFromJar:mod.filePath entryName:@"mcmod.info"];
                if (mcmodData) {
                    id mcmod = [NSJSONSerialization JSONObjectWithData:mcmodData options:0 error:nil];
                    // ★ 类型声明先行（id 点语法 count/firstObject = run 42487051782
                    //   / 42500577120 同族编译雷判例：id 接收者禁点语法）
                    NSArray *ame413_mcmodList = nil;
                    if ([mcmod isKindOfClass:[NSArray class]]) {
                        ame413_mcmodList = mcmod;
                    } else if ([mcmod isKindOfClass:[NSDictionary class]]) {
                        id ame413_inner = [(NSDictionary *)mcmod objectForKey:@"modList"];
                        if ([ame413_inner isKindOfClass:[NSArray class]]) {
                            ame413_mcmodList = ame413_inner;
                        } else {
                            ame413_mcmodList = [NSArray arrayWithObject:(NSDictionary *)mcmod];   // 单对象形态
                        }
                    }
                    if (ame413_mcmodList.count > 0) {
                        NSDictionary *firstMod = [ame413_mcmodList objectAtIndex:0];
                        if ([firstMod isKindOfClass:[NSDictionary class]] &&
                            [firstMod[@"url"] isKindOfClass:[NSString class]]) {
                            mod.homepage = firstMod[@"url"];
                        }
                    }
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[ModService] mcmod.info link probe exception (%@): %@", mod.fileName, exception);
        }

        if (completion) completion(mod, nil);
    });
}

// ---------- 文件操作（启用/禁用、删除）----------
- (BOOL)toggleEnableForMod:(ModItem *)mod error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *currentPath = mod.filePath;

    // Task217（"部分 Mod 无法点击"根修前置）：源文件存在性预检。列表项可能
    // 因更新替换 / 文件 App 手工整理后指向不存在的路径（moveItemAtPath 的
    // ENOENT 以前一路裸抛，管理页只 NSLog，开关被 updateToggleState 弹回 =
    // 用户视角"点了没反应"）。返回明确本地化错误；调用方据此弹窗 + 自愈重扫。
    BOOL ame217_srcIsDir = NO;
    if (currentPath.length == 0 ||
        ![fileManager fileExistsAtPath:currentPath isDirectory:&ame217_srcIsDir] || ame217_srcIsDir) {
        if (error) *error = [NSError errorWithDomain:@"ModServiceError" code:201
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"mods.toggle.source_missing", nil),
                currentPath.length > 0 ? currentPath.lastPathComponent : @"?"]}];
        return NO;
    }

    NSString *newPath;

    if (mod.disabled) {
        if ([currentPath.lowercaseString hasSuffix:@".jar.disabled"]) {
            newPath = [currentPath substringToIndex:currentPath.length - 9];
        } else {
            if (error) *error = [NSError errorWithDomain:@"ModServiceError" code:101 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_452", nil)}];
            return NO;
        }
    } else {
        newPath = [currentPath stringByAppendingString:@".disabled"];
    }

    // Task217：目标同名预检。mods/ 同时存在 foo.jar 与 foo.jar.disabled 时
    // "启用旧档"必然撞名（更新流程与手工整理的常见残留）；裸 moveItemAtPath
    // 只会给出不可读的 NSFileWriteFileExists。明确告知冲突文件名，用户可在
    // 文件 App（本应用已开 UIFileSharing）或滑动删除里自行清理。
    if ([fileManager fileExistsAtPath:newPath]) {
        if (error) *error = [NSError errorWithDomain:@"ModServiceError" code:202
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"mods.toggle.dest_exists", nil),
                newPath.lastPathComponent]}];
        return NO;
    }

    BOOL success = [fileManager moveItemAtPath:currentPath toPath:newPath error:error];
    if (success) {
        mod.filePath = newPath;
        mod.fileName = [newPath lastPathComponent];
        [mod refreshDisabledFlag];
    }
    return success;
}

- (BOOL)deleteMod:(ModItem *)mod error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:mod.filePath error:error];
}

// ---------- 下载（PLDownloadClient 统一下载器：镜像候选 + SHA1 校验 + 增量命中 + 断点续传）----------
- (void)downloadMod:(ModItem *)mod toProfile:(NSString *)profileName completion:(ModDownloadHandler)completion {
    [self downloadMod:mod toProfile:profileName expectedSHA1:nil progress:nil completion:completion];
}

// ---------- 带进度回调的下载 ----------
- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
            progress:(void (^)(NSProgress *downloadProgress))progress
          completion:(ModDownloadHandler)completion {
    [self downloadMod:mod toProfile:profileName expectedSHA1:nil progress:progress completion:completion];
}

// ---------- 带 SHA1 校验的下载（spec Task 5.1：expectedSHA1 传入即启用校验）----------
- (void)downloadMod:(ModItem *)mod
          toProfile:(NSString *)profileName
       expectedSHA1:(nullable NSString *)expectedSHA1
           progress:(nullable void (^)(NSProgress *downloadProgress))progress
         completion:(ModDownloadHandler)completion {
    // Task269 末梢自愈：目标实例不存在（升级迁移合并后残留的旧实例名引用）→
    // 回落当前选中实例，杜绝"下载进不存在的实例"再次制造错位。
    if (profileName.length > 0 && !PLProfiles.current.profiles[profileName]) {
        NSString *ame269_fallback = PLProfiles.current.selectedProfileName;
        NSLog(@"[ModService] Task269: target profile \"%@\" gone -> fallback to selected \"%@\"",
              profileName, ame269_fallback ?: @"(nil)");
        profileName = ame269_fallback;
    }
    NSString *modsFolder = [self ensureModsFolderForProfile:profileName error:nil];
    // ★ Task265：下载目标锚——今后任何"下载了但游戏/管理页看不到"直接看这行
    NSLog(@"[ModService] Task265 download dest: profile=%@ folder=%@ file=%@",
          profileName ?: @"(nil)", modsFolder, mod.fileName ?: @"(nil)");
    if (!modsFolder) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ModServiceError" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_453", nil)}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return;
    }

    NSURL *url = [NSURL URLWithString:mod.selectedVersionDownloadURL];
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"ModServiceError" code:2 userInfo:@{NSLocalizedDescriptionKey:localize(@"i18n_str_454", nil)}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
        return;
    }

    NSString *destinationPath = [modsFolder stringByAppendingPathComponent:mod.fileName];

    // 注册到统一下载任务管理器（rawTask 稍后赋值为 PLDownloadOperation；悬浮球已移除，始终注册以便下载任务列表跟踪）
    NSString *resourceName = mod.fileName.length > 0 ? mod.fileName : (mod.displayName.length > 0 ? mod.displayName : @"mod");
    NSString *displayName = mod.displayName.length > 0 ? mod.displayName : resourceName;
    // ★ Task274-h S8：退役键 general.download_source（Task218 声明无写入方，恒 nil
    //   → @"official" 来源标签失真）→ PLMirrorCenter legacySourceTokenForType
    //   （Task218 收敛口径，对齐 World/DP/RP/Shader 四服务）。
    NSString *downloadSource = [PLMirrorCenter legacySourceTokenForType:PLMirrorResourceTypeAssetDownload];
    DownloadTaskItem *taskItem = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeMod
                        resourceName:resourceName
                         displayName:displayName
                      downloadSource:downloadSource
                             rawTask:nil
                      supportsResume:YES
                             iconURL:mod.iconURL];
    taskItem.downloadURL = mod.selectedVersionDownloadURL;
    // ★ Task266：下载目标实例随任务标注——资源管理页据 targetProfileName
    //   与本页生效实例比对，跨实例下载展示横幅+一键切换（"游戏加载了、
    //   管理页不显示"的实例错位自解释修复；同锚 Task265 download dest）。
    taskItem.targetProfileName = profileName;
    // redesign-download-ui Phase 4：单文件下载接入统一进度页——
    // PLTaskStagesSingleFile 单阶段 + autoPresentDetail 自动弹出 PLTaskProgressViewController
    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesSingleFile()];
    taskItem.autoPresentDetail = YES;

    // retryHandler：FCL 风格重新下载，复用同一 taskItem，重新发起 PLDownloadClient 请求
    __weak typeof(self) weakSelf = self;
    taskItem.retryHandler = ^id(DownloadTaskItem *taskItemRef) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [strongSelf restartPLDownloadForTaskId:taskItemRef.taskId];
    };

    PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
    // 镜像候选列表：原始 CDN URL（cdn.modrinth.com / edge.forgecdn.net 等）+ MCIM 镜像，
    // 按 download.assetDownloadSource 策略排序（PLMirrorCenter 统一收敛，替代旧版独立镜像工具类）
    request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:url
                                                          resourceType:PLMirrorResourceTypeAssetDownload];
    // Task 5.1：expectedSHA1（版本模型 files[].hashes.sha1）传入即启用 SHA1 校验，
    // 校验失败由 PLDownloadClient 内部按镜像/退避节奏重试
    request.expectedSHA1 = expectedSHA1;
    // Task 5.2：目标文件已存在且校验通过 → PLDownloadClient 零流量直接成功（增量下载）；
    // 目标路径语义与原实现一致（mods/<fileName>.jar）
    request.destinationPath = destinationPath;
    // taskIdentifier 用 DownloadTaskManager 的 taskId，resumeData 断点数据跨次下载可复用
    request.taskIdentifier = taskItem.taskId;
    // 无 SHA1 时对 .jar（zip 格式）做 EOCD 兜底完整性校验
    request.allowZipFallbackCheck = YES;

    [self startPLDownloadWithRequest:request taskItem:taskItem progress:progress completion:completion];
}

#pragma mark - Task267 最近 mod 下载落点记录（模组管理页对账数据源）

// 下载先于开页场景：Task266 横幅靠实时通知，页面不在场时通知够不着。
// 本记录持久于进程生命周期，模组管理页每次 viewWillAppear 对账补挂横幅。
// 回调线程为 PLDownloadClient 完成队列（非主线程），@synchronized 护账。
static NSString *_ame267_lastDLProfile = nil;
static NSString *_ame267_lastDLFile = nil;
static double _ame267_lastDLTs = 0.0;

+ (void)ame267_noteLastModDownloadToProfile:(NSString *)profileName file:(NSString *)fileName {
    @synchronized ([ModService class]) {
        _ame267_lastDLProfile = [profileName copy];
        _ame267_lastDLFile = [fileName copy];
        _ame267_lastDLTs = [[NSDate date] timeIntervalSince1970];
    }
    NSLog(@"[ModService] Task267 last-download record: profile=%@ file=%@", profileName ?: @"(nil)", fileName ?: @"(nil)");
}

+ (nullable NSDictionary<NSString *, id> *)ame267_lastModDownload {
    @synchronized ([ModService class]) {
        if (_ame267_lastDLTs <= 0.0) return nil;
        return @{ @"profile": _ame267_lastDLProfile ?: @"",
                  @"file":    _ame267_lastDLFile ?: @"",
                  @"ts":      @(_ame267_lastDLTs) };
    }
}

#pragma mark - PLDownloadClient 封装（进度 delta 累计 / 速率采样 / 完成分发）

/// 发起（或重发）PLDownloadClient 请求并挂接进度、速率、完成回调。
/// progress/completion 传 nil 时不覆盖已登记的回调（retryHandler 重发时复用首次回调）。
- (nullable PLDownloadOperation *)startPLDownloadWithRequest:(PLDownloadRequest *)request
                                                     taskItem:(DownloadTaskItem *)taskItem
                                                     progress:(nullable void(^)(NSProgress *))progress
                                                   completion:(nullable ModDownloadHandler)completion {
    NSString *taskId = taskItem.taskId;
    __weak typeof(self) weakSelf = self;

    [self.downloadStateLock lock];
    NSInteger generation = [self.downloadGenerations[taskId] integerValue] + 1;
    self.downloadGenerations[taskId] = @(generation);
    self.downloadTaskItems[taskId] = taskItem;
    self.downloadRequests[taskId] = request;
    if (progress) self.downloadProgressHandlers[taskId] = progress;
    if (completion) self.downloadCompletionHandlers[taskId] = completion;
    // 重发从头下载：归零累计（PLDownloadClient 的负 delta 回退语义在单次 operation 内自洽）
    self.downloadAccumulatedBytes[taskId] = @(0);
    self.downloadTotalBytes[taskId] = @(-1);
    self.downloadLastSpeeds[taskId] = @(0.0);
    [self.downloadStateLock unlock];

    PLDownloadOperation *operation = [[PLDownloadClient sharedClient] startRequest:request
                                                                          progress:^(int64_t deltaBytes, int64_t totalExpectedBytes) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadDelta:deltaBytes total:totalExpectedBytes taskId:taskId generation:generation];
    }
                                                                             speed:^(int64_t bytesPerSecond) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadSpeed:bytesPerSecond taskId:taskId generation:generation];
    }
                                                                        completion:^(BOOL success, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePLDownloadCompletion:success error:error taskId:taskId generation:generation];
    }];
    if (!operation) {
        // 参数错误：PLDownloadClient 会异步回调 completion（error），由统一失败路径收尾
        return nil;
    }

    [self.downloadStateLock lock];
    self.downloadOperations[taskId] = operation;
    [self.downloadStateLock unlock];

    // rawTask 为 weak 引用：operation 由 PLDownloadClient 与本 Service 共同持有，
    // DownloadTaskManager 据此对 PLDownloadOperation 做 pause/resume/cancel
    taskItem.rawTask = operation;
    // 占用并发槽位（满则由 DownloadTaskManager 自动 pauseOperation 排队）
    [[DownloadTaskManager sharedManager] setTaskWithId:taskId state:DownloadTaskStateDownloading];
    // redesign-download-ui Phase 4：单阶段任务进入下载时将阶段0 置为 Running
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                              stageAtIndex:0
                                                  status:PLTaskStageStatusRunning];
    return operation;
}

/// retryHandler 入口：复用登记的请求描述重新发起下载
- (nullable id)restartPLDownloadForTaskId:(NSString *)taskId {
    [self.downloadStateLock lock];
    PLDownloadRequest *request = self.downloadRequests[taskId];
    DownloadTaskItem *taskItem = self.downloadTaskItems[taskId];
    [self.downloadStateLock unlock];
    if (!request || !taskItem) return nil;
    return [self startPLDownloadWithRequest:request taskItem:taskItem progress:nil completion:nil];
}

/// 进度 delta 累计：负 delta（镜像切换/重试/断点失效回退）直接累加即可贴合真实进度
- (void)handlePLDownloadDelta:(int64_t)delta total:(int64_t)total taskId:(NSString *)taskId generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    int64_t accumulated = [self.downloadAccumulatedBytes[taskId] longLongValue] + delta;
    if (accumulated < 0) accumulated = 0;
    if (total > 0) self.downloadTotalBytes[taskId] = @(total);
    int64_t totalStored = [self.downloadTotalBytes[taskId] longLongValue];
    self.downloadAccumulatedBytes[taskId] = @(accumulated);
    double lastSpeed = [self.downloadLastSpeeds[taskId] doubleValue];
    void (^progressHandler)(NSProgress *) = self.downloadProgressHandlers[taskId];
    [self.downloadStateLock unlock];

    double fraction = totalStored > 0 ? (double)accumulated / (double)totalStored : -1.0;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                                 progress:fraction
                                               totalBytes:totalStored
                                          downloadedBytes:accumulated];
    // redesign-download-ui Phase 4：单阶段任务的阶段进度与任务总进度保持一致
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                              stageAtIndex:0
                                                  progress:fraction
                                                 message:nil];

    if (!progressHandler) return;

    // 构造带 throughput/ETA 的 NSProgress，供调用方（DownloadViewController）
    // 在 FCL 风格的下载进度卡片上显示速度和 ETA
    NSProgress *downloadProgress = [NSProgress progressWithTotalUnitCount:totalStored > 0 ? totalStored : -1];
    downloadProgress.completedUnitCount = accumulated;
    if (lastSpeed > 0) {
        downloadProgress.throughput = @(lastSpeed);
        if (totalStored > accumulated) {
            downloadProgress.estimatedTimeRemaining = @((double)(totalStored - accumulated) / lastSpeed);
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        progressHandler(downloadProgress);
    });
}

/// 速率采样（PLDownloadClient 每秒回调一次；结束/暂停时回调 0）
- (void)handlePLDownloadSpeed:(int64_t)bytesPerSecond taskId:(NSString *)taskId generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    self.downloadLastSpeeds[taskId] = @(bytesPerSecond);
    int64_t total = [self.downloadTotalBytes[taskId] longLongValue];
    int64_t accumulated = [self.downloadAccumulatedBytes[taskId] longLongValue];
    [self.downloadStateLock unlock];

    double eta = (bytesPerSecond > 0 && total > accumulated)
        ? (double)(total - accumulated) / (double)bytesPerSecond : 0.0;
    [[DownloadTaskManager sharedManager] updateTaskWithId:taskId
                                                    speed:(double)bytesPerSecond
                                  estimatedTimeRemaining:eta];
}

/// 完成分发：更新 DownloadTaskManager 状态并回调业务方（主线程）
- (void)handlePLDownloadCompletion:(BOOL)success
                             error:(nullable NSError *)error
                            taskId:(NSString *)taskId
                         generation:(NSInteger)generation {
    [self.downloadStateLock lock];
    if ([self.downloadGenerations[taskId] integerValue] != generation) {
        [self.downloadStateLock unlock];
        return;
    }
    ModDownloadHandler completion = self.downloadCompletionHandlers[taskId];
    // Task267：taskItem 在 cleanup 中被移除，落点记录需在清理前捕获
    DownloadTaskItem *ame267_item = self.downloadTaskItems[taskId];
    // ★ Task268（scan-d #1）：失败/取消保留 request+taskItem——retryHandler
    //   →restartPLDownloadForTaskId 靠 downloadRequests 命中，旧版一律清空
    //   = "重试"恒 nil → 任务永久卡"等待中"。成功路径才全量清理。
    if (success) {
        [self cleanupPLDownloadStateForTaskId:taskId];
    } else {
        [self.downloadOperations removeObjectForKey:taskId];
        [self.downloadGenerations removeObjectForKey:taskId];
        [self.downloadAccumulatedBytes removeObjectForKey:taskId];
        [self.downloadTotalBytes removeObjectForKey:taskId];
        [self.downloadLastSpeeds removeObjectForKey:taskId];
        [self.downloadProgressHandlers removeObjectForKey:taskId];
        [self.downloadCompletionHandlers removeObjectForKey:taskId];
    }
    [self.downloadStateLock unlock];

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    if (success) {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusCompleted];
        [manager setTaskWithId:taskId state:DownloadTaskStateCompleted];
        // Task267：成功落盘才记入“最近 mod 下载落点”（模组管理页对账数据源）
        if ([ame267_item.resourceType isEqualToString:DownloadTaskResourceTypeMod]) {
            [ModService ame267_noteLastModDownloadToProfile:ame267_item.targetProfileName
                                                       file:(ame267_item.resourceName.length > 0 ? ame267_item.resourceName : ame267_item.displayName)]; // Task268：记实际落盘文件名（scan-d #7）
        }
    } else if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        // 用户取消（DownloadTaskManager 已置 Cancelled，这里幂等对齐）
        // ★ Task268（scan-d #8）：阶段行同步置 Skipped——旧版停在 Running，
        //   统一进度页显示"进行中"直到页面关闭。
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusSkipped];
        [manager setTaskWithId:taskId state:DownloadTaskStateCancelled];
    } else {
        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusFailed];
        [manager updateTaskWithId:taskId error:error];
        [manager setTaskWithId:taskId state:DownloadTaskStateFailed];
    }

    if (completion) {
        NSError *capturedError = success ? nil : error;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(capturedError);
        });
    }
}

/// 清理指定任务的全部跟踪状态（须在 downloadStateLock 内调用）
- (void)cleanupPLDownloadStateForTaskId:(NSString *)taskId {
    [self.downloadTaskItems removeObjectForKey:taskId];
    [self.downloadOperations removeObjectForKey:taskId];
    [self.downloadGenerations removeObjectForKey:taskId];
    [self.downloadAccumulatedBytes removeObjectForKey:taskId];
    [self.downloadTotalBytes removeObjectForKey:taskId];
    [self.downloadLastSpeeds removeObjectForKey:taskId];
    [self.downloadRequests removeObjectForKey:taskId];
    [self.downloadProgressHandlers removeObjectForKey:taskId];
    [self.downloadCompletionHandlers removeObjectForKey:taskId];
}

@end