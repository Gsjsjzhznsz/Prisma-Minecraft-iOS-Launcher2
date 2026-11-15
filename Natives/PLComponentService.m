//
//  PLComponentService.m
//  Amethyst (Prisma)
//
//  ★Task429（PDF 第五版 §2.1 + 第六版 §3.2.5）：FCL 式组件自动安装服务实现。
//
//  ┌─ 同源声明（第六版 §3.2.5 强制项：与 PLGameIntegrityService 共享清单构建）
//  │
//  │ 本文件承载 Task429 组件维度的清单构建消费端，与 PLGameIntegrityService
//  │ （Task428 完整性校验）共用同一套 inheritsFrom 链合并与文件枚举口径：
//  │   ① 版本根解析：直接复用 PLProfiles ame353_versionRootForProfileName:
//  │     （= PLGameIntegrityService ame428_resolveContextForProfileName: 的
//  │     清单构建步骤②，同一函数引用，零第二实现）；
//  │   ② 文件枚举 + inheritsFrom 判定：直接复用 Task428 扫描式列表
//  │     [ZL2VersionsViewController ame428_scanWithOptions:]（jsonState 三态 +
//  │     inheritsFromParent 链接即其产物；该扫描器同时是版本管理页事实源）；
//  │   ③ 链环装配契约（①②覆盖不到的 ame353 深层根回退分支）1:1 对齐
//  │     ame428_resolveContextForProfileName: 的链走法：chain = [子, 父, 祖父...]、
//  │     guard 8、父版本 JSON 不可读即截断（fail-safe，不伪造清单）。
//  │   ④ 判定标记（id 形态 + mainClass/tweakClass/libraries 坐标）为 FCL
//  │     LibraryAnalyzer 口径移植，与 ①②③ 的"清单解析"正交（判定 ≠ 解析）。
//  │ ①② 为真复用（函数引用），③④ 为被授权文件边界下的同源消费端。三处
//  │ 注释互相锚定，任何一端重构须同步另一端注释——禁止出现第三套解析器。
//  └─
//
//  事务性（换装失败不落盘）三层保障详见 installComponent: 注释块。
//
//  红线：纯 Foundation；iOS 14.0+（零 iOS15+ API）；用户可见文案全部经
//  localize 的 ame429.g.* 键（键清单 scripts/task429_i18n_G.json；键尚未
//  合入 Localizable.strings 时由协调层统一合并——与 Task428/429 姊妹工位
//  同管线）；日志前缀 [Component] Task429。
//

#import "PLComponentService.h"
#import "utils.h"                          // localize / parseJSONFromFile / saveJSONToFile / ame185
#import <CommonCrypto/CommonCrypto.h>       // ★Task430：嵌套 launchwrapper-of 提取 sha1
#import "UnzipKit.h"                        // ★Task430：OptiFine 安装器 jar 内嵌库解包（ModService 同源）
#import "PLProfiles.h"                     // 注册表 + ame353 版本根（清单构建①复用点）
#import "PLMirrorCenter.h"                 // ModLoader 镜像候选链（清单面/下载面同源）
#import "ModLoaderIconHelper.h"            // 全仓加载器识别器（概览页信息卡同源）
#import "ZL2VersionsViewController.h"      // Task428 扫描式列表宿主（清单构建②复用点）
#import "installer/FabricUtils.h"          // Fabric meta 端点候选链（既有消费点）
#import "installer/NeoForgeVersionFetcher.h" // NeoForge 清单面（installerURLForLoader 同源）
#import "installer/ForgeDirectInstaller.h"     // Forge 离线直装器（既有安装器）
#import "installer/NeoForgeDirectInstaller.h"  // NeoForge 离线直装器（既有安装器）
#import "installer/modpack/ModpackUtils.h"     // installerURLForLoader + javaMajorVersionForMC
#import "external/UnzipKit/UZKArchive.h"   // 离线安装器 install_profile.json 读取
#include <stdlib.h>                        // getenv（Ame429GameDir；JavaLauncher.m 同款显式包含）

// ★Task429：旧 UI 内存版本注册表（安装器家族共用 extern，FabricUtils.m 同判例）。
// ZL2 侧版本发现走磁盘扫描，本注册仅为旧链兼容；消息至 nil 安全。
extern NSMutableArray *localVersionList;

#pragma mark - 跨 TU 类方法本地前置声明（零 .h 侵入判例）

// ★Task429：ame428_scanWithOptions: 仅声明于 ZL2VersionsViewController.m
//   （.h 不在授权清单内；分类声明 = PLGameIntegrityService.m 同判例）。
//   签名与 .m 实现逐一对应，勿漂移。
@interface ZL2VersionsViewController (Ame429Task429Scan)
+ (NSArray<NSDictionary *> *)ame428_scanWithOptions:(BOOL)includeSize;
@end

// ★Task429：ame428_scanRoot 仅声明于 PLProfiles.m（PLGameIntegrityService.m
//   同款本地前置声明判例；签名与 .m 实现逐一对应，勿漂移）。
@interface PLProfiles (Ame429Task429ScanRoot)
+ (NSString *)ame428_scanRoot;
@end

#pragma mark - 常量（常量实名判例）

/// inheritsFrom 链走链护栏（PLGameIntegrityService ame428 链同值 8）
static const NSInteger kAme429ChainGuardMax = 8;
/// 清单类小载荷同步请求超时（秒；ModpackUtils ame428 单发判例同量级）
static const NSTimeInterval kAme429MetaFetchTimeout = 12.0;
/// installer jar 同步下载超时（秒；直装器 jar 约 5-30MB）
static const NSTimeInterval kAme429InstallerFetchTimeout = 60.0;

#pragma mark - 文件级工具函数

/// POJAV_GAME_DIR（可为 nil；调用方 NSHomeDirectory 兜底——ame336 同款）
static NSString *Ame429GameDir(void) {
    const char *c = getenv("POJAV_GAME_DIR");
    if (!c || !*c) return nil;
    return [NSString stringWithUTF8String:c];
}

/// 单发同步 GET（ModpackUtils ame428_singleLookupSHA1 判例同款：信号量 +
/// 超时封顶；HTTP ≥400 按失败处理——ame337 下载面同口径）。
static NSData *Ame429SyncFetch(NSURL *url, NSTimeInterval timeout) {
    if (![url isKindOfClass:[NSURL class]] || url.absoluteString.length == 0) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = timeout;
    // UA 对齐 ModrinthAPI/ModpackUtils 仓内判例（Task263）
    [request setValue:@"Amethyst-iOS/1.0" forHTTPHeaderField:@"User-Agent"];
    __block NSData *outData = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) {
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
                    if (status >= 200 && status < 400) outData = data;
                } else {
                    outData = data;
                }
            }
            dispatch_semaphore_signal(done);
        }] resume];
    // 超时兜底 = 请求超时 + 5s（completion 永不回调防线，ame428 判例同款）
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 5.0) * NSEC_PER_SEC)));
    return outData;
}

/// 扫描列表内按 id 取条目（ZL2VersionsViewController ame428_byIdLocal 同款静态形态）
static NSDictionary *Ame429ById(NSArray<NSDictionary *> *list, NSString *vid) {
    for (NSDictionary *e in list) {
        if ([e isKindOfClass:[NSDictionary class]] && [e[@"id"] isEqualToString:vid]) return e;
    }
    return @{};
}

