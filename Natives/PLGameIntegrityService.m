//
//  PLGameIntegrityService.m
//  Amethyst (Prisma)
//
//  ★Task428：游戏完整性校验与补全服务实现（PDF v5 §3.3，HMCL checkGameState 对标）。
//
//  闭环语义（对齐 HMCL checkGameState：校验 → 分类 → 修复 → 复检 → 报告）：
//   · 校验对象（版本 JSON 解析含 inheritsFrom 链，Task225/ame158 同源口径）：
//       - 版本 jar   versions/<id>/<id>.jar（Tools.java generateLaunchClassPath
//                    尾项 / tweakVersionJson client 伪库 path 同约定）
//       - libraries  逐条（ame158 闸门同款跳过名单：LWJGL 自带/text2speech/
//                    jna:platform/twitch/skip/rules 不许/无 path/含 ".."）
//       - assets     索引 json + 索引内 objects（抽样或全量，模式决定）
//   · 两档模式：
//       - quick（常规启动）：存在性级（缺失/0 字节），assets 抽样 ≤64；
//       - full（上次会话异常退出自动升级，或手动交互入口）：SHA-1 级，
//         启动档 assets 抽样 ≤300（20s 预算内可控；交互档全量无上限）。
//   · 上次异常退出判定（Task251/306 同族，selfexit 命名语义）：
//       $POJAV_HOME/ame428_selfexit.marker 由 JavaLauncher 启动链立桩
//      （JLI_Launch 前）＋ JVM 有序返回时清除；判定时若存在 mtime ≥
//       marker ts 的 latestlog.selfexit-*.txt（PatchSVC shutdown hook 在
//       Java exit 前落盘）则视为正常退出（System.exit 路径进程被
//       _exit(0)，立桩方无法回收，由快照兜底）。marker 残留且无新快照
//      = 上次异常退出 → 本次升级全量 SHA-1 级。
//   · 修复：全部走 PLDownloadClient（仓内统一下载基建：镜像候选链 +
//     SHA1 校验 + 原子落盘 + 增量零流量），不另起炉灶。jar/library 走
//     GameFile 候选链（PLMirrorCenter：Mojang 系 → BMCLAPI），assets 复用
//     Task225 官方两段式 URL + BMCLAPI 回退语义（候选链统一实现）。
//   · 启动档预算 20s（kAme428LaunchBudgetSeconds）；超时/失败只记日志不
//     阻断启动（在途下载继续落盘，下轮启动自然命中增量）。
//   · 交互档自包含：遮罩 + 卡片（标题/状态/进度条/取消），结束弹
//     缺失/损坏/修复三类清单 + 完整报告写 POJAV_HOME/game_integrity_report.txt。
//
//  红线：iOS 14.0+（零 iOS15+ API）；类扩展 ivar 直用（无 self. 属性语法）；
//  用户可见文案全部经 localize 的 ame428.verify.* 键（键清单见
//  scripts/task428_i18n_B.json）；日志前缀 [Integrity] Task428。
//

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

#import "PLGameIntegrityService.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "PLMirrorCenter.h"
#import "PLDownloadClient.h"
#import "MinecraftResourceUtils.h"
#import "ZL2Theme.h"

// ★Task429：PLProfiles 新增类方法的本地前置声明（PLProfiles.h 不在任务
//   授权文件清单内，分类声明 = 零 .h 侵入；签名与 PLProfiles.m 实现逐一
//   对应，勿漂移。ZL2VersionsViewController/ZL2SettingPages 同判例）。
//   仅用于报告文件的 profile 维度字段（有效隔离态），纯读零副作用。
@interface PLProfiles (Ame429Task429)
+ (NSInteger)ame428_effectiveIsolationForVid:(NSString *)vid profile:(NSDictionary *)profile;
@end

// ★Task428：与 JavaLauncher.m 的立桩/清除共用同一文件名与首行格式
// （"ts=<epoch>\n"）。改动须两侧同步。
static NSString *const kAme428SelfExitMarkerName = @"ame428_selfexit.marker";
/// 启动档修复总预算（秒）——对齐 Task225 heal 的 20s 口径
static const NSTimeInterval kAme428LaunchBudgetSeconds = 20.0;
/// 启动档 quick 模式 assets 抽样上限
static const NSUInteger kAme428QuickAssetSampleCap = 64;
/// 启动档 full 模式 assets 抽样上限（SHA-1 级，20s 预算内的经验安全界）
static const NSUInteger kAme428FullAssetSampleCap = 300;
/// 交互档修复并发度（PLDownloadClient 单 host 并发充裕，4 为保守值）
static const NSUInteger kAme428RepairBatchSize = 4;
/// 弹窗各分类清单展示上限（报告文件内为全量）
static const NSUInteger kAme428ListShowCap = 8;
/// ★Task429 N4b：交互档批次修复等待轮询步进（秒）
static const NSTimeInterval kAme428RepairWaitPollStepSeconds = 0.2;
/// ★Task429 N4b：交互档批次修复等待总上界（秒）= 修复预算 20s 口径 + 余量
///   （40s；单批 ≤4 条并发下载，PLDownloadClient 内部自带退避重试，
///   60s 内无一批收口 = completion 丢失/悬挂，按已回源渲染部分结果）
static const NSTimeInterval kAme428InteractiveRepairWaitCapSeconds =
    kAme428LaunchBudgetSeconds + 40.0;

#pragma mark - 文件级工具函数

/// POJAV_HOME（可为 nil；调用方自行兜底）
static NSString *Ame428Home(void) {
    const char *c = getenv("POJAV_HOME");
    if (!c || !*c) return nil;
    return [NSString stringWithUTF8String:c];
}

/// POJAV_GAME_DIR（可为 nil）
static NSString *Ame428GameDir(void) {
    const char *c = getenv("POJAV_GAME_DIR");
    if (!c || !*c) return nil;
    return [NSString stringWithUTF8String:c];
}

/// 流式 SHA-1（任意大文件；PLDownloadClient.m 同款实现语义）
static NSString *_Nullable Ame428SHA1HexForFile(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    @try {
        for (;;) {
            NSData *chunk = [handle readDataOfLength:256 * 1024];
            if (chunk.length == 0) break;
            CC_SHA1_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    } @catch (NSException *e) {
        [handle closeFile];
        return nil;
    }
    [handle closeFile];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex copy];
}