/// 统一错误构造（域 + 本地化文案）
static NSError *Ame429Error(PLComponentServiceError code, NSString *message) {
    return [NSError errorWithDomain:PLComponentServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - 内部数据模型

/// 继承链环（chain = [子, 父, 祖父...]；PLGameIntegrityService 同向序）
@interface Ame429ChainNode : NSObject
@property (nonatomic, copy) NSString *versionId;        // 版本实体 id（= versions/ 目录名）
@property (nonatomic, copy, nullable) NSString *jsonPath; // 该环 version json（内容兜底判定用）
@property (nonatomic, assign) BOOL jsonOK;              // JSON 可解析（ame428 scan jsonState==1 同义）
@end
@implementation Ame429ChainNode
@end

// 条目内部可写（对外 readonly 契约）
@interface PLComponentEntry ()
@property (nonatomic, copy, readwrite) NSString *type;
@property (nonatomic, copy, readwrite, nullable) NSString *version;
@property (nonatomic, copy, readwrite, nullable) NSString *versionId;
@property (nonatomic, copy, readwrite, nullable) NSString *minecraftVersion;
@property (nonatomic, copy, readwrite) NSString *source;
@property (nonatomic, assign, readwrite, getter=isInstallable) BOOL installable;
@end

@implementation PLComponentEntry
@end

@implementation PLComponentService

#pragma mark - 常量定义

NSString * const PLComponentTypeClean = @"clean";
NSString * const PLComponentTypeFabric = @"fabric";
NSString * const PLComponentTypeForge = @"forge";
NSString * const PLComponentTypeNeoForge = @"neoforge";
NSString * const PLComponentTypeOptiFine = @"optifine";
NSString * const PLComponentSourceScanned = @"scanned";

NSString * const PLComponentServiceErrorDomain = @"PLComponentService";

#pragma mark - 清单构建（同源声明见文件头）

/// 实例 → 继承链（chain = [子, 父, 祖父...]）。
/// ① 注册表直查（PLGameIntegrityService 清单构建步骤①同口径：注册表字典键
///   直查，只读零副作用）；
/// ② 文件枚举 + inheritsFrom 判定：复用 Task428 扫描式列表（清单构建②复用点）；
/// ③ 链环装配：扫描列表覆盖时走链接（零重复 JSON 解析）；扫描不覆盖目标
///   实例（ame353 深层根/跨实例形态）时按 ame428 链走法回退直读。
+ (NSArray<Ame429ChainNode *> *)ame429_scanChainForProfile:(NSString *)resolvedProfile {
    @autoreleasepool {
        NSDictionary *profile = [PLProfiles.current.profiles objectForKey:resolvedProfile];
        NSString *vid = nil;
        if ([profile isKindOfClass:[NSDictionary class]] &&
            [profile[@"lastVersionId"] isKindOfClass:[NSString class]]) {
            vid = (NSString *)profile[@"lastVersionId"];
        }
        if (vid.length == 0) return @[];
        if ([vid hasPrefix:@"latest-"]) return @[]; // 别名走在线解析下载流，绝不指根（ame353 同口径）

        // ② 复用 Task428 扫描式列表（文件枚举 + jsonState 三态 + inheritsFrom 判定）
        NSArray<NSDictionary *> *scan = [ZL2VersionsViewController ame428_scanWithOptions:NO];
        NSDictionary *leaf = Ame429ById(scan, vid);
        BOOL leafOK = ([leaf isKindOfClass:[NSDictionary class]] && leaf.count > 0 && [leaf[@"jsonOK"] boolValue]);

        NSMutableArray<Ame429ChainNode *> *chain = [NSMutableArray array];
        if (leafOK) {
            // ③-a 链接装配：scan 条目的 inheritsFromParent 即其版本 JSON 的
            //   inheritsFrom 字段（Task428 扫描器已解析），本端零重复解析。
            //   走链契约与 PLGameIntegrityService ame428_resolveContextForProfileName:
            //   一致：guard 8 / 父环 jsonOK=NO（缺失或损坏）即截断。
            NSString *leafPath = [leaf[@"path"] isKindOfClass:[NSString class]] ? (NSString *)leaf[@"path"] : nil;
            Ame429ChainNode *node = [[Ame429ChainNode alloc] init];
            node.versionId = vid;
            if (leafPath.length > 0) {
                node.jsonPath = [leafPath stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.json", vid]];
            }
            node.jsonOK = YES;
            [chain addObject:node];
            NSString *cursor = [leaf[@"inheritsFromParent"] isKindOfClass:[NSString class]]
                ? (NSString *)leaf[@"inheritsFromParent"] : nil;
            NSInteger guardCount = 0;
            while (cursor.length > 0 && guardCount++ < kAme429ChainGuardMax) {
                NSDictionary *entry = Ame429ById(scan, cursor);
                if (![entry isKindOfClass:[NSDictionary class]] || entry.count == 0 ||
                    ![entry[@"jsonOK"] boolValue]) {
                    NSLog(@"[Component] Task429: inheritsFrom parent missing/broken (%@) -- chain truncated at %@",
                          cursor, vid);
                    break;
                }
                Ame429ChainNode *parent = [[Ame429ChainNode alloc] init];
                parent.versionId = cursor;
                NSString *parentPath = [entry[@"path"] isKindOfClass:[NSString class]] ? (NSString *)entry[@"path"] : nil;
                if (parentPath.length > 0) {
                    parent.jsonPath = [parentPath stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"%@.json", cursor]];
                }
                parent.jsonOK = YES;
                [chain addObject:parent];
                cursor = [entry[@"inheritsFromParent"] isKindOfClass:[NSString class]]
                    ? (NSString *)entry[@"inheritsFromParent"] : nil;
            }
            return [chain copy];
        }

        // ③-b 回退：扫描列表未覆盖目标实例（跨实例/ame353 深层根形态）→
        //   与 PLGameIntegrityService 清单构建②③同口径：ame353 自洽根解析 +
        //   直读链走（guard 8 / 父 JSON 不可读截断）。**同源消费端**：本分支
        //   为 ame428 链走法的 Task429 维度引用，勿分叉（文件头同源声明③）。
        NSString *root = [PLProfiles ame353_versionRootForProfileName:resolvedProfile];
        if (root.length == 0) root = [PLProfiles ame428_scanRoot];
        if (root.length == 0) return @[];
        NSString *jsonPath = [[root stringByAppendingPathComponent:@"versions"]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.json", vid, vid]];
        NSMutableDictionary *json = parseJSONFromFile(jsonPath);
        if (![json isKindOfClass:[NSDictionary class]] || json[@"NSErrorObject"]) {
            NSLog(@"[Component] Task429: version JSON unreadable (%@) -- no components", jsonPath);
            return @[];
        }
        Ame429ChainNode *node = [[Ame429ChainNode alloc] init];
        node.versionId = vid;
        node.jsonPath = jsonPath;
        node.jsonOK = YES;
        [chain addObject:node];
        NSString *cursor = [json[@"inheritsFrom"] isKindOfClass:[NSString class]] ? (NSString *)json[@"inheritsFrom"] : nil;
        NSInteger guardCount = 0;
        while (cursor.length > 0 && guardCount++ < kAme429ChainGuardMax) {
            if ([cursor isEqualToString:vid]) break; // 自环防御（ame428 scan 自引用排除同语义）
            NSString *parentPath = [[root stringByAppendingPathComponent:@"versions"]
                stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.json", cursor, cursor]];
            NSMutableDictionary *parentJson = parseJSONFromFile(parentPath);
            if (![parentJson isKindOfClass:[NSDictionary class]] || parentJson[@"NSErrorObject"]) {
                NSLog(@"[Component] Task429: inheritsFrom parent JSON unreadable (%@) -- chain truncated at %@",
                      parentPath, cursor);
                break;
            }
            Ame429ChainNode *parent = [[Ame429ChainNode alloc] init];
            parent.versionId = cursor;
            parent.jsonPath = parentPath;
            parent.jsonOK = YES;
            [chain addObject:parent];
            cursor = [parentJson[@"inheritsFrom"] isKindOfClass:[NSString class]] ? (NSString *)parentJson[@"inheritsFrom"] : nil;
        }
        return [chain copy];
    }
}

/// 单环组件判定（FCL LibraryAnalyzer 口径移植；判定 ≠ 清单解析，见文件头④）。
/// ① id 形态：复用全仓加载器识别器 ModLoaderIconHelper detectLoaderFromVersionId:
///   （概览页信息卡/版本卡同源），映射到五分类；
/// ② 内容兜底：mainClass/tweakClass/libraries 坐标标记（id 形态未命中时）。
/// 返回五分类常量之一，非组件环返回 nil（vanilla 本体环）。
+ (nullable NSString *)ame429_detectTypeForNode:(Ame429ChainNode *)node {
    if (node.versionId.length == 0) return nil;
    // 注意判定顺序：neoforge 先于 forge（id 含 forge 子串——识别器内部同序）
    NSString *detected = [ModLoaderIconHelper detectLoaderFromVersionId:node.versionId];
    if ([detected isEqualToString:@"neoforge"]) return PLComponentTypeNeoForge;
    if ([detected isEqualToString:@"forge"]) return PLComponentTypeForge;
    if ([detected isEqualToString:@"optifabric"] || [detected isEqualToString:@"optifine"]) {
        return PLComponentTypeOptiFine;
    }
    // Quilt 谱系归并 fabric 家族（清单面共用 Fabric meta；换装语义 = 家族覆盖安装，
    // 与 ZL2GameAddons 互斥表"五主加载器互斥"同口径——quilte 实例点 fabric 条目
    // 即完成家族换装；quilt 专属清单面不在本任务范围）
    if ([detected isEqualToString:@"quilt"] || [detected isEqualToString:@"fabric"]) {
        return PLComponentTypeFabric;
    }
    // iris/rift = 着色器 mod 装载器，不属于本页五分类 → 继续内容兜底
    if (node.jsonOK && node.jsonPath.length > 0) {
        NSMutableDictionary *json = parseJSONFromFile(node.jsonPath);
        if ([json isKindOfClass:[NSDictionary class]] && !json[@"NSErrorObject"]) {
            NSString *mainClass = [json[@"mainClass"] isKindOfClass:[NSString class]]
                ? (NSString *)json[@"mainClass"] : nil;
            NSString *tweakClass = [json[@"tweakClass"] isKindOfClass:[NSString class]]
                ? (NSString *)json[@"tweakClass"] : nil;
            NSString *lc = mainClass.lowercaseString ?: @"";
            NSString *tc = tweakClass.lowercaseString ?: @"";
            if ([tc hasPrefix:@"optifine."]) return PLComponentTypeOptiFine;
            if ([lc containsString:@"fabricmc"]) return PLComponentTypeFabric;
            if ([lc containsString:@"neoforged"]) return PLComponentTypeNeoForge;
            if ([lc containsString:@"fml"] || [lc containsString:@"forge"]) return PLComponentTypeForge;
            NSArray *libs = [json[@"libraries"] isKindOfClass:[NSArray class]]
                ? (NSArray *)json[@"libraries"] : nil;
            for (NSDictionary *lib in libs) {
                if (![lib isKindOfClass:[NSDictionary class]]) continue;
                NSString *name = [lib[@"name"] isKindOfClass:[NSString class]]
                    ? (NSString *)lib[@"name"] : nil;
                if (name.length == 0) continue;
                if ([name hasPrefix:@"net.neoforged:"]) return PLComponentTypeNeoForge;
                if ([name hasPrefix:@"net.minecraftforge:"]) return PLComponentTypeForge;
                if ([name hasPrefix:@"net.fabricmc:fabric-loader"] ||
                    [name hasPrefix:@"org.quiltmc:quilt-loader"]) return PLComponentTypeFabric;
                if ([name hasPrefix:@"optifine:OptiFine"]) return PLComponentTypeOptiFine;
            }
        }
    }
    return nil;
}

/// 继承链根 MC 版本：末端环为 vanilla（判定 nil）→ 其 id 即 MC 版本；
/// truncated 链末端仍为 loader 形态时按 id 形态递归剥壳推断（仅 clean 展示用）。
+ (nullable NSString *)ame429_mcVersionForChain:(NSArray<Ame429ChainNode *> *)chain {
    if (chain.count == 0) return nil;
    Ame429ChainNode *rootNode = chain.lastObject;
    if ([self ame429_detectTypeForNode:rootNode] == nil) return rootNode.versionId;
    return [self ame429_guessMinecraftVersionFromId:rootNode.versionId];
}

/// truncated 链兜底：loader 形态 id → MC 版本段（递归剥复合前缀，防呆深度 3 层）
+ (NSString *)ame429_guessMinecraftVersionFromId:(NSString *)versionId {
    for (NSString *anchor in @[@"-forge-", @"-neoforge-", @"-OptiFine_"]) {
        NSRange range = [versionId rangeOfString:anchor];
        if (range.location != NSNotFound && range.location > 0) {
            NSString *prefix = [versionId substringToIndex:range.location];
            if ([prefix rangeOfString:@"-forge-"].location != NSNotFound ||
                [prefix rangeOfString:@"-neoforge-"].location != NSNotFound ||
                [prefix rangeOfString:@"-OptiFine_"].location != NSNotFound) {
                return [self ame429_guessMinecraftVersionFromId:prefix]; // 复合形态递归剥壳
            }
            return prefix;
        }
    }
    NSArray *parts = [versionId componentsSeparatedByString:@"-"];
    if ([versionId hasPrefix:@"fabric-loader-"] || [versionId hasPrefix:@"quilt-loader-"]) {
        if (parts.count >= 4) return parts.lastObject;   // "fabric-loader-<v>-<mc>"
        return versionId;
    }
    if (parts.count >= 3) return parts[1];               // "Forge-1.20.1-47.3.0" legacy 形态中段
    return versionId;
}

#pragma mark - analyze（FCL LibraryAnalyzer.analyze 对标）

+ (void)analyzeComponentsForProfile:(NSString *)profileName
                         completion:(void (^)(NSArray<PLComponentEntry *> *entries))completion {
    void (^safeCompletion)(NSArray<PLComponentEntry *> *) = ^(NSArray<PLComponentEntry *> *entries) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(entries); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *resolvedProfile = profileName.length > 0 ? profileName : PLProfiles.current.selectedProfileName;
            if (resolvedProfile.length == 0) { safeCompletion(@[]); return; }
            NSArray<Ame429ChainNode *> *chain = [self ame429_scanChainForProfile:resolvedProfile];
            if (chain.count == 0) { safeCompletion(@[]); return; }
            NSString *mc = [self ame429_mcVersionForChain:chain];
            if (mc.length == 0) { safeCompletion(@[]); return; }

            // 逐环判定（子优先；同类型首中即占 = processVersion 子覆盖父同语义：
            // 子环上的组件形态优先于父环，例如 OptiFine 补丁环盖 Forge 环时
            // 各自类型独立成条，但同类型重复环只取子环）
            NSMutableDictionary<NSString *, PLComponentEntry *> *byType = [NSMutableDictionary dictionary];
            for (Ame429ChainNode *node in chain) {
                NSString *type = [self ame429_detectTypeForNode:node];
                if (type.length == 0) continue;
                if (byType[type] != nil) continue;
                PLComponentEntry *entry = [[PLComponentEntry alloc] init];
                entry.type = type;
                entry.version = [self componentVersionForVersionId:node.versionId type:type];
                entry.versionId = node.versionId;
                entry.minecraftVersion = mc;
                entry.source = PLComponentSourceScanned;
                entry.installable = YES; // fabric/forge/neoforge 默认可换装；optifine 在下方灰置
                byType[type] = entry;
            }
            // OptiFine：远端清单未接入 → 灰置"仅展示"（离线导入可用，importOfflineJar）
            PLComponentEntry *optifine = byType[PLComponentTypeOptiFine];
            if (optifine) optifine.installable = NO;

            // 条目 = {type, version, source:"scanned"}；顺序 fabric → forge →
            // neoforge → optifine → clean。clean 收尾一条表达"干净本体 = MC x.y.z"
            //（排除游戏本体重复计数：本体环不参与 loader 判定，本体换版不走本页）。
            NSMutableArray<PLComponentEntry *> *ordered = [NSMutableArray array];
            for (NSString *type in @[PLComponentTypeFabric, PLComponentTypeForge,
                                     PLComponentTypeNeoForge, PLComponentTypeOptiFine]) {
                PLComponentEntry *entry = byType[type];
                if (entry) [ordered addObject:entry];
            }
            PLComponentEntry *clean = [[PLComponentEntry alloc] init];
            clean.type = PLComponentTypeClean;
            clean.version = mc;
            clean.versionId = mc; // 干净本体实体 id == MC 版本
            clean.minecraftVersion = mc;
            clean.source = PLComponentSourceScanned;
            clean.installable = NO;
            [ordered addObject:clean];

            NSLog(@"[Component] Task429: analyze '%@' -> %lu component(s), MC %@",
                  resolvedProfile, (unsigned long)ordered.count, mc);
            safeCompletion([ordered copy]);
        }
    });
}

#pragma mark - 版本号提取 / 显示名

+ (nullable NSString *)componentVersionForVersionId:(NSString *)versionId type:(NSString *)type {
    if (versionId.length == 0) return nil;
    if ([type isEqualToString:PLComponentTypeClean]) return versionId;
    if ([type isEqualToString:PLComponentTypeForge] || [type isEqualToString:PLComponentTypeNeoForge]) {
        NSString *anchor = [type isEqualToString:PLComponentTypeForge] ? @"-forge-" : @"-neoforge-";
        NSRange range = [versionId rangeOfString:anchor];
        if (range.location != NSNotFound && NSMaxRange(range) < versionId.length) {
            return [versionId substringFromIndex:NSMaxRange(range)];
        }
        // legacy 复合形态（"Forge-1.20.1-47.3.0"，ForgeDirectInstaller 注释同表）：末段
        NSArray *parts = [versionId componentsSeparatedByString:@"-"];
        if (parts.count >= 2) return parts.lastObject;
        return nil;
    }
    if ([type isEqualToString:PLComponentTypeFabric]) {
        // "fabric-loader-<v>-<mc>" / "quilt-loader-<v>-<mc>"：第三段
        NSArray *parts = [versionId componentsSeparatedByString:@"-"];
        if (parts.count >= 3) return parts[2];
        return nil;
    }
    if ([type isEqualToString:PLComponentTypeOptiFine]) {
        // "<parent>-OptiFine_<type>_<patch>"：OptiFine_ 后缀
        NSRange range = [versionId rangeOfString:@"OptiFine_"];
        if (range.location != NSNotFound && NSMaxRange(range) < versionId.length) {
            return [versionId substringFromIndex:NSMaxRange(range)];
        }
        return nil;
    }
    return nil;
}

+ (NSString *)displayNameForComponentType:(NSString *)type {
    if ([type isEqualToString:PLComponentTypeClean]) {
        return localize(@"ame429.g.comp.type.clean", @"原版（干净本体）");
    }
    // 品牌名（Fabric/Forge/NeoForge/OptiFine）不分语种；quilt 谱系归并 fabric 后
    // 显示名带家族注记（判定归并语义见 ame429_detectTypeForNode 注释）
    if ([type isEqualToString:PLComponentTypeFabric]) {
        return localize(@"ame429.g.comp.type.fabric", @"Fabric（含 Quilt 谱系）");
    }
    NSString *brand = [ModLoaderIconHelper displayNameForLoader:type];
    return brand.length > 0 ? brand : type;
}

#pragma mark - availableVersions（远端清单面）

+ (void)availableVersionsForComponentType:(NSString *)type
                              gameVersion:(NSString *)minecraftVersion
                               completion:(void (^)(NSArray<NSString *> *versions,
                                                    NSError * _Nullable error))completion {
    void (^safeCompletion)(NSArray<NSString *> *, NSError *) = ^(NSArray<NSString *> *versions, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(versions, error); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            if (minecraftVersion.length == 0) {
                safeCompletion(@[], Ame429Error(PLComponentServiceErrorNetwork,
                    localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试")));
                return;
            }
            if ([type isEqualToString:PLComponentTypeFabric]) {
                NSArray *fabricList = [self ame429_fabricVersionListForGame:minecraftVersion];
                if (fabricList.count > 0) { safeCompletion(fabricList, nil); return; }
                safeCompletion(@[], Ame429Error(PLComponentServiceErrorNetwork,
                    localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试")));
                return;
            }
            if ([type isEqualToString:PLComponentTypeForge]) {
                NSArray *list = [self ame429_forgeVersionListForGame:minecraftVersion];
                if (list.count > 0) { safeCompletion(list, nil); return; }
                safeCompletion(@[], Ame429Error(PLComponentServiceErrorNetwork,
                    localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试")));
                return;
            }
            if ([type isEqualToString:PLComponentTypeNeoForge]) {
                // 直接复用 NeoForgeVersionFetcher（installerURLForLoader 同源清单面；
                // 内聚 Task185 匹配器 + 双源回退 + 新在前排序）
                [NeoForgeVersionFetcher fetchVersionsForGameVersion:minecraftVersion
                                                         completion:^(NSArray *versions, NSError *error) {
                    NSMutableArray<NSString *> *outList = [NSMutableArray array];
                    for (id obj in versions ?: @[]) {
                        if ([obj isKindOfClass:[NSString class]]) [outList addObject:(NSString *)obj];
                    }
                    safeCompletion([outList copy], error);
                }];
                return;
            }
            // optifine / clean：无远端清单面（任务口径：OptiFine 无源则灰置"仅展示"；
            // OptiFine 离线导入走 importOfflineJar；clean 本体换版走游戏下载页）
            NSString *note = [type isEqualToString:PLComponentTypeClean]
                ? localize(@"ame429.g.comp.clean.viewonly_note", @"原版本体：换版本请走游戏下载页")
                : localize(@"ame429.g.comp.optifine.viewonly_note",
                           @"OptiFine 远端清单未接入：仅展示当前版本，可离线导入安装器");
            safeCompletion(@[], Ame429Error(PLComponentServiceErrorNoRemoteSource, note));
        }
    });
}

/// Fabric per-game loader 清单（meta v2；PLMirrorCenter 候选链 =
/// ZL2GameAddonsViewController ame_fetchListForIdentifier fabric 分支同源消费点）
+ (nullable NSArray<NSString *> *)ame429_fabricVersionListForGame:(NSString *)gameVersion {
    NSString *official = [NSString stringWithFormat:@"https://meta.fabricmc.net/v2/versions/loader/%@", gameVersion];
    NSArray<NSURL *> *candidates = [PLMirrorCenter candidateURLsForOriginalURL:[NSURL URLWithString:official]
                                                                  resourceType:PLMirrorResourceTypeModLoader];
    if (candidates.count == 0) candidates = @[[NSURL URLWithString:official]];
    NSData *data = nil;
    for (NSURL *url in candidates) {
        data = Ame429SyncFetch(url, kAme429MetaFetchTimeout);
        if (data) break;
    }
    if (!data) {
        NSLog(@"[Component] Task429: fabric meta list fetch failed (all candidates)");
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSString *> *outList = [NSMutableArray array];
    for (id obj in json) {
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSString *version = [obj[@"loader"][@"version"] isKindOfClass:[NSString class]]
            ? (NSString *)obj[@"loader"][@"version"] : nil;
        if (version.length > 0) [outList addObject:version];
    }
    return [outList copy]; // meta v2 返回序即新在前
}

/// Forge per-mc 清单（BMCLAPI JSON 主源 → 官方 maven-metadata.xml 正则兜底；
/// 端点与解析口径 1:1 对齐 ZL2GameAddonsViewController ame_fetchListForIdentifier
/// forge 分支（Task325），同源清单面勿漂移）
+ (nullable NSArray<NSString *> *)ame429_forgeVersionListForGame:(NSString *)gameVersion {
    NSData *data = Ame429SyncFetch(
        [NSURL URLWithString:[NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/forge/minecraft/%@", gameVersion]],
        kAme429MetaFetchTimeout);
    if (data) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSArray class]]) {
            NSMutableArray<NSString *> *outList = [NSMutableArray array];
            for (NSDictionary *entry in json) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                NSString *version = [entry[@"version"] isKindOfClass:[NSString class]]
                    ? (NSString *)entry[@"version"] : nil;
                if (version.length > 0) [outList addObject:version];
            }
            if (outList.count > 0) return [outList copy];
        }
    }
    NSLog(@"[Component] Task429: forge bmclapi list failed -- falling back to official maven-metadata.xml");
    NSData *meta = Ame429SyncFetch(
        [NSURL URLWithString:@"https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"],
        kAme429MetaFetchTimeout);
    if (!meta) return nil;
    NSString *xml = [[NSString alloc] initWithData:meta encoding:NSUTF8StringEncoding];
    if (xml.length == 0) return nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<version>([^<]+)</version>" options:0 error:nil];
    NSMutableArray<NSString *> *outList = [NSMutableArray array];
    [regex enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length)
                      usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *version = [xml substringWithRange:[match rangeAtIndex:1]];
        // 形如 1.21.1-52.0.24：按游戏版本前缀过滤（Task325 同口径）
        if ([version hasPrefix:gameVersion] && [version rangeOfString:@"-"].location != NSNotFound) {
            [outList addObject:version];
        }
    }];
    // metadata 旧版在前 → 反转为新在前（Task325 同口径）
    return outList.count > 0 ? [[outList reverseObjectEnumerator] allObjects] : nil;
}

#pragma mark - install（事务性见方法头）

/// 安装/换装主入口。
///
/// 事务性（换装失败不落盘）三层保障：
///  ① Forge/NeoForge：ForgeDirectInstaller / NeoForgeDirectInstaller 在
///    processor 执行 + 产物校验（Task188 Step E）全部通过后才写
///    versions/<id>/<id>.json；本调用以 skipRegisterVersion:YES 传入 →
///    安装器绝不触碰 profile 注册表（其 registerVersion 跳过）。
///  ② Fabric：meta profile json 全量拉取并解析成功（含 MC 版本段守卫）后
///    才做单次原子落盘（saveJSONToFile）；落盘失败即回滚删除半截文件。
///  ③ 实例 repoint（lastVersionId/javaVersion）只在安装器返回 YES 且新版本
///    JSON 实体确认存在后于主线程执行（注册表是 UI 读面，写方收口主队列——
///    ame336 Task337 判例）；失败路径零注册表写入。
/// 残余说明：安装中途失败的 libraries 残片属共享 maven 缓存（按坐标寻址、
/// 无孤立引用，下次成功安装直接复用）——与 FCL/HMCL 失败语义一致。
+ (void)installComponent:(NSString *)profileName
                    type:(NSString *)type
                 version:(NSString *)remoteVersion
              completion:(void (^)(BOOL success,
                                   NSString * _Nullable newVersionId,
                                   NSError * _Nullable error))completion {
    void (^safeCompletion)(BOOL, NSString *, NSError *) = ^(BOOL success, NSString *newVersionId, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(success, newVersionId, error); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *resolvedProfile = profileName.length > 0 ? profileName : PLProfiles.current.selectedProfileName;
            if (resolvedProfile.length == 0) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorProfileMissing,
                    localize(@"ame429.g.comp.empty", @"未检测到组件（实例尚未安装版本）")));
                return;
            }
            // ① 本地上下文：继承链根 MC 版本（复用 analyze 的链扫描，零第三套解析）
            NSArray<Ame429ChainNode *> *chain = [self ame429_scanChainForProfile:resolvedProfile];
            NSString *mc = [self ame429_mcVersionForChain:chain];
            if (mc.length == 0) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorProfileMissing,
                    localize(@"ame429.g.comp.empty", @"未检测到组件（实例尚未安装版本）")));
                return;
            }
            // ② clean/optifine 无远端安装面（UI 灰置；防御守卫配真错误回执）
            if ([type isEqualToString:PLComponentTypeClean] || [type isEqualToString:PLComponentTypeOptiFine]) {
                NSString *note = [type isEqualToString:PLComponentTypeClean]
                    ? localize(@"ame429.g.comp.clean.viewonly_note", @"原版本体：换版本请走游戏下载页")
                    : localize(@"ame429.g.comp.optifine.viewonly_note",
                               @"OptiFine 远端清单未接入：仅展示当前版本，可离线导入安装器");
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorNoRemoteSource, note));
                return;
            }
            if (remoteVersion.length == 0) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorUnsupportedType,
                    localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试")));
                return;
            }

            // ③ 复用既有安装器执行（均为同步后台语义；completion 收口本方法主线程）
            NSString *newVersionId = nil;
            NSError *installError = nil;
            if ([type isEqualToString:PLComponentTypeFabric]) {
                newVersionId = [self ame429_installFabricMc:mc loaderVersion:remoteVersion error:&installError];
            } else if ([type isEqualToString:PLComponentTypeForge] || [type isEqualToString:PLComponentTypeNeoForge]) {
                NSString *vendor = [type isEqualToString:PLComponentTypeNeoForge]
                    ? PLComponentTypeNeoForge : PLComponentTypeForge;
                newVersionId = [self ame429_installForgeLikeVendor:vendor
                                                                mc:mc
                                                     versionString:remoteVersion
                                                             error:&installError];
            } else {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorUnsupportedType,
                    localize(@"ame429.g.comp.clean.viewonly_note", @"原版本体：换版本请走游戏下载页")));
                return;
            }
            if (newVersionId.length == 0) {
                safeCompletion(NO, nil, installError ?: Ame429Error(PLComponentServiceErrorInstall,
                    localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更")));
                return;
            }

            // ④ repoint（主线程；只在安装成功 + 版本实体确认落盘后执行）
            NSError *repointError = nil;
            BOOL repointed = [self ame429_repointProfileMainThread:resolvedProfile
                                                        toVersionId:newVersionId
                                                          mcVersion:mc
                                                              error:&repointError];
            safeCompletion(repointed, repointed ? newVersionId : nil, repointed ? nil : repointError);
        }
    });
}