/// 判定上次游戏会话是否异常退出（Task251/306 同族，selfexit 命名语义）。
/// 依据：$POJAV_HOME/ame428_selfexit.marker（JavaLauncher 立桩/清除）；
/// 若存在 mtime ≥ marker ts 的 latestlog.selfexit-*.txt（PatchSVC
/// shutdown hook 在 Java exit 前落盘）→ 走过 shutdown hook = 有序退出，
/// 视为正常并顺手消费 marker（读后即清，幂等）。
static BOOL Ame428LastSessionEndedAbnormally(void) {
    NSString *home = Ame428Home();
    if (home.length == 0) return NO;
    NSString *markerPath = [home stringByAppendingPathComponent:kAme428SelfExitMarkerName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:markerPath]) return NO;

    // 读 ts（首行 "ts=<epoch>"；解析失败按 0 = 接受任何 selfexit 快照）
    long long ts = 0;
    NSString *content = [NSString stringWithContentsOfFile:markerPath
                                              encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"ts="]) {
            ts = [line substringFromIndex:3].longLongValue;
            break;
        }
    }
    NSDate *armDate = ts > 0 ? [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)ts] : nil;

    // 扫 latestlog.selfexit-*.txt：mtime 晚于立桩时刻 → 有序退出
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:home error:nil];
    for (NSString *name in entries) {
        if (![name hasPrefix:@"latestlog.selfexit-"] || ![name hasSuffix:@".txt"]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:[home stringByAppendingPathComponent:name]
                                                   error:nil];
        NSDate *mtime = attrs.fileModificationDate;
        if (armDate && mtime && [mtime compare:armDate] != NSOrderedAscending) {
            NSLog(@"[Integrity] Task428: last session orderly (selfexit snapshot %@ newer than marker ts=%lld) -- quick tier this launch", name, ts);
            [fm removeItemAtPath:markerPath error:nil]; // 读后即清：下次不再重复感知
            return NO;
        }
    }
    NSLog(@"[Integrity] Task428: last session ended ABNORMALLY (marker residue, no fresh selfexit snapshot) -- upgrading to full SHA-1 tier");
    return YES;
}

#pragma mark - 内部数据模型

/// 单个待检/待修文件条目
@interface Ame428CheckItem : NSObject
@property (nonatomic, copy) NSString *kind;            // jar / library / assetIndex / asset
@property (nonatomic, copy) NSString *absPath;         // 磁盘绝对路径
@property (nonatomic, copy) NSString *display;         // 报告用相对路径
@property (nonatomic, copy, nullable) NSString *sha1;  // 期望 SHA-1（nil = 无元数据）
@property (nonatomic, copy, nullable) NSString *url;   // 修复下载 URL（官方原始）
@end
@implementation Ame428CheckItem
@end

/// 校验结果分类
typedef NS_ENUM(NSInteger, Ame428ItemState) {
    Ame428ItemStateOK = 0,
    Ame428ItemStateMissing,   // 不存在
    Ame428ItemStateCorrupt,   // 存在但 0 字节 / SHA 不匹配
};

/// 校验上下文（一次解析，两种模式共用）
@interface Ame428Context : NSObject
@property (nonatomic, copy) NSString *profileName;
@property (nonatomic, copy) NSString *versionId;
@property (nonatomic, copy) NSString *versionRoot;   // versions/<id> 所在根
@property (nonatomic, copy) NSString *gameRoot;      // libraries/assets 所在根（POJAV_GAME_DIR）
@property (nonatomic, strong) NSDictionary *mergedJson; // 含继承链合并 + __libs 汇总
// ★Task429：profile 维度字段（报告文件追加项）
@property (nonatomic, copy) NSString *gameDirRaw;       // profile 原始 gameDir（缺失/空 = "."）
@property (nonatomic, assign) NSInteger isolationEffective; // A 层有效隔离（-1=自定义/0=共享/1=隔离）
@end
@implementation Ame428Context
@end

@interface PLGameIntegrityService () {
    /// 交互流程重入保护（仅主线程读写）
    BOOL _interactiveRunning;
    /// 活动交互流程的取消令牌（单实例单流程）
    /// ★Task429 N4a（第六版报告）：原 NSMutableArray 主线程写/后台轮询读
    ///   非线程安全（NSMutableArray 非线程安全容器）→ NSLock 保护读写全路径
    ///   收口（写读只经 ame429_setCancelFlag:/ame429_cancelRequested，裸容器
    ///   不再直触；锁与令牌在主线程同帧创建，dispatch_async 发布 = happens-before）
    NSMutableArray *_activeCancelToken;
    NSLock *_cancelTokenLock;
    /// 交互流程取消按钮（直持身份，零 viewWithTag）
    UIButton *_activeCancelButton;
}
@end

@implementation PLGameIntegrityService

#pragma mark - 单例

+ (instancetype)sharedService {
    static PLGameIntegrityService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PLGameIntegrityService alloc] init];
    });
    return shared;
}

#pragma mark - 上下文解析

/// 解析指定 profile 的校验上下文；任一环节失败返回 nil（调用方 fail-open 放行）。
/// ★Task429（实例级化）：profileName 为空 = 全局当前档（旧调用兼容，逐位
///   等价）；非空 = 该 profile 附属实例，解析口径与 PLProfiles/实例隔离一致：
///   ① 注册表字典键直查（PLProfiles.current.profiles，只读）；
///   ② 版本根 = ame353 自洽根（ame353_versionRootForProfileName:——gameDir
///      展开点祖先链探测，A 层 gameDir 各形态全覆盖：A1 缺失/"."→当前实例
///      根、A2 versions/<vid>→实例自根、A3 绝对/相对自定义→展开点祖先链）；
///   ③ libraries/assets 根 = ②的自洽根 R（对齐启动链：ZL2Home Ame353 对齐点
///      启动期把 POJAV_GAME_DIR setenv 到 R，MRDT 校验链把 libraries/assets
///      补进 R = 版本隔离安装语义闭环。旧实现读 env：当前档 A1/A2 常态下
///      R == env 逐位等价（零回归）；跨实例/深层根形态 R ≠ env 时旧口径会
///      扫错实例的库/资产——本口径为启动链同根修正，属任务要求的
///      "与实例隔离一致的 gameDir 解析链"）。
- (nullable Ame428Context *)ame428_resolveContextForProfileName:(NSString *)profileName {
    @autoreleasepool {
        // ★Task429：nil/空 = 当前档（旧调用兼容）；非空 = 指定实例字典键
        NSString *resolvedProfile = profileName.length > 0 ? profileName : PLProfiles.current.selectedProfileName;
        if (resolvedProfile.length == 0) return nil;
        NSDictionary *profile = [PLProfiles.current.profiles objectForKey:resolvedProfile];
        NSString *versionId = nil;
        if ([profile isKindOfClass:[NSDictionary class]] &&
            [profile[@"lastVersionId"] isKindOfClass:[NSString class]]) {
            versionId = profile[@"lastVersionId"];
        }
        if (versionId.length == 0) return nil;

        // 版本根：优先 ame353（Task353 profile 自洽根，深层实例形态正确）；
        // 缺席时回退 POJAV_GAME_DIR（Task225/ame158 同源口径）。
        NSString *versionRoot = [PLProfiles ame353_versionRootForProfileName:resolvedProfile];
        if (versionRoot.length == 0) versionRoot = Ame428GameDir();
        if (versionRoot.length == 0) return nil;
        // ★Task429：gameRoot 口径对齐启动链（注释详见方法头 ③）。
        //   ame353 未命中回退 env 时，下方版本 JSON 校验即失败返回 nil，
        //   gameRoot 不可达——此处 versionRoot 恒为启动链同根 R。
        NSString *gameRoot = versionRoot;

        // 版本 JSON（含 inheritsFrom 链：chain = [子, 父, 祖父...]）
        NSString *jsonPath = [[versionRoot stringByAppendingPathComponent:@"versions"]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.json", versionId, versionId]];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:jsonPath] options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[Integrity] Task428: version JSON unreadable (%@) -- fail-open", jsonPath);
            return nil;
        }
        NSMutableArray<NSDictionary *> *chain = [NSMutableArray array];
        [chain addObject:json];
        NSString *cursor = [json[@"inheritsFrom"] isKindOfClass:[NSString class]] ? json[@"inheritsFrom"] : nil;
        NSInteger guardCount = 0;
        while (cursor.length > 0 && guardCount++ < 8) {
            NSString *parentPath = [[versionRoot stringByAppendingPathComponent:@"versions"]
                stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.json", cursor, cursor]];
            NSDictionary *parent = [NSJSONSerialization JSONObjectWithData:
                [NSData dataWithContentsOfFile:parentPath] options:0 error:nil];
            if (![parent isKindOfClass:[NSDictionary class]]) {
                NSLog(@"[Integrity] Task428: inheritsFrom parent JSON unreadable (%@) -- chain truncated at %@", parentPath, cursor);
                break;
            }
            [chain addObject:parent];
            cursor = [parent[@"inheritsFrom"] isKindOfClass:[NSString class]] ? parent[@"inheritsFrom"] : nil;
        }

        // 库合并：从最父辈向子辈收敛，子辈同组覆盖（processVersion 同语义；
        // 组键 = name 的 groupId:artifactId 段，存 __group 书签键不参与落盘）
        NSMutableArray<NSMutableDictionary *> *libs = [NSMutableArray array];
        for (NSInteger i = (NSInteger)chain.count - 1; i >= 0; i--) {
            NSArray *arr = [chain[i][@"libraries"] isKindOfClass:[NSArray class]] ? chain[i][@"libraries"] : nil;
            if (!arr) continue;
            for (NSDictionary *lib in arr) {
                if (![lib isKindOfClass:[NSDictionary class]]) continue;
                NSString *name = [lib[@"name"] isKindOfClass:[NSString class]] ? lib[@"name"] : nil;
                if (name.length == 0) continue;
                NSRange colon = [name rangeOfString:@":" options:NSBackwardsSearch];
                if (colon.location == NSNotFound || colon.location == 0) continue;
                NSString *group = [name substringToIndex:colon.location];
                BOOL replaced = NO;
                for (NSMutableDictionary *existing in libs) {
                    if ([existing[@"__group"] isEqualToString:group]) {
                        NSMutableDictionary *m = [lib mutableCopy];
                        m[@"__group"] = group;
                        [libs replaceObjectAtIndex:[libs indexOfObject:existing] withObject:m];
                        replaced = YES;
                        break;
                    }
                }
                if (!replaced) {
                    NSMutableDictionary *m = [lib mutableCopy];
                    m[@"__group"] = group;
                    [libs addObject:m];
                }
            }
        }

        // 合并 JSON：子优先；子缺的键（assetIndex/assets/downloads）回退父链
        NSMutableDictionary *merged = [chain.firstObject mutableCopy];
        for (NSString *key in @[@"assetIndex", @"assets", @"downloads"]) {
            if (merged[key] == nil) {
                for (NSInteger i = 1; i < (NSInteger)chain.count; i++) {
                    if (chain[i][key] != nil) { merged[key] = chain[i][key]; break; }
                }
            }
        }
        merged[@"__libs"] = libs;

        Ame428Context *ctx = [[Ame428Context alloc] init];
        ctx.profileName = resolvedProfile;
        ctx.versionId = versionId;
        ctx.versionRoot = versionRoot;
        ctx.gameRoot = gameRoot;
        ctx.mergedJson = merged;
        // ★Task429：profile 维度字段（原始 gameDir + A 层有效隔离，报告用）
        NSString *rawGameDir = [profile[@"gameDir"] isKindOfClass:[NSString class]]
            ? profile[@"gameDir"] : nil;
        ctx.gameDirRaw = rawGameDir.length > 0 ? rawGameDir : @".";
        ctx.isolationEffective = [PLProfiles ame428_effectiveIsolationForVid:versionId
                                                                    profile:profile];
        return ctx;
    }
}

#pragma mark - 清单构建

/// 版本 client jar 元数据（沿继承链子优先；无 downloads.client 时为 nil）
- (nullable NSDictionary *)ame428_clientArtifactForContext:(Ame428Context *)ctx {
    NSDictionary *downloads = [ctx.mergedJson[@"downloads"] isKindOfClass:[NSDictionary class]]
        ? ctx.mergedJson[@"downloads"] : nil;
    NSDictionary *client = ([downloads isKindOfClass:[NSDictionary class]] &&
                            [downloads[@"client"] isKindOfClass:[NSDictionary class]])
        ? downloads[@"client"] : nil;
    if ([client isKindOfClass:[NSDictionary class]] &&
        [client[@"url"] isKindOfClass:[NSString class]] && ((NSString *)client[@"url"]).length > 0) {
        return client;
    }
    return nil;
}

/// assets 索引 id（"assets" 字段或 assetIndex.id；Task225 同口径）
- (nullable NSString *)ame428_assetIndexIdForContext:(Ame428Context *)ctx {
    id assets = ctx.mergedJson[@"assets"];
    if ([assets isKindOfClass:[NSString class]] && [(NSString *)assets length] > 0) return assets;
    id idx = ctx.mergedJson[@"assetIndex"];
    if ([idx isKindOfClass:[NSDictionary class]] && [idx[@"id"] isKindOfClass:[NSString class]]) {
        return idx[@"id"];
    }
    return nil;
}