/// Fabric 换装（meta profile json 候选链 + 原子落盘；ame336 同源 URL 面）
+ (nullable NSString *)ame429_installFabricMc:(NSString *)mc
                                 loaderVersion:(NSString *)loaderVersion
                                         error:(NSError **)error {
    // 候选链复用 FabricUtils 既有消费点（meta profile json 端点 + PLMirrorCenter
    // 策略序，与 ame336 执行器同一 URL 面——Task336/325 同源）
    NSArray<NSURL *> *candidates = [FabricUtils candidateURLsForVendor:@"Fabric"
                                                      minecraftVersion:mc
                                                         loaderVersion:loaderVersion];
    NSDictionary *profileJson = nil;
    for (NSURL *url in candidates) {
        NSData *data = Ame429SyncFetch(url, kAme429MetaFetchTimeout);
        if (!data) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) { profileJson = (NSDictionary *)json; break; }
    }
    if (![profileJson isKindOfClass:[NSDictionary class]]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorNetwork,
            localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试"));
        return nil;
    }
    NSString *profileId = [profileJson[@"id"] isKindOfClass:[NSString class]]
        ? (NSString *)profileJson[@"id"] : nil;
    // FCL 式守卫：meta 载荷 id 必须含目标 MC 版本（防镜像脏载荷错装到错误谱系）
    if (profileId.length == 0 || ![profileId containsString:mc]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParse,
            localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息"));
        return nil;
    }
    // 原子落盘（ame336 同口径 versions/<id>/<id>.json）；失败即回滚半截文件
    //（事务性②：落盘失败 = 零实例状态变更）
    NSString *gameDir = Ame429GameDir() ?: NSHomeDirectory();
    NSString *jsonPath = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.json", profileId, profileId]];
    NSError *saveError = saveJSONToFile(profileJson, jsonPath);
    if (saveError) {
        [[NSFileManager defaultManager] removeItemAtPath:jsonPath error:nil];
        if (error) *error = saveError;
        return nil;
    }
    // 旧 UI 内存注册表同款注册（FabricUtils ame336 同款；主线程——注册表是
    // UI 读面；ZL2 侧版本发现走磁盘扫描，本注册仅为旧链兼容，消息至 nil 安全）
    dispatch_async(dispatch_get_main_queue(), ^{
        [localVersionList addObject:@{@"id": profileId, @"type": @"custom"}];
    });
    NSLog(@"[Component] Task429: fabric installed %@ %@/%@", profileId, mc, loaderVersion);
    return profileId;
}