/// 构建待检条目清单。
/// fullAssets=YES → 索引内 objects 全量；否则确定性抽样（键排序后取前 sampleCap 条）。
- (NSArray<Ame428CheckItem *> *)ame428_buildItemsForContext:(Ame428Context *)ctx
                                                 fullAssets:(BOOL)fullAssets
                                                  sampleCap:(NSUInteger)sampleCap {
    NSMutableArray<Ame428CheckItem *> *items = [NSMutableArray array];

    // 1) 版本 jar：versions/<id>/<id>.jar（Tools.java classpath 尾项同约定）
    {
        NSDictionary *client = [self ame428_clientArtifactForContext:ctx];
        if (client) {
            Ame428CheckItem *item = [[Ame428CheckItem alloc] init];
            item.kind = @"jar";
            item.absPath = [[ctx.versionRoot stringByAppendingPathComponent:@"versions"]
                stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.jar", ctx.versionId, ctx.versionId]];
            item.display = [NSString stringWithFormat:@"versions/%@/%@.jar", ctx.versionId, ctx.versionId];
            item.sha1 = [client[@"sha1"] isKindOfClass:[NSString class]] ? client[@"sha1"] : nil;
            item.url = [client[@"url"] isKindOfClass:[NSString class]] ? client[@"url"] : nil;
            [items addObject:item];
        } else {
            NSLog(@"[Integrity] Task428: no downloads.client in version JSON chain -- jar tier skipped (该谱系 client jar 由安装链负责)");
        }
    }

    // 2) libraries：ame158 闸门同款跳过名单
    NSArray *libs = [ctx.mergedJson[@"__libs"] isKindOfClass:[NSArray class]] ? ctx.mergedJson[@"__libs"] : nil;
    for (NSDictionary *lib in libs) {
        if (![lib isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = [lib[@"name"] isKindOfClass:[NSString class]] ? lib[@"name"] : nil;
        if (name.length == 0) continue;
        if ([name hasPrefix:@"org.lwjgl:"] ||              // iOS 自带 LWJGL（ame158 同款名单）
            [name hasPrefix:@"com.mojang:text2speech"] ||   // mojang-stubs 桩提供
            [name hasPrefix:@"net.java.dev.jna:platform:"] ||
            [name hasPrefix:@"tv.twitch"]) {
            continue;
        }
        if ([lib[@"skip"] boolValue]) continue;             // tweakVersionJson 伪条目（含 client）
        id rules = lib[@"rules"];
        if ([rules isKindOfClass:[NSArray class]] && [(NSArray *)rules count] > 0 &&
            ![MinecraftResourceUtils evaluateRules:(NSArray *)rules]) {
            continue;                                       // OS 规则不许（iOS 视作 osx）
        }
        NSDictionary *downloads = [lib[@"downloads"] isKindOfClass:[NSDictionary class]] ? lib[@"downloads"] : nil;
        NSDictionary *artifact = ([downloads isKindOfClass:[NSDictionary class]] &&
                                  [downloads[@"artifact"] isKindOfClass:[NSDictionary class]])
            ? downloads[@"artifact"] : nil;
        NSString *rel = [artifact[@"path"] isKindOfClass:[NSString class]] ? artifact[@"path"] : nil;
        if (rel && [rel containsString:@".."]) continue;    // 越界条目不归本闸门（ame158 同款）
        // Forge 风格（无 artifact.path）：按 name 推导（downloadClientLibraries 同款）
        if (!rel && [name containsString:@":"]) {
            NSArray *parts = [name componentsSeparatedByString:@":"];
            if (parts.count >= 3) {
                rel = [NSString stringWithFormat:@"%1$@/%2$@/%3$@/%2$@-%3$@.jar",
                    [parts[0] stringByReplacingOccurrencesOfString:@"." withString:@"/"], parts[1], parts[2]];
            }
        }
        if (rel.length == 0) continue;
        Ame428CheckItem *item = [[Ame428CheckItem alloc] init];
        item.kind = @"library";
        item.absPath = [[ctx.gameRoot stringByAppendingPathComponent:@"libraries"] stringByAppendingPathComponent:rel];
        item.display = [@"libraries/" stringByAppendingString:rel];
        item.sha1 = [artifact[@"sha1"] isKindOfClass:[NSString class]] ? artifact[@"sha1"] : nil;
        item.url = [artifact[@"url"] isKindOfClass:[NSString class]] ? artifact[@"url"] : nil;
        if (item.url.length == 0) {
            // 无官方 URL：库根字段或 Mojang maven 兜底（Forge 风格安装链同源）
            // ★Task428-r1：id 下标 .length 点语法不可编译——显式转修
            NSString *libBase = ([lib[@"url"] isKindOfClass:[NSString class]] && ((NSString *)lib[@"url"]).length > 0)
                ? [lib[@"url"] stringByReplacingOccurrencesOfString:@"http://" withString:@"https://"]
                : @"https://libraries.minecraft.net/";
            item.url = [NSString stringWithFormat:@"%@%@", libBase, rel];
        }
        [items addObject:item];
    }

    // 3) assets 索引 + objects（Task225 同源布局：gameRoot/assets/...）
    NSString *indexId = [self ame428_assetIndexIdForContext:ctx];
    if (indexId.length > 0) {
        id idxMeta = [ctx.mergedJson[@"assetIndex"] isKindOfClass:[NSDictionary class]]
            ? ctx.mergedJson[@"assetIndex"] : nil;
        Ame428CheckItem *idxItem = [[Ame428CheckItem alloc] init];
        idxItem.kind = @"assetIndex";
        idxItem.absPath = [[ctx.gameRoot stringByAppendingPathComponent:@"assets/indexes"]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", indexId]];
        idxItem.display = [NSString stringWithFormat:@"assets/indexes/%@.json", indexId];
        idxItem.sha1 = ([idxMeta isKindOfClass:[NSDictionary class]] &&
                        [idxMeta[@"sha1"] isKindOfClass:[NSString class]]) ? idxMeta[@"sha1"] : nil;
        idxItem.url = ([idxMeta isKindOfClass:[NSDictionary class]] &&
                       [idxMeta[@"url"] isKindOfClass:[NSString class]]) ? idxMeta[@"url"] : nil;
        [items addObject:idxItem];

        // 索引可读 → 展开 objects（确定性抽样：键稳定排序取前 N）
        NSDictionary *indexJson = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:idxItem.absPath] options:0 error:nil];
        NSDictionary *objects = [indexJson isKindOfClass:[NSDictionary class]]
            ? [indexJson[@"objects"] isKindOfClass:[NSDictionary class]] ? indexJson[@"objects"] : nil
            : nil;
        if ([objects isKindOfClass:[NSDictionary class]] && objects.count > 0) {
            NSArray *sortedNames = [objects.allKeys sortedArrayUsingSelector:@selector(compare:)];
            NSUInteger cap = fullAssets ? sortedNames.count : MIN(sampleCap, sortedNames.count);
            for (NSUInteger i = 0; i < sortedNames.count && i < cap; i++) {
                NSString *objName = sortedNames[i];
                NSDictionary *obj = [objects[objName] isKindOfClass:[NSDictionary class]] ? objects[objName] : nil;
                NSString *hash = [obj[@"hash"] isKindOfClass:[NSString class]] ? obj[@"hash"] : nil;
                if (hash.length < 4) continue;
                Ame428CheckItem *item = [[Ame428CheckItem alloc] init];
                item.kind = @"asset";
                item.absPath = [[ctx.gameRoot stringByAppendingPathComponent:@"assets/objects"]
                    stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@", [hash substringToIndex:2], hash]];
                item.display = [NSString stringWithFormat:@"assets/objects/%@/%@ (%@)",
                    [hash substringToIndex:2], hash, objName];
                item.sha1 = hash; // assets objects 的 hash 即 SHA-1
                item.url = [NSString stringWithFormat:@"https://resources.download.minecraft.net/%@/%@",
                    [hash substringToIndex:2], hash]; // Task227 官方两段式
                [items addObject:item];
            }
            if (!fullAssets && sortedNames.count > cap) {
                NSLog(@"[Integrity] Task428: assets sampled %lu/%lu (existence tier cap)", (unsigned long)cap, (unsigned long)sortedNames.count);
            }
        } else {
            NSLog(@"[Integrity] Task428: asset index unreadable (%@) -- objects tier skipped (index 条目本身已在清单，修复后下轮展开)", idxItem.display);
        }
    }
    return items;
}

#pragma mark - 单条校验

- (Ame428ItemState)ame428_checkItem:(Ame428CheckItem *)item fullSha1:(BOOL)fullSha1 {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:item.absPath error:nil];
    if (!attrs) return Ame428ItemStateMissing;
    if ([attrs fileSize] == 0) return Ame428ItemStateCorrupt; // 0 字节按损坏（checkSHA 关档同口径）
    if (fullSha1 && item.sha1.length > 0) {
        NSString *actual = Ame428SHA1HexForFile(item.absPath);
        if (!actual) return Ame428ItemStateCorrupt;
        if (![actual.lowercaseString isEqualToString:item.sha1.lowercaseString]) {
            return Ame428ItemStateCorrupt;
        }
    }
    return Ame428ItemStateOK;
}

#pragma mark - 修复（PLDownloadClient 现有基建）

/// 单条修复：走 PLDownloadClient（镜像候选链 + SHA1 校验 + 原子落盘 +
/// 已存在且校验通过时零流量增量）。completion 恰好回调一次（后台线程）。
- (void)ame428_repairItem:(Ame428CheckItem *)item
               completion:(void (^)(BOOL repaired, NSError *_Nullable error))completion {
    if (item.url.length == 0) {
        NSLog(@"[Integrity] Task428: no download URL for %@ -- cannot repair", item.display);
        completion(NO, nil);
        return;
    }
    NSURL *original = [NSURL URLWithString:item.url];
    if (!original) {
        NSLog(@"[Integrity] Task428: malformed URL for %@ (%@)", item.display, item.url);
        completion(NO, nil);
        return;
    }
    PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
    request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:original
                                                     resourceType:PLMirrorResourceTypeGameFile];
    request.expectedSHA1 = item.sha1;
    request.destinationPath = item.absPath;
    request.taskIdentifier = [@"ame428|" stringByAppendingString:item.absPath]; // 稳定断点续传键
    request.allowZipFallbackCheck = [item.absPath.pathExtension.lowercaseString isEqualToString:@"jar"];
    [[PLDownloadClient sharedClient] startRequest:request
                                         progress:nil
                                            speed:nil
                                      completion:^(BOOL success, NSError *_Nullable error) {
        // ★Task428：与 [MCDL]/[AssetsHeal] 同风格；回调线程为 client 内部队列
        NSLog(@"[Integrity] Task428: repair %@ -> %@ (%@)",
              item.display, success ? @"OK" : @"FAILED",
              error.localizedDescription ?: (success ? @"incremental/zero-traffic" : @"no-url"));
        completion(success, error);
    }];
}

/// 启动档修复：串行 + 全局预算；预算耗尽才停止发起新下载（在途的继续落盘）。
- (void)ame428_repairSequentialWithDeadline:(NSArray<Ame428CheckItem *> *)items
                                   deadline:(NSDate *)deadline {
    NSUInteger done = 0;
    for (Ame428CheckItem *item in items) {
        // ★Task429 N1（第六版报告）：原写法 `== NSOrderedDescending` 语义写反——
        //   deadline 晚于当前 = 预算还剩却 break → 启动档自动补全首轮即退出，
        //   整个修复循环成死代码。修法：预算耗尽（deadline 不晚于当前，即
        //   NSOrderedAscending 或 NSOrderedSame）才 break；预算还剩
        //   （NSOrderedDescending）继续发起新下载。
        NSInteger ame429_budgetCmp = [deadline compare:[NSDate date]];
        if (ame429_budgetCmp == NSOrderedAscending || ame429_budgetCmp == NSOrderedSame) {
            NSUInteger remaining = items.count - done;
            if (remaining > 0) {
                NSLog(@"[Integrity] Task428: repair budget exhausted (%lu/%lu done, %lu deferred to next launch)",
                      (unsigned long)done, (unsigned long)items.count, (unsigned long)remaining);
            }
            break;
        }
        __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self ame428_repairItem:item completion:^(BOOL repaired, NSError *_Nullable error) {
            dispatch_semaphore_signal(sem);
        }];
        // 每条最多等到剩余预算（PLDownloadClient 内部自带 3 次/候选退避重试）
        NSTimeInterval remain = [deadline timeIntervalSinceNow];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(remain > 0 ? remain : 0) * NSEC_PER_SEC + NSEC_PER_SEC));
        done++;
    }
}

#pragma mark - 启动档入口（契约 API）

- (void)preLaunchCheckForCurrentProfile:(void (^)(BOOL, NSDictionary<NSString *, id> * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *report = nil;
        @autoreleasepool {
            // ★Task429：启动档恒为全局当前档语义（nil = selectedProfileName）
            Ame428Context *ctx = [self ame428_resolveContextForProfileName:nil];
            if (!ctx) {
                // fail-open：无从校验不阻断启动（Task225 "老版本/异常 JSON" 同语义）
                report = @{ @"ok": @YES,
                            @"missing": @[],
                            @"checked": @(0),
                            @"profile": (PLProfiles.current.selectedProfileName ?: @"") };
                NSLog(@"[Integrity] Task428: context unresolvable -- fail-open (checked=0)");
            } else {
                BOOL fullSha1 = Ame428LastSessionEndedAbnormally(); // 异常退出 → 全量 SHA-1 级
                NSArray<Ame428CheckItem *> *items = [self ame428_buildItemsForContext:ctx
                    fullAssets:NO
                    sampleCap:fullSha1 ? kAme428FullAssetSampleCap : kAme428QuickAssetSampleCap];
                NSMutableArray<NSString *> *missingList = [NSMutableArray array];
                NSMutableArray<Ame428CheckItem *> *toRepair = [NSMutableArray array];
                for (Ame428CheckItem *item in items) {
                    Ame428ItemState st = [self ame428_checkItem:item fullSha1:fullSha1];
                    if (st == Ame428ItemStateOK) continue;
                    if (st == Ame428ItemStateMissing) {
                        [missingList addObject:item.display];
                    } else {
                        [missingList addObject:[item.display stringByAppendingString:@" (corrupt)"]];
                    }
                    [toRepair addObject:item];
                }
                NSLog(@"[Integrity] Task428: pre-launch tier=%@ checked=%lu missing=%lu (profile=%@ version=%@)",
                      fullSha1 ? @"full-sha1" : @"quick-existence",
                      (unsigned long)items.count, (unsigned long)toRepair.count,
                      ctx.profileName, ctx.versionId);
                if (toRepair.count > 0) {
                    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kAme428LaunchBudgetSeconds];
                    [self ame428_repairSequentialWithDeadline:toRepair deadline:deadline];
                    // 复检（存在性级；SHA 级复检交给下轮全量档）
                    NSUInteger stillBroken = 0;
                    NSMutableArray<NSString *> *unresolved = [NSMutableArray array];
                    for (Ame428CheckItem *item in toRepair) {
                        if ([self ame428_checkItem:item fullSha1:NO] == Ame428ItemStateOK) continue;
                        stillBroken++;
                        [unresolved addObject:item.display];
                    }
                    report = @{ @"ok": @(stillBroken == 0),
                                @"missing": [missingList copy],
                                @"checked": @(items.count),
                                @"profile": ctx.profileName };
                    if (stillBroken > 0) {
                        NSLog(@"[Integrity] Task428: %lu item(s) still broken after repair pass (deferred, non-blocking): %@",
                              (unsigned long)stillBroken, unresolved);
                    }
                } else {
                    report = @{ @"ok": @YES,
                                @"missing": @[],
                                @"checked": @(items.count),
                                @"profile": ctx.profileName };
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([report[@"ok"] boolValue], report);
        });
    });
}