/// Forge/NeoForge 换装（installer jar 下载 + 直装器复用；ame337 同源语义）
+ (nullable NSString *)ame429_installForgeLikeVendor:(NSString *)vendor
                                                  mc:(NSString *)mc
                                       versionString:(NSString *)versionString
                                               error:(NSError **)error {
    // ① pure loader 段（ame337 同表：清单可能返回复合 "<mc>-<v>"；NeoForge 为纯段）
    NSString *pureLoader = versionString;
    NSString *compoundPrefix = [NSString stringWithFormat:@"%@-", mc];
    if ([pureLoader hasPrefix:compoundPrefix]) {
        pureLoader = [pureLoader substringFromIndex:compoundPrefix.length];
    }
    NSString *versionId = [NSString stringWithFormat:@"%@-%@-%@", mc,
        [vendor isEqualToString:PLComponentTypeNeoForge] ? @"neoforge" : @"forge", pureLoader];

    // ② installer URL 面：主源 = ModpackUtils installerURLForLoader:（任务钦定
    //    同源清单面：PLMirrorCenter ModLoader 策略首选）；候选链 = 同 official
    //    URL 的 PLMirrorCenter 候选列表（镜像失败回退官方，下载面与 ModpackUtils
    //    同源）。official URL 构造 1:1 对齐 ModpackUtils.installerURLForLoader
    //    内部（同源勿漂移；NeoForge 1.20.1 = 老坐标 net/neoforged/forge）。
    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    NSString *primary = [ModpackUtils installerURLForLoader:vendor
                                              loaderVersion:pureLoader
                                             minecraftVersion:mc];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    if (primary.length > 0) {
        NSURL *primaryURL = [NSURL URLWithString:primary];
        if (primaryURL) { [candidates addObject:primaryURL]; [seen addObject:primaryURL.absoluteString]; }
    }
    NSString *versionString2 = [NSString stringWithFormat:@"%@-%@", mc, pureLoader];
    NSString *officialURLString = nil;
    if ([vendor isEqualToString:PLComponentTypeNeoForge]) {
        BOOL legacyForgeArtifact = [mc isEqualToString:@"1.20.1"];
        if (legacyForgeArtifact) {
            officialURLString = [NSString stringWithFormat:
                @"https://maven.neoforged.net/releases/net/neoforged/forge/%@/forge-%@-installer.jar",
                pureLoader, pureLoader];
        } else {
            officialURLString = [NSString stringWithFormat:
                @"https://maven.neoforged.net/releases/net/neoforged/neoforge/%@/neoforge-%@-installer.jar",
                pureLoader, pureLoader];
        }
    } else {
        officialURLString = [NSString stringWithFormat:
            @"https://maven.minecraftforge.net/net/minecraftforge/forge/%@/forge-%@-installer.jar",
            versionString2, versionString2];
    }
    for (NSURL *url in [PLMirrorCenter candidateURLsForOriginalURL:[NSURL URLWithString:officialURLString]
                                                      resourceType:PLMirrorResourceTypeModLoader]) {
        if (url && ![seen containsObject:url.absoluteString]) {
            [candidates addObject:url];
            [seen addObject:url.absoluteString];
        }
    }

    // ③ installer jar 下载（原子写 tmp；HTTP≥400 在 Ame429SyncFetch 内已按失败处理）
    NSString *destPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ame429-%@-installer-%@.jar", vendor, [NSUUID UUID].UUIDString]];
    BOOL downloaded = NO;
    for (NSURL *url in candidates) {
        NSData *data = Ame429SyncFetch(url, kAme429InstallerFetchTimeout);
        if (data.length == 0) continue;
        if ([data writeToFile:destPath options:NSDataWritingAtomic error:nil]) { downloaded = YES; break; }
    }
    if (!downloaded) {
        NSLog(@"[Component] Task429: %@ installer download failed (%lu candidate(s))",
              vendor, (unsigned long)candidates.count);
        if (error) *error = Ame429Error(PLComponentServiceErrorNetwork,
            localize(@"ame429.g.comp.list.failed", @"版本清单获取失败，请检查网络后重试"));
        return nil;
    }

    // ④ 直装器复用（事务性①：skipRegisterVersion=YES → 注册表零触碰；产物校验
    //   通过后安装器才落版本 JSON）。分流同源 = ModpackImportService L2702 口径
    //  （NeoForge 独立安装器；Forge 走 ForgeDirectInstaller 新旧双格式）。
    NSError *installError = nil;
    BOOL installed = NO;
    if ([vendor isEqualToString:PLComponentTypeNeoForge]) {
        installed = [NeoForgeDirectInstaller installNeoForgeFromInstaller:destPath
                                                                versionId:versionId
                                                            customGameDir:nil
                                                      skipRegisterVersion:YES
                                                                 progress:nil
                                                                    error:&installError];
    } else {
        installed = [ForgeDirectInstaller installForgeFromInstaller:destPath
                                                          versionId:versionId
                                                      customGameDir:nil
                                                skipRegisterVersion:YES
                                                           progress:nil
                                                              error:&installError];
    }
    [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    if (!installed) {
        NSLog(@"[Component] Task429: %@ direct install failed (ver=%@)", vendor,
              installError.localizedDescription ?: @"ok");
        if (error) *error = installError ?: Ame429Error(PLComponentServiceErrorInstall,
            localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更"));
        return nil;
    }

    // ⑤ 事务性闸门：版本 JSON 实体确认落盘才允许 repoint
    NSString *gameDir = Ame429GameDir() ?: NSHomeDirectory();
    NSString *jsonPath = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
    if (![NSFileManager.defaultManager fileExistsAtPath:jsonPath]) {
        NSLog(@"[Component] Task429: installer reported success but version JSON missing (%@)", jsonPath);
        if (error) *error = Ame429Error(PLComponentServiceErrorInstall,
            localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更"));
        return nil;
    }
    return versionId;
}

/// 实例 repoint（lastVersionId/javaVersion；必须主线程——注册表是 UI 读面）。
/// 仅当安装器返回 YES 且新版本 JSON 确认存在后调用（事务性③）。
+ (BOOL)ame429_repointProfileMainThread:(NSString *)profileName
                             toVersionId:(NSString *)newVersionId
                               mcVersion:(NSString *)mc
                                   error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *outError = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSMutableDictionary *profileDict = [PLProfiles.current.profiles objectForKey:profileName];
            if (![profileDict isKindOfClass:[NSMutableDictionary class]]) {
                outError = Ame429Error(PLComponentServiceErrorProfileMissing,
                    localize(@"ame429.g.comp.empty", @"未检测到组件（实例尚未安装版本）"));
            } else {
                // 活字典键改写（ameV13_writeProfileKey 同款：整体字典保留，绝不用
                // saveProfile:withName: 重建丢 versionSummary 等实例键）
                profileDict[@"lastVersionId"] = newVersionId;
                // javaVersion 重推（ForgeDirectInstaller.registerVersion 同语义：换装即
                // 按 MC 版本重算 Java 主版本；ModpackUtils.javaMajorVersionForMC 与
                // 注册版本推断同源口径，年份制 26.x → Java 25 一并覆盖）
                profileDict[@"javaVersion"] = [NSString stringWithFormat:@"%ld",
                    (long)[ModpackUtils javaMajorVersionForMC:mc]];
                [PLProfiles.current save];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
                NSLog(@"[Component] Task429: instance '%@' repointed -> %@", profileName, newVersionId);
                ok = YES;
            }
            dispatch_semaphore_signal(done);
        }
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (error) *error = outError;
    return ok;
}

#pragma mark - importOfflineJar（离线 jar 导入）

+ (void)importOfflineJar:(NSURL *)jarURL
       forComponentType:(NSString *)type
              forProfile:(NSString *)profileName
             completion:(void (^)(BOOL success,
                                  NSString * _Nullable newVersionId,
                                  NSError * _Nullable error))completion {
    void (^safeCompletion)(BOOL, NSString *, NSError *) = ^(BOOL success, NSString *newVersionId, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(success, newVersionId, error); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *resolvedProfile = profileName.length > 0 ? profileName : PLProfiles.current.selectedProfileName;
            if (resolvedProfile.length == 0) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorProfileMissing,
                    localize(@"ame429.g.comp.empty", @"未检测到组件（实例尚未安装版本）")));
                return;
            }
            if (![NSFileManager.defaultManager fileExistsAtPath:jarURL.path]) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorParse,
                    localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息")));
                return;
            }
            NSArray<Ame429ChainNode *> *chain = [self ame429_scanChainForProfile:resolvedProfile];
            NSString *mc = [self ame429_mcVersionForChain:chain];
            if (mc.length == 0) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorProfileMissing,
                    localize(@"ame429.g.comp.empty", @"未检测到组件（实例尚未安装版本）")));
                return;
            }

            // fabric/clean 无离线安装器形态（FCL 同限制：fabric 系无独立 installer jar，
            // 在线换装走 installComponent fabric 条目）
            if ([type isEqualToString:PLComponentTypeFabric] || [type isEqualToString:PLComponentTypeClean]) {
                safeCompletion(NO, nil, Ame429Error(PLComponentServiceErrorUnsupportedType,
                    localize(@"ame429.g.comp.import.fabric_notsupported",
                             @"Fabric 无离线安装器（换版请点 Fabric 条目在线安装）")));
                return;
            }

            NSError *err = nil;
            NSString *newVersionId = nil;
            if ([type isEqualToString:PLComponentTypeOptiFine]) {
                newVersionId = [self ame429_installOptiFineOfflineJar:jarURL
                                                            forProfile:resolvedProfile
                                                                    mc:mc
                                                              chain:chain
                                                                 error:&err];
            } else {
                NSString *vendor = [type isEqualToString:PLComponentTypeNeoForge]
                    ? PLComponentTypeNeoForge : PLComponentTypeForge;
                newVersionId = [self ame429_installForgeOfflineJar:jarURL vendor:vendor mc:mc error:&err];
            }
            if (newVersionId.length == 0) {
                safeCompletion(NO, nil, err ?: Ame429Error(PLComponentServiceErrorInstall,
                    localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更")));
                return;
            }
            NSError *repointError = nil;
            BOOL repointed = [self ame429_repointProfileMainThread:resolvedProfile
                                                        toVersionId:newVersionId
                                                          mcVersion:mc
                                                              error:&repointError];
            safeCompletion(repointed, repointed ? newVersionId : nil, repointed ? nil : repointError);
        }
    });
}