#pragma mark - 交互档入口（契约 API）

- (void)runInteractiveVerifyAndRepairFromViewController:(UIViewController *)presentingVC {
    // ★Task429：thin wrapper——nil = 全局当前档（旧语义零回归，见 .h 契约注）
    [self runInteractiveVerifyAndRepairForProfile:nil fromViewController:presentingVC];
}

- (void)runInteractiveVerifyAndRepairForProfile:(NSString *)profileName
                              fromViewController:(UIViewController *)presentingVC {
    // ★Task429：实例级化——profileName 空 = 当前档；非空 = 该 profile 附属
    //   实例（ame428_resolveContextForProfileName: 同口径解析）。流程/UI/
    //   报告与旧入口完全一致，仅校验对象随参数走。
    NSString *ame429_targetProfile = profileName.length > 0 ? [profileName copy] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_interactiveRunning || !presentingVC.view) {
            NSLog(@"[Integrity] Task428: interactive run busy / no host view -- ignored (profile=%@)",
                  ame429_targetProfile ?: @"<current>");
            return;
        }
        _interactiveRunning = YES;

        // ---- 自包含遮罩 + 进度卡片（iOS14 安全控件；ZL2Theme 动态令牌）----
        UIView *hostView = presentingVC.view;
        UIView *dim = [[UIView alloc] init];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        dim.frame = hostView.bounds;
        dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [ZL2Theme surfaceContainerHigh];
        card.layer.cornerRadius = [ZL2Theme radiusL];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = localize(@"ame428.verify.title", nil);
        titleLabel.font = [ZL2Theme fontTitleMedium];
        titleLabel.textColor = [ZL2Theme onSurface];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *statusLabel = [[UILabel alloc] init];
        statusLabel.text = localize(@"ame428.verify.phase_verify", nil);
        statusLabel.font = [ZL2Theme fontBodyMedium];
        statusLabel.textColor = [ZL2Theme onSurfaceVariant];
        statusLabel.numberOfLines = 2;
        statusLabel.textAlignment = NSTextAlignmentCenter;
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        bar.progress = 0;
        bar.progressTintColor = accentColor();
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [cancelBtn setTitle:localize(@"resman.common.cancel", nil) forState:UIControlStateNormal];
        cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [dim addSubview:card];
        [card addSubview:titleLabel];
        [card addSubview:statusLabel];
        [card addSubview:bar];
        [card addSubview:cancelBtn];
        [hostView addSubview:dim];
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:dim.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:dim.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:300],
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
            [titleLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [statusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
            [statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [bar.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor constant:16],
            [bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
            [bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
            [cancelBtn.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:16],
            [cancelBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [cancelBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        ]];

        // 取消令牌：主线程写 / 后台轮询——★Task429 N4a：读写全部收口到
        //   ame429_setCancelFlag:/ame429_cancelRequested（NSLock 保护），
        //   本地局部变量退役，后台轮询一律走访问器。
        _cancelTokenLock = [[NSLock alloc] init];
        _activeCancelToken = [NSMutableArray arrayWithObject:@(NO)];
        _activeCancelButton = cancelBtn;
        [cancelBtn addTarget:self
                      action:@selector(ame428_cancelTapped:)
            forControlEvents:UIControlEventTouchUpInside];

        void (^updateUI)(NSString *status, double progress) = ^(NSString *status, double progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = status;
                [bar setProgress:(float)progress animated:YES];
            });
        };
        void (^teardown)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [dim removeFromSuperview];
                _interactiveRunning = NO;
                [self ame429_resetCancelToken];   // ★Task429 N4a：令牌+锁同帧收口（锁内置 nil，与后台读互斥）
                _activeCancelButton = nil;
            });
        };

        // ---- 阶段 1/2：后台校验（full SHA-1，无抽样上限）----
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            // ★Task429：校验对象 = 参数指定的 profile（nil = 当前档）
            Ame428Context *ctx = [self ame428_resolveContextForProfileName:ame429_targetProfile];
            if (!ctx) {
                teardown();
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self ame428_presentResultOnVC:presentingVC
                                             title:localize(@"ame428.verify.failed_title", nil)
                                           message:localize(@"ame428.verify.no_context", nil)];
                });
                return;
            }
            NSArray<Ame428CheckItem *> *items = [self ame428_buildItemsForContext:ctx fullAssets:YES sampleCap:0];
            NSMutableArray<Ame428CheckItem *> *missing = [NSMutableArray array];
            NSMutableArray<Ame428CheckItem *> *corrupt = [NSMutableArray array];
            NSUInteger checked = 0;
            BOOL anyIssue = NO;
            for (Ame428CheckItem *item in items) {
                if ([self ame429_cancelRequested]) break;   // ★Task429 N4a：NSLock 收口读
                Ame428ItemState st = [self ame428_checkItem:item fullSha1:YES];
                checked++;
                if (st == Ame428ItemStateMissing) { [missing addObject:item]; anyIssue = YES; }
                else if (st == Ame428ItemStateCorrupt) { [corrupt addObject:item]; anyIssue = YES; }
                if (checked % 25 == 0 || checked == items.count) {
                    updateUI([NSString stringWithFormat:localize(@"ame428.verify.progress_fmt", nil),
                              checked, items.count],
                             items.count > 0 ? (double)checked / (double)items.count : 0.0);
                }
            }
            if ([self ame429_cancelRequested]) {   // ★Task429 N4a：NSLock 收口读
                teardown();
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self ame428_presentResultOnVC:presentingVC
                                             title:localize(@"ame428.verify.title", nil)
                                           message:localize(@"ame428.verify.cancelled", nil)];
                });
                return;
            }

            // ---- 阶段 2/2：修复（批次并发；PLDownloadClient 现有队列）----
            NSMutableArray<Ame428CheckItem *> *toRepair = [NSMutableArray array];
            [toRepair addObjectsFromArray:missing];
            [toRepair addObjectsFromArray:corrupt];
            // ★Task428-r1：block 内自增/NSMutableArray add 需 __block 修饰
            //   （原裸自动变量在 repair completion block 里不可赋值 = CI 编译雷）
            __block NSUInteger repairedOK = 0;
            __block NSMutableArray<NSString *> *repairFailed = [NSMutableArray array];
            if (toRepair.count > 0) {
                updateUI(localize(@"ame428.verify.phase_repair", nil), 0.0);
                for (NSUInteger start = 0; start < toRepair.count; start += kAme428RepairBatchSize) {
                    if ([self ame429_cancelRequested]) break;   // ★Task429 N4a：NSLock 收口读
                    NSUInteger end = MIN(start + kAme428RepairBatchSize, toRepair.count);
                    dispatch_group_t group = dispatch_group_create();
                    for (NSUInteger i = start; i < end; i++) {
                        Ame428CheckItem *item = toRepair[i];
                        dispatch_group_enter(group);
                        [self ame428_repairItem:item completion:^(BOOL ok, NSError *_Nullable error) {
                            if (ok) {
                                repairedOK++;
                            } else {
                                [repairFailed addObject:item.display];
                            }
                            dispatch_group_leave(group);
                        }];
                    }
                    // ★Task429 N4b（第六版报告）：dispatch_group_wait(DISPATCH_TIME_FOREVER)
                    //   单个 completion 丢失则遮罩永久卡死。修法：200ms 步进轮询
                    //   （总上界 = 修复预算 20s + 余量 = 60s），轮询内查取消标志；
                    //   取消/超时按已回源渲染部分结果（在途 item 落盘后，下轮
                    //   启动档/交互档自然命中增量）。迟到的 leave 与 enter 仍配平，
                    //   无二次回调点（notify 未用）。
                    NSTimeInterval ame429_waited = 0;
                    while (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW,
                            (int64_t)(kAme428RepairWaitPollStepSeconds * NSEC_PER_SEC))) != 0) {
                        if ([self ame429_cancelRequested]
                            || ame429_waited >= kAme428InteractiveRepairWaitCapSeconds) {
                            NSLog(@"[Integrity] ★Task429 N4b: batch repair wait %@ at %.1fs -- render partial results (in-flight items keep landing)",
                                  [self ame429_cancelRequested] ? @"cancelled" : @"timed out",
                                  ame429_waited);
                            break;
                        }
                        ame429_waited += kAme428RepairWaitPollStepSeconds;
                    }
                    NSUInteger doneCount = end;
                    updateUI([NSString stringWithFormat:localize(@"ame428.verify.repair_progress_fmt", nil),
                              doneCount, toRepair.count],
                             toRepair.count > 0 ? (double)doneCount / (double)toRepair.count : 0.0);
                }
            }

            // ---- 报告文件 + 结果弹窗 ----
            [self ame428_writeReportFileForContext:ctx
                                          checked:checked
                                          missing:missing
                                          corrupt:corrupt
                                    repairedCount:repairedOK
                                    repairFailed:repairFailed];
            dispatch_async(dispatch_get_main_queue(), ^{
                // ★Task429 N4a：取消态先于 teardown 取值（teardown 收口后令牌
                //   置 nil，访问器将恒 NO；先读后清 = cancelled 弹窗不丢）
                BOOL ame429_cancelled = [self ame429_cancelRequested];
                teardown();
                if (ame429_cancelled) {
                    [self ame428_presentResultOnVC:presentingVC
                                             title:localize(@"ame428.verify.title", nil)
                                           message:localize(@"ame428.verify.cancelled", nil)];
                    return;
                }
                if (!anyIssue) {
                    NSLog(@"[Integrity] Task428: interactive done -- all %lu item(s) OK", (unsigned long)checked);
                    [self ame428_presentResultOnVC:presentingVC
                                             title:localize(@"ame428.verify.done_title", nil)
                                           message:localize(@"ame428.verify.all_ok", nil)];
                    return;
                }
                NSMutableString *msg = [NSMutableString stringWithFormat:localize(@"ame428.verify.summary_fmt", nil),
                                        (unsigned long)missing.count, (unsigned long)corrupt.count, repairedOK];
                [msg appendString:[self ame428_listSection:localize(@"ame428.verify.list_missing", nil)
                                                       from:missing cap:kAme428ListShowCap]];
                [msg appendString:[self ame428_listSection:localize(@"ame428.verify.list_corrupt", nil)
                                                       from:corrupt cap:kAme428ListShowCap]];
                if (repairFailed.count > 0) {
                    [msg appendFormat:@"\n%@\n", localize(@"ame428.verify.list_repair_failed", nil)];
                    NSUInteger cap = MIN(repairFailed.count, kAme428ListShowCap);
                    for (NSUInteger i = 0; i < cap; i++) [msg appendFormat:@"  • %@\n", repairFailed[i]];
                }
                NSString *home = Ame428Home();
                NSString *reportName = (home.length > 0
                    ? [home stringByAppendingPathComponent:@"game_integrity_report.txt"]
                    : @"game_integrity_report.txt").lastPathComponent;
                [msg appendFormat:@"\n%@", [NSString stringWithFormat:localize(@"ame428.verify.report_hint_fmt", nil), reportName]];
                NSLog(@"[Integrity] Task428: interactive done (checked=%lu missing=%lu corrupt=%lu repaired=%lu failed=%lu)",
                      (unsigned long)checked, (unsigned long)missing.count, (unsigned long)corrupt.count,
                      (unsigned long)repairedOK, (unsigned long)repairFailed.count);
                [self ame428_presentResultOnVC:presentingVC
                                         title:localize(@"ame428.verify.done_title", nil)
                                       message:msg.copy];
            });
        });
    });
}