/// 离线安装器内单条目读取（ForgeDirectInstaller dataFromZip 同款 UZK API：
/// initWithPath + extractDataFromFile）
+ (nullable NSData *)ame429_dataFromZip:(NSURL *)jarURL entry:(NSString *)entry {
    NSError *openError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jarURL.path error:&openError];
    if (!archive) return nil;
    return [archive extractDataFromFile:entry error:nil];
}

/// Forge/NeoForge 离线安装器直装（DownloadViewController 本地安装器直装流同款：
/// 既有 ForgeDirectInstaller / NeoForgeDirectInstaller 离线路径复用）。
/// versionId 派生链：install_profile versionInfo.id（旧格式）→
/// install_profile.version（新格式，剥 "<mc>-" 复合前缀）→ 文件名派生
///（forge/neoforge 命名安装器）；全落空 → Parse 错误（诚实边界：不伪造版本号）。
+ (nullable NSString *)ame429_installForgeOfflineJar:(NSURL *)jarURL
                                              vendor:(NSString *)vendor
                                                  mc:(NSString *)mc
                                               error:(NSError **)error {
    NSData *profileData = [self ame429_dataFromZip:jarURL entry:@"install_profile.json"];
    NSMutableDictionary *installProfile = nil;
    if (profileData.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:profileData
                                                  options:NSJSONReadingMutableContainers
                                                    error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) installProfile = (NSMutableDictionary *)json;
    }
    NSString *pureLoader = nil;
    NSString *legacyId = nil;
    if ([installProfile isKindOfClass:[NSDictionary class]]) {
        // 旧格式（install_profile versionInfo.id）：官方复合 id 直接作版本实体 id
        id oldId = installProfile[@"versionInfo"][@"id"];
        if ([oldId isKindOfClass:[NSString class]] && ((NSString *)oldId).length > 0) {
            legacyId = (NSString *)oldId;
        }
        // 新格式（install_profile.version）：forge = "1.20.1-47.3.0" 复合形态 /
        // neoforge = "47.1.3" 纯段——统一剥 "<mc>-" 前缀取 pure 段
        id newVer = installProfile[@"version"];
        if ([newVer isKindOfClass:[NSString class]] && ((NSString *)newVer).length > 0) {
            pureLoader = (NSString *)newVer;
        }
    }
    if (pureLoader.length == 0) {
        // 文件名派生兜底："forge-1.20.1-47.3.0-installer.jar" / "neoforge-21.1.77-installer.jar"
        pureLoader = [self ame429_pureLoaderFromInstallerFilename:jarURL.lastPathComponent mc:mc];
    }
    NSString *compoundPrefix = [NSString stringWithFormat:@"%@-", mc];
    if ([pureLoader hasPrefix:compoundPrefix]) {
        pureLoader = [pureLoader substringFromIndex:compoundPrefix.length];
    }
    if (pureLoader.length == 0 && legacyId.length == 0) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParse,
            localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息"));
        return nil;
    }
    NSString *versionId = legacyId.length > 0
        ? legacyId
        : [NSString stringWithFormat:@"%@-%@-%@", mc,
            [vendor isEqualToString:PLComponentTypeNeoForge] ? @"neoforge" : @"forge", pureLoader];

    // 直装（事务性①同款：skipRegisterVersion=YES；产物校验通过才落版本 JSON）
    NSError *installError = nil;
    BOOL installed = NO;
    if ([vendor isEqualToString:PLComponentTypeNeoForge]) {
        installed = [NeoForgeDirectInstaller installNeoForgeFromInstaller:jarURL.path
                                                                versionId:versionId
                                                            customGameDir:nil
                                                      skipRegisterVersion:YES
                                                                 progress:nil
                                                                    error:&installError];
    } else {
        installed = [ForgeDirectInstaller installForgeFromInstaller:jarURL.path
                                                          versionId:versionId
                                                      customGameDir:nil
                                                skipRegisterVersion:YES
                                                           progress:nil
                                                              error:&installError];
    }
    if (!installed) {
        if (error) *error = installError ?: Ame429Error(PLComponentServiceErrorInstall,
            localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更"));
        return nil;
    }
    // 事务性闸门：版本 JSON 实体确认落盘
    NSString *gameDir = Ame429GameDir() ?: NSHomeDirectory();
    NSString *jsonPath = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
    if (![NSFileManager.defaultManager fileExistsAtPath:jsonPath]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorInstall,
            localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更"));
        return nil;
    }
    return versionId;
}