/// 取消按钮动作（主线程）
- (void)ame428_cancelTapped:(id)sender {
    // ★Task429 N4a：唯一写路径经 NSLock 收口访问器（原裸 _activeCancelToken[0]
    //   写与后台轮询读并发 = NSMutableArray 数据竞争）
    [self ame429_setCancelFlag:YES];
    NSLog(@"[Integrity] Task428: interactive run cancellation requested");
}

/// ★Task429 N4a：取消令牌唯一写路径（NSLock 收口；锁/令牌主线程同帧创建，
///   teardown 经 ame429_resetCancelToken 锁内收口——锁为 nil 时消息投递为
///   no-op，仅存在于无交互流程时的防御性调用，不构成竞争窗口）
- (void)ame429_setCancelFlag:(BOOL)flag {
    [_cancelTokenLock lock];
    if (_activeCancelToken.count > 0) {
        _activeCancelToken[0] = @(flag);
    }
    [_cancelTokenLock unlock];
}

/// ★Task429 N4a：令牌+锁收口（teardown 专用；锁内置 nil = 与后台读全互斥，
///   裸指针写不参与竞争面）
- (void)ame429_resetCancelToken {
    [_cancelTokenLock lock];
    _activeCancelToken = nil;
    [_cancelTokenLock unlock];
}