/// 安装器文件名 → pure loader 段（离线派生兜底；非官方命名返回 nil）
+ (nullable NSString *)ame429_pureLoaderFromInstallerFilename:(NSString *)filename mc:(NSString *)mc {
    if (filename.length == 0) return nil;
    NSString *stem = filename.pathExtension.length > 0
        ? [filename stringByDeletingPathExtension] : filename;
    for (NSString *prefix in @[@"forge-", @"neoforge-"]) {
        if ([stem hasPrefix:prefix]) {
            stem = [stem substringFromIndex:prefix.length];
            break;
        }
    }
    if ([stem hasSuffix:@"-installer"]) stem = [stem substringToIndex:stem.length - 10];
    NSString *compoundPrefix = [NSString stringWithFormat:@"%@-", mc];
    if ([stem hasPrefix:compoundPrefix]) stem = [stem substringFromIndex:compoundPrefix.length];
    // 残余形态须仍像版本号（仅数字/点/字母短横），排除误吞（防御守卫）
    if (stem.length == 0 || stem.length > 32) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if ([stem rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) return nil;
    return stem;
}

/// OptiFine 离线 jar 补丁流（ZL2GameAddonsViewController ame_installOptiFinePatch
/// 步骤 2-5 同口径最小实现；事务性加固：父版本存在性预检先于一切写入）。
/// 限制注释（诚实边界）：与既有补丁流同口径——单一 tweakClass
///（optifine.OptiFineTweaker）+ launchwrapper；forge 组合场景 tweakClass 合并
/// 语义以启动链 processVersion 为准，与既有流保持一致不做额外合成。
+ (nullable NSString *)ame429_installOptiFineOfflineJar:(NSURL *)jarURL
                                              forProfile:(NSString *)profileName
                                                      mc:(NSString *)mc
                                                    chain:(NSArray<Ame429ChainNode *> *)chain
                                                   error:(NSError **)error {
    // ① 文件名解析：OptiFine_<mc>_<type>_<patch>.jar（type 可含 "_"，末段 = patch；
    //   与 BMCLAPI 清单 {type:"HD_U",patch:"H1"} 载荷同构）
    NSString *filename = jarURL.lastPathComponent ?: @"";
    NSString *stem = filename.pathExtension.length > 0 ? [filename stringByDeletingPathExtension] : filename;
    NSArray *tokens = [stem componentsSeparatedByString:@"_"];
    if (tokens.count < 3 || ![tokens[0] isEqualToString:@"OptiFine"]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParse,
            localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息"));
        return nil;
    }
    NSString *optiPatch = tokens.lastObject;
    NSMutableArray *typeTokens = [NSMutableArray array];
    for (NSUInteger i = 2; i < tokens.count - 1; i++) [typeTokens addObject:tokens[i]];
    NSString *optiType = [typeTokens componentsJoinedByString:@"_"];
    if (optiType.length == 0 || optiPatch.length == 0) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParse,
            localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息"));
        return nil;
    }

    // ② 父版本决策：优先继承链上的 forge 版本实体（OptiFine×forge 共存语义，
    //   ZL2GameAddons 组合流同款 optifine 继承 forge 版本）；无 forge → MC 本体。
    //   fabric/neoforge 父环与 OptiFine 互斥（ame369 互斥表口径）→ 本流不提供，
    //   链上无 forge 时回退本体继承（纯 OptiFine 形态）。
    NSString *parent = mc;
    for (Ame429ChainNode *node in chain) {
        NSString *nodeType = [self ame429_detectTypeForNode:node];
        if ([nodeType isEqualToString:PLComponentTypeForge]) { parent = node.versionId; break; }
    }
    NSString *versionId = [NSString stringWithFormat:@"%@-OptiFine_%@_%@", parent, optiType, optiPatch];

    // ③ 事务性预检：父版本 JSON 必须已存在（先于一切写入——较既有补丁流的
    //   "写后检查"加固，失败路径零落盘）
    NSString *gameDir = Ame429GameDir() ?: NSHomeDirectory();
    NSString *parentJsonPath = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.json", parent, parent]];
    if (![NSFileManager.defaultManager fileExistsAtPath:parentJsonPath]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParentMissing,
            [NSString stringWithFormat:localize(@"ame429.g.comp.parent_missing_fmt",
                @"父版本 %@ 不存在，请先安装原版/加载器版本"), parent]);
        return nil;
    }

    // ④ jar 入 libraries（launchwrapper tweaker 语义，ame_installOptiFinePatch
    //   步骤 3 同款路径与 library name 形态）
    NSString *optifineLibRel = [NSString stringWithFormat:
        @"optifine/OptiFine/%@/%@.jar", parent, versionId];
    NSString *optifineLibAbs = [[gameDir stringByAppendingPathComponent:@"libraries"]
        stringByAppendingPathComponent:optifineLibRel];
    NSData *jarData = [NSData dataWithContentsOfFile:jarURL.path];
    if (jarData.length == 0) {
        if (error) *error = Ame429Error(PLComponentServiceErrorParse,
            localize(@"ame429.g.comp.import.parse_failed", @"未能解析安装器/清单版本信息"));
        return nil;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:
        [optifineLibAbs stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:nil];
    if (![jarData writeToFile:optifineLibAbs options:NSDataWritingAtomic error:nil]) {
        if (error) *error = Ame429Error(PLComponentServiceErrorInstall,
            localize(@"ame429.g.comp.failed", @"换装失败：实例状态未做任何变更"));
        return nil;
    }

    // ⑤ version.json（launchwrapper + OptiFineTweaker；字段 1:1 对齐
    //   ame_installOptiFinePatch 步骤 4——inheritsFrom/jar 均指父版本实体）
    //   ★Task430（一代 issue#24）：launchwrapper 库补齐——原实现只声明
    //   optifine:OptiFine 库而 mainClass=launchwrapper，launchwrapper 既不在
    //   原版 inheritsFrom 库表（1.13+ 原版已无 launchwrapper）也不在补丁
    //   jar 内 → ClassNotFoundException: net.minecraft.launchwrapper.Launcher
    //   → exit(1)。官方 OptiFine 安装器语义 = 嵌套 launchwrapper-of-<v>.jar
    //   解包 + libraries 追加本地库条目（helper 内含 1.12 在线兜底）。
    NSDictionary *ame430_lwLib = [self ame430_launchwrapperLibraryForOptiFineJar:jarURL.path
                                                                        gameDir:gameDir];
    NSDictionary *versionJson = @{
        @"id": versionId,
        @"inheritsFrom": parent,
        @"type": @"release",
        @"mainClass": @"net.minecraft.launchwrapper.Launcher",
        @"minecraftArguments": @"--username ${auth_player_name} --version ${version_name} --gameDir ${game_directory} --assetsDir ${assets_root} --assetIndex ${assets_index_name} --uuid ${auth_uuid} --accessToken ${auth_access_token} --userType ${user_type} --versionType ${version_type} --tweakClass optifine.OptiFineTweaker",
        @"libraries": @[@{
            @"name": [NSString stringWithFormat:@"optifine:OptiFine:%@", parent],
            @"downloads": @{@"artifact": @{
                @"path": optifineLibRel,
                @"url": @"",
                @"size": @(jarData.length),
                @"sha1": @""
            }}
        }, ame430_lwLib],
        @"jar": parent,
        @"minimumLauncherVersion": @21
    };
    NSString *versionDir = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@", versionId]];
    [[NSFileManager defaultManager] createDirectoryAtPath:versionDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *jsonPath = [versionDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.json", versionId]];
    NSError *saveError = saveJSONToFile(versionJson, jsonPath);
    if (saveError) {
        // 事务性回滚：JSON 落盘失败 → 删除半截 jar（零孤立引用）
        [[NSFileManager defaultManager] removeItemAtPath:optifineLibAbs error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:versionDir error:nil];
        if (error) *error = saveError;
        return nil;
    }
    NSLog(@"[Component] Task429: optifine offline patch installed %@ (parent=%@)", versionId, parent);
    return versionId;
}

#pragma mark - ★Task430 OptiFine launchwrapper 库补齐（一代 issue#24 根修）

/// ★Task430（一代 issue#24：OptiFine 装好即崩 "ClassNotFoundException:
/// net.minecraft.launchwrapper.Launcher" exit(1)，装机 58e4ff9 latestlog
/// 2026-11-08 19:27:41 实锤；二代两处 OptiFine 安装流生成的 version.json
/// 只声明 optifine:OptiFine 库 + mainClass=launchwrapper，而 launchwrapper
/// 既不在原版 inheritsFrom 库表（1.13+ 原版已无 launchwrapper）、也不在
/// OptiFine 补丁 jar 内 → URLClassLoader 必然找不到 → exit(1)）。
/// 官方 OptiFine 安装器语义复刻（OptiFine_1.20.1_HD_U_I5.jar 字节级实测）：
/// 安装器 jar 根目录内嵌 launchwrapper-of-<ver>.jar（2.3，sha1
/// 073b25f1667904d481b10f706288c95ea9656f0c），官方安装 = 解包落
/// libraries/optifine/launchwrapper-of/<ver>/launchwrapper-of-<ver>.jar
/// 并在 version.json libraries 追加 optifine:launchwrapper-of:<ver> 本地库。
/// 返回值 = 应追加进 versionJson.libraries 的 library 字典：
///   - 嵌套 launchwrapper-of 在场 → 本地库条目（url 空，本地文件直用，
///     Java 侧 generateLaunchClasspath 以文件存在性准入，既有判例链一致）；
///   - 无嵌套库/解压失败（旧形态或损坏）→ net.minecraft:launchwrapper:1.12
///     在线下载条目（libraries.minecraft.net 官方工件，sha1/size 实测写入）
///     ——自救优先，下载失败由下载链显式报错，不阻断安装主流程。
+ (NSDictionary *)ame430_launchwrapperLibraryForOptiFineJar:(NSString *)optifineJarPath
                                                     gameDir:(NSString *)gameDir {
    @try {
        NSError *zipErr = nil;
        UZKArchive *archive = [[UZKArchive alloc] initWithPath:optifineJarPath error:&zipErr];
        if (archive) {
            NSArray<NSString *> *names = [archive listFilenames:&zipErr];
            NSString *nested = nil;
            for (NSString *n in names) {
                if (n.length > 0 && ![n containsString:@"/"] &&
                    [n hasPrefix:@"launchwrapper-of-"] && [n hasSuffix:@".jar"]) { nested = n; break; }
            }
            if (nested) {
                NSData *lwData = [archive extractDataFromFile:nested error:&zipErr];
                if (lwData.length > 0) {
                    // launchwrapper-of-2.3.jar → 2.3
                    NSString *stem = [nested stringByDeletingPathExtension];
                    NSString *lwVer = [stem substringFromIndex:(NSUInteger)([@"launchwrapper-of-" length])];
                    NSString *lwRel = [NSString stringWithFormat:
                        @"optifine/launchwrapper-of/%@/launchwrapper-of-%@.jar", lwVer, lwVer];
                    NSString *lwAbs = [[gameDir stringByAppendingPathComponent:@"libraries"]
                        stringByAppendingPathComponent:lwRel];
                    [[NSFileManager defaultManager] createDirectoryAtPath:
                        [lwAbs stringByDeletingLastPathComponent]
                        withIntermediateDirectories:YES attributes:nil error:nil];
                    if ([lwData writeToFile:lwAbs options:NSDataWritingAtomic error:nil]) {
                        unsigned char ame430_dg[CC_SHA1_DIGEST_LENGTH];
                        CC_SHA1(lwData.bytes, (CC_LONG)lwData.length, ame430_dg);
                        NSMutableString *ame430_sha = [NSMutableString stringWithCapacity:40];
                        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [ame430_sha appendFormat:@"%02x", ame430_dg[i]];
                        NSLog(@"[Component] Task430: optifine nested launchwrapper-of-%@ extracted (%lu B, sha1 %@)", lwVer, (unsigned long)lwData.length, ame430_sha);
                        return @{@"name": [NSString stringWithFormat:@"optifine:launchwrapper-of:%@", lwVer],
                                 @"downloads": @{@"artifact": @{@"path": lwRel, @"url": @"",
                                     @"size": @(lwData.length), @"sha1": ame430_sha}}};
                    }
                    NSLog(@"[Component] Task430: launchwrapper-of write failed -- fallback to net.minecraft:launchwrapper:1.12");
                } else {
                    NSLog(@"[Component] Task430: nested launchwrapper-of extract failed%@ -- fallback to net.minecraft:launchwrapper:1.12",
                          zipErr ? [NSString stringWithFormat:@" (%@)", zipErr.localizedDescription] : @"");
                }
            } else {
                NSLog(@"[Component] Task430: no nested launchwrapper-of-*.jar in OptiFine jar -- fallback to net.minecraft:launchwrapper:1.12");
            }
        } else {
            NSLog(@"[Component] Task430: OptiFine jar not openable as zip%@ -- fallback to net.minecraft:launchwrapper:1.12",
                  zipErr ? [NSString stringWithFormat:@" (%@)", zipErr.localizedDescription] : @"");
        }
    } @catch (NSException *exc) {
        NSLog(@"[Component] Task430: launchwrapper extraction exception %@ -- fallback to net.minecraft:launchwrapper:1.12", exc);
    }
    // 兜底：net.minecraft:launchwrapper:1.12（libraries.minecraft.net 官方
    // 工件，Task430 实测 http 200 / 32999 B / sha1 111e7bea9c968cdb3d06ef4632bf7ff0824d0f36）
    return @{@"name": @"net.minecraft:launchwrapper:1.12",
             @"downloads": @{@"artifact": @{@"path": @"net/minecraft/launchwrapper/1.12/launchwrapper-1.12.jar",
                 @"url": @"https://libraries.minecraft.net/net/minecraft/launchwrapper/1.12/launchwrapper-1.12.jar",
                 @"size": @32999, @"sha1": @"111e7bea9c968cdb3d06ef4632bf7ff0824d0f36"}}};
}

@end