/// ★Task429 N4a：取消态唯一读路径（后台轮询/主线程终态皆走此收口）
- (BOOL)ame429_cancelRequested {
    BOOL ame429_requested = NO;
    [_cancelTokenLock lock];
    ame429_requested = (_activeCancelToken.count > 0
                        && [_activeCancelToken.firstObject boolValue]);
    [_cancelTokenLock unlock];
    return ame429_requested;
}

/// 弹窗辅助（主线程）
- (void)ame428_presentResultOnVC:(UIViewController *)vc title:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.ok", nil)
                                              style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

/// 分类清单段（弹窗用 cap 截断；报告文件内为全量）
- (NSString *)ame428_listSection:(NSString *)header from:(NSArray<Ame428CheckItem *> *)items cap:(NSUInteger)cap {
    if (items.count == 0) return @"";
    NSMutableString *s = [NSMutableString stringWithFormat:@"\n%@\n", header];
    NSUInteger show = MIN(items.count, cap);
    for (NSUInteger i = 0; i < show; i++) [s appendFormat:@"  • %@\n", items[i].display];
    if (items.count > show) {
        [s appendFormat:localize(@"ame428.verify.more_fmt", nil), (unsigned long)(items.count - show)];
    }
    return s;
}

/// 报告文件落盘（POJAV_HOME/game_integrity_report.txt；文件内全量清单）
- (void)ame428_writeReportFileForContext:(Ame428Context *)ctx
                                 checked:(NSUInteger)checked
                                 missing:(NSArray<Ame428CheckItem *> *)missing
                                 corrupt:(NSArray<Ame428CheckItem *> *)corrupt
                           repairedCount:(NSUInteger)repairedCount
                           repairFailed:(NSArray<NSString *> *)repairFailed {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *home = Ame428Home();
        if (home.length == 0) {
            NSLog(@"[Integrity] Task428: POJAV_HOME unset -- report skipped");
            return;
        }
        NSMutableString *s = [NSMutableString string];
        [s appendFormat:@"=== Prisma game integrity report (Task428) ===\n"];
        [s appendFormat:@"time: %@\n", [NSDate date]];
        [s appendFormat:@"profile: %@\n", ctx.profileName];
        // ★Task429：profile 维度字段追加（实例级扫描可追溯：附属实例原始
        //   gameDir / 库资产根（启动链同根 R）/ A 层有效隔离态）
        [s appendFormat:@"gameDir: %@\n", ctx.gameDirRaw];
        [s appendFormat:@"game_root: %@\n", ctx.gameRoot];
        NSString *ame429_iso = @"custom(-1)";
        switch (ctx.isolationEffective) {
            case 1: ame429_iso = @"isolated(1)"; break;
            case 0: ame429_iso = @"shared(0)"; break;
            default: break;
        }
        [s appendFormat:@"isolation: %@\n", ame429_iso];
        [s appendFormat:@"version: %@ (root %@)\n", ctx.versionId, ctx.versionRoot];
        [s appendFormat:@"tier: interactive-full-sha1\n"];
        [s appendFormat:@"checked: %lu\n", (unsigned long)checked];
        [s appendFormat:@"missing: %lu\n", (unsigned long)missing.count];
        [s appendFormat:@"corrupt: %lu\n", (unsigned long)corrupt.count];
        [s appendFormat:@"repaired: %lu\n", (unsigned long)repairedCount];
        [s appendFormat:@"repair_failed: %lu\n", (unsigned long)repairFailed.count];
        [s appendFormat:@"--- missing ---\n"];
        for (Ame428CheckItem *i in missing) [s appendFormat:@"%@\n", i.display];
        [s appendFormat:@"--- corrupt ---\n"];
        for (Ame428CheckItem *i in corrupt) [s appendFormat:@"%@\n", i.display];
        [s appendFormat:@"--- repair_failed ---\n"];
        for (NSString *f in repairFailed) [s appendFormat:@"%@\n", f];
        NSString *path = [home stringByAppendingPathComponent:@"game_integrity_report.txt"];
        NSError *err = nil;
        [[s dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic error:&err];
        NSLog(@"[Integrity] Task428: report written -> %@ (%@)", path, err.localizedDescription ?: @"ok");
    });
}

@end
