//
//  PLLogShareService.m
//  Amethyst
//
//  ★Task428（报告 5.3 日志上传系统）实现。日志前缀统一 [Task428]。
//
//  双端点 failover 流（ZL2 对标）：
//    判定大陆（时区+语言组合）→ 排序端点（大陆 [logshare.cn, mclo.gs] /
//    海外反序）→ 逐端点尝试（15s 超时）→ 任一成功即回调 → 全部失败聚合
//    报错（用户可读 i18n 文案 + 技术细节附录）。
//
//  尺寸策略：总载荷 2MB 简化阈值（对齐 ZL2 拒传阈值口径）。超限逐文件
//    「保留最后 2000 行」（.tail 语义）——name 保持原名（任务示例明文
//    「latestlog.txt 尾部截断后 name 仍用原名」），truncated 标记以
//    "<name>.tail" 值追加进 metadata；行截尾仍超限（巨行长文）时字节级
//    截尾兜底（16KB 下限、对齐行边界）。
//
//  脱敏（保守，只动明确凭证形态）：
//    ① JWT（eyJ 头三段长串）→ «redacted»；
//    ② xuid 键位附近的 16 位数字 → «redacted»；
//    ③ access_token/clientToken 键位附近 ≥32 位十六进制/Base64 长串 → «redacted»；
//    ④ Authorization: Bearer ≥20 位凭证 → «redacted»。
//

#import "PLLogShareService.h"
#import "BuildTag.h"
#import "utils.h"
#import "PLProfiles.h"
#import "ModpackExportService.h"
#include <stdlib.h>

#pragma mark - 常量

/// 主端点：logshare.cn（mclo.gs 中国镜像）
static NSString *const kAme428LogshareAPI = @"https://api.logshare.cn";
/// logshare.cn 浏览页根（响应缺 url 字段时按 id 拼接兜底）
static NSString *const kAme428LogshareViewRoot = @"https://logshare.cn";
/// 备端点：mclo.gs 官方
static NSString *const kAme428MclogsAPI = @"https://api.mclo.gs";
/// mclo.gs 浏览页根
static NSString *const kAme428MclogsViewRoot = @"https://mclo.gs";
/// 单端点超时（秒）
static const NSTimeInterval kAme428EndpointTimeout = 15.0;
/// 总载荷简化拒传阈值（2MB，对齐 ZL2 口径）
static const NSUInteger kAme428MaxTotalBytes = 2 * 1024 * 1024;
/// logshare.cn files 契约上限
static const NSUInteger kAme428MaxFiles = 200;
/// logshare.cn metadata 契约上限
static const NSUInteger kAme428MaxMetadata = 100;
/// 超限截尾保留行数（.tail 语义）
static const NSUInteger kAme428TailLines = 2000;
/// 字节级截尾下限（行截尾仍超限时的最终手段）
static const NSUInteger kAme428ByteTailFloor = 16 * 1024;

NSString *const PLLogShareErrorDomain = @"PLLogShareService";
static const NSInteger kAme428ErrNoFiles = -1001;
static const NSInteger kAme428ErrBothEndpoints = -1003;

@interface PLLogShareService ()
/// 串行队列：网络发送 + 大文本正则清洗不占主线程，且天然防并发重入
@property(nonatomic, strong) dispatch_queue_t eme428_queue;
@end

@implementation PLLogShareService

#pragma mark - 单例

+ (instancetype)sharedService {
    static PLLogShareService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PLLogShareService alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _eme428_queue = dispatch_queue_create("cn.prisma.task428.logshare", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - 工具

/// POJAV_HOME 环境变量（日志三件套所在目录）
+ (NSString *)ame428_pojavHome {
    return @(getenv("POJAV_HOME") ?: "");
}

/// Java 日志可能混非 UTF-8 字节：UTF-8 优先，失败降级 Latin-1 保证全文可读
+ (NSString *)ame428_readTextFile:(NSString *)path {
    if (path.length == 0) return @"";
    NSString *text = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) {
        text = [NSString stringWithContentsOfFile:path
                                        encoding:NSISOLatin1StringEncoding error:nil];
    }
    return text ?: @"";
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_collectLatestlogFile {
    NSString *home = [self ame428_pojavHome];
    if (home.length == 0) return @[];
    NSString *path = [home stringByAppendingPathComponent:@"latestlog.txt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
    NSString *content = [self ame428_readTextFile:path];
    if (content.length == 0) return @[];
    return @[@{ @"name": @"latestlog.txt", @"content": content }];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_collectCrashFiles {
    NSString *home = [self ame428_pojavHome];
    if (home.length == 0) return @[];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];

    // ① latestlog.txt
    NSString *latestlogPath = [home stringByAppendingPathComponent:@"latestlog.txt"];
    if ([fm fileExistsAtPath:latestlogPath]) {
        NSString *content = [self ame428_readTextFile:latestlogPath];
        if (content.length > 0) {
            [out addObject:@{ @"name": @"latestlog.txt", @"content": content }];
        }
    }

    // ② fatal_trace.txt（Task27 fatal 证据链）
    NSString *tracePath = [home stringByAppendingPathComponent:@"fatal_trace.txt"];
    if ([fm fileExistsAtPath:tracePath]) {
        NSString *content = [self ame428_readTextFile:tracePath];
        if (content.length > 0) {
            [out addObject:@{ @"name": @"fatal_trace.txt", @"content": content }];
        }
    }

    // ③ 最新 hs_err_pid*.log（与 PLCrashView shareLog 同款扫描口径）
    NSArray *files = [fm contentsOfDirectoryAtPath:home error:nil];
    NSString *best = nil;
    NSDate *bestDate = nil;
    for (NSString *name in files) {
        if (![name isKindOfClass:NSString.class]) continue;
        if (![name hasPrefix:@"hs_err_pid"] || ![name hasSuffix:@".log"]) continue;
        NSString *p = [home stringByAppendingPathComponent:name];
        NSDate *d = [fm attributesOfItemAtPath:p error:nil][NSFileModificationDate];
        if (!bestDate || [d compare:bestDate] == NSOrderedDescending) {
            best = p;
            bestDate = d;
        }
    }
    if (best.length > 0) {
        NSString *content = [self ame428_readTextFile:best];
        if (content.length > 0) {
            [out addObject:@{ @"name": best.lastPathComponent, @"content": content }];
        }
    }
    return out;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_buildDefaultMetadata {
    // ★Task428：版本串拼接 BuildTag.h ame415_buildTag（构建代际单一事实源）
    NSString *appVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *versionValue = [NSString stringWithFormat:@"Prisma %@ · %@", appVer, ame415_buildTag];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *meta =
        [NSMutableArray arrayWithObject:@{ @"key": @"version",
                                           @"value": versionValue,
                                           @"label": @"Launcher" }];
    @try {
        // MC 版本 / 加载器：当前 profile lastVersionId 反解（与
        // DownloadViewController currentProfileMinecraftVersion/currentProfileLoader 同口径）
        NSDictionary *profile = [PLProfiles current].selectedProfile;
        if ([profile isKindOfClass:NSDictionary.class]) {
            NSString *lastVersionId = profile[@"lastVersionId"];
            if ([lastVersionId isKindOfClass:NSString.class] && lastVersionId.length > 0) {
                NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
                if ([parsed isKindOfClass:NSDictionary.class]) {
                    NSString *mc = parsed[@"minecraft"];
                    if ([mc isKindOfClass:NSString.class] && mc.length > 0) {
                        [meta addObject:@{ @"key": @"mc_version", @"value": mc, @"label": @"Minecraft" }];
                    }
                    NSString *loader = parsed[@"loader"];
                    if ([loader isKindOfClass:NSString.class] && loader.length > 0) {
                        [meta addObject:@{ @"key": @"loader", @"value": loader, @"label": @"Mod loader" }];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[Task428] metadata profile read failed: %@", exception);
    }
    return meta;
}

#pragma mark - 脱敏（保守正则，只动明确凭证形态）

+ (NSString *)ame428_redactLogContent:(NSString *)content {
    if (content.length == 0) return content;
    // 规则表（编译一次）：pattern + 替换模板（$1 保留键名前缀）
    static NSArray<NSDictionary *> *rules = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rules = @[
            // ① JWT：eyJ 头三段式长串
            @{ @"regex": @"eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}",
               @"template": @"«redacted»" },
            // ② xuid：键位附近的 16 位数字（键名原样保留）
            @{ @"regex": @"(?i)(xuid[\"']?\\s*[:=]\\s*[\"']?)\\d{16}([\"']?)",
               @"template": @"$1«redacted»$2" },
            // ③ access_token / clientToken：键位附近 ≥32 位长凭证串（hex/Base64）
            @{ @"regex": @"(?i)((?:access[_-]?token|client[_-]?token)[\"']?\\s*[:=]\\s*[\"']?)[A-Za-z0-9_\\-\\+\\/=\\.]{32,}",
               @"template": @"$1«redacted»" },
            // ④ Authorization: Bearer 凭证头
            @{ @"regex": @"(?i)(authorization[\"']?\\s*[:=]\\s*[\"']?bearer\\s+)[A-Za-z0-9_\\-\\+\\/=\\.]{20,}",
               @"template": @"$1«redacted»" },
        ];
    });
    @try {
        for (NSDictionary *rule in rules) {
            NSRegularExpression *regex = rule[@"regex"];
            if (![regex isKindOfClass:NSRegularExpression.class]) continue;
            content = [regex stringByReplacingMatchesInString:content
                                                       options:0
                                                         range:NSMakeRange(0, content.length)
                                                  withTemplate:rule[@"template"]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Task428] redact pass exception: %@", exception);
    }
    return content;
}

#pragma mark - 尺寸策略（2MB 简化阈值 + 尾部 2000 行截尾）

/// 保留最后 N 行（不足 N 行原样返回）
+ (NSString *)ame428_tailLinesOfString:(NSString *)string lines:(NSUInteger)lines {
    if (string.length == 0 || lines == 0) return @"";
    NSArray *all = [string componentsSeparatedByString:@"\n"];
    if (all.count <= lines) return string;
    NSRange range = NSMakeRange(all.count - lines, lines);
    NSArray *tail = [all subarrayWithRange:range];
    return [tail componentsJoinedByString:@"\n"];
}

/// 字节级尾部截取（UTF-16 计数近似字节预算；起点向后找行边界防切断多字节字符）
+ (NSString *)ame428_byteTailOfString:(NSString *)string budget:(NSUInteger)budget {
    if (string.length <= budget) return string;
    NSUInteger start = string.length - budget;
    NSRange nl = [string rangeOfString:@"\n" options:0
                                 range:NSMakeRange(start, string.length - start)];
    if (nl.location != NSNotFound && nl.location - start < 4096) {
        start = nl.location + 1;
    }
    return [string substringFromIndex:start];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_applySizePolicy:(NSArray<NSDictionary<NSString *, NSString *> *> *)files
                                                          appendedMetadata:(NSMutableArray<NSDictionary<NSString *, NSString *> *> *)metadata {
    if (files.count == 0) return files;
    // 拷贝为可变工作集（helper 标记键不外泄）
    NSMutableArray<NSMutableDictionary *> *working = [NSMutableArray array];
    NSUInteger total = 0;
    for (NSDictionary *file in files) {
        NSString *name = [file[@"name"] isKindOfClass:NSString.class] ? file[@"name"] : @"log.txt";
        NSString *content = [file[@"content"] isKindOfClass:NSString.class] ? file[@"content"] : @"";
        [working addObject:[NSMutableDictionary dictionaryWithDictionary:@{ @"name": name, @"content": content }]];
        total += content.length;
    }
    if (total <= kAme428MaxTotalBytes) return files;

    // ① 行截尾：总载荷超限时对「贡献最大的文件」保留最后 2000 行，循环到达标
    BOOL progress = YES;
    while (total > kAme428MaxTotalBytes && progress) {
        progress = NO;
        NSUInteger maxIdx = 0;
        for (NSUInteger i = 1; i < working.count; i++) {
            if ([working[i][@"content"] length] > [working[maxIdx][@"content"] length]) maxIdx = i;
        }
        NSMutableDictionary *file = working[maxIdx];
        if (![file[@"ame428_lineDone"] boolValue]) {
            file[@"ame428_lineDone"] = @YES;
            NSString *old = file[@"content"];
            NSString *tail = [self ame428_tailLinesOfString:old lines:kAme428TailLines];
            if (tail.length < old.length) {
                file[@"content"] = tail;
                total -= (old.length - tail.length);
                progress = YES;
                // ★Task428：name 保持原名（任务示例明文），truncated 标记以
                //   "<name>.tail" 值入 metadata（.tail 概念承载点）
                [metadata addObject:@{ @"key": @"truncated",
                                       @"value": [NSString stringWithFormat:@"%@.tail", file[@"name"]],
                                       @"label": @"Truncated to last 2000 lines" }];
            }
        }
    }

    // ② 字节截尾兜底：行截尾后仍超限（巨行长文）——按剩余预算截最大文件
    while (total > kAme428MaxTotalBytes) {
        NSUInteger maxIdx = 0;
        for (NSUInteger i = 1; i < working.count; i++) {
            if ([working[i][@"content"] length] > [working[maxIdx][@"content"] length]) maxIdx = i;
        }
        NSMutableDictionary *file = working[maxIdx];
        NSUInteger others = total - [file[@"content"] length];
        NSUInteger budget = (kAme428MaxTotalBytes > others) ? (kAme428MaxTotalBytes - others) : 0;
        if (budget < kAme428ByteTailFloor) budget = kAme428ByteTailFloor;
        NSString *old = file[@"content"];
        if (old.length <= budget) break;   // 全部触底（多文件叠加 16KB 下限的极端形态，接受轻微超额）
        NSString *tail = [self ame428_byteTailOfString:old budget:budget];
        file[@"content"] = tail;
        total -= (old.length - tail.length);
        if (![file[@"ame428_byteNoted"] boolValue]) {
            file[@"ame428_byteNoted"] = @YES;
            [metadata addObject:@{ @"key": @"truncated",
                                   @"value": [NSString stringWithFormat:@"%@.tail", file[@"name"]],
                                   @"label": @"Byte-tail truncated" }];
        }
    }

    // 剥离 helper 键 → 输出干净 {name, content}
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];
    for (NSMutableDictionary *file in working) {
        [out addObject:@{ @"name": file[@"name"], @"content": file[@"content"] }];
    }
    return out;
}

#pragma mark - 大陆判据

+ (BOOL)ame428_isMainlandNetwork {
    // 仓内无既有大陆探测（PLMirrorCenter 为测速竞速、无地域判定）→ 任务口径
    // 兜底：Asia/Shanghai 时区 AND（zh 语言 OR CN 区域）。时区条件覆盖大陆，
    // 与语言/区域组合避免海外华语用户被误判（海外默认 mclo.gs 优先）。
    // ★Task428-r2：NSTimeZone 无 identifier 属性（实名 name——CI run 43640652323
    //   编译雷，虚构属性族判例）
    NSString *tz = [NSTimeZone systemTimeZone].name;
    BOOL tzMainland = ([tz isEqualToString:@"Asia/Shanghai"] ||
                       [tz isEqualToString:@"Asia/Urumqi"] ||
                       [tz isEqualToString:@"Asia/Chongqing"] ||
                       [tz isEqualToString:@"Asia/Harbin"]);
    if (!tzMainland) return NO;
    NSString *lang = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
    NSString *region = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    BOOL zhLanguage = (lang.length > 0 && [lang hasPrefix:@"zh"]);
    BOOL cnRegion = [region isEqualToString:@"CN"];
    return (zhLanguage || cnRegion);
}

#pragma mark - 共用上传图标（CoreGraphics 自绘模板图）

+ (UIImage *)ame428_uploadIconImage {
    // 「上箭头 + 托盘」20×20 模板图（零 SF Symbols；tint 由按钮着色）
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20.0, 20.0), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:1.0].CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        // 箭头竖干
        CGContextMoveToPoint(ctx, 10.0, 3.5);
        CGContextAddLineToPoint(ctx, 10.0, 12.5);
        CGContextStrokePath(ctx);
        // 箭头双翼
        CGContextMoveToPoint(ctx, 5.8, 7.6);
        CGContextAddLineToPoint(ctx, 10.0, 3.4);
        CGContextAddLineToPoint(ctx, 14.2, 7.6);
        CGContextStrokePath(ctx);
        // 托盘（底横线 + 双侧短竖）
        CGContextMoveToPoint(ctx, 4.0, 13.6);
        CGContextAddLineToPoint(ctx, 4.0, 16.5);
        CGContextAddLineToPoint(ctx, 16.0, 16.5);
        CGContextAddLineToPoint(ctx, 16.0, 13.6);
        CGContextStrokePath(ctx);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) image = [UIImage new];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - 网络（端点尝试）

/// 同步发送（自有串行队列上阻塞等待；NSURLSession 回调在系统 delegate 队列，无死锁）
- (nullable NSDictionary *)ame428_sendRequest:(NSURLRequest *)request
                                    failNote:(NSString **)failNote {
    __block NSData *data = nil;
    __block NSURLResponse *response = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            data = d;
            response = r;
            requestError = e;
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    NSString *host = request.URL.host ?: @"";
    if (requestError) {
        if (failNote) *failNote = [NSString stringWithFormat:@"%@: %@", host, requestError.localizedDescription];
        return nil;
    }
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status < 200 || status >= 300) {
        if (failNote) *failNote = [NSString stringWithFormat:@"%@: HTTP %ld", host, (long)status];
        return nil;
    }
    if (data.length == 0) {
        if (failNote) *failNote = [NSString stringWithFormat:@"%@: empty response", host];
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (failNote) *failNote = [NSString stringWithFormat:@"%@: invalid JSON", host];
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)json;

    // 字段兜底解析：url/link、raw/raw_url/rawUrl、删除凭证 deletion_token/
    // delete_token/deletionToken/deleteToken/token（服务端字段名以实际响应为准）
    NSString * (^stringField)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *keys) {
        for (NSString *key in keys) {
            NSString *value = dict[key];
            if ([value isKindOfClass:NSString.class] && value.length > 0) return value;
        }
        return nil;
    };
    NSString *url = stringField(@[@"url", @"link"]);
    NSString *rawUrl = stringField(@[@"raw", @"raw_url", @"rawUrl"]);
    NSString *deleteToken = stringField(@[@"deletion_token", @"delete_token",
                                          @"deletionToken", @"deleteToken", @"token"]);
    NSString *logId = stringField(@[@"id"]);

    // url 缺失但 id 在 → 按端点浏览页根拼接兜底
    if (url.length == 0 && logId.length > 0) {
        if ([host containsString:@"logshare.cn"]) {
            url = [kAme428LogshareViewRoot stringByAppendingPathComponent:logId];
        } else {
            url = [kAme428MclogsViewRoot stringByAppendingPathComponent:logId];
        }
    }
    if (url.length == 0) {
        if (failNote) *failNote = [NSString stringWithFormat:@"%@: no url/id in response", host];
        return nil;
    }
    return @{ @"url": url,
              @"raw": (rawUrl ?: @""),
              @"deleteToken": (deleteToken ?: @"") };
}

/// mclo.gs 多文件合并（单文件直传；多文件以 ===== name ===== 分节）
+ (NSString *)ame428_combinedContentForMclogs:(NSArray<NSDictionary<NSString *, NSString *> *> *)files {
    if (files.count <= 1) {
        return files.firstObject[@"content"] ?: @"";
    }
    NSMutableString *combined = [NSMutableString string];
    for (NSUInteger i = 0; i < files.count; i++) {
        if (i > 0) [combined appendString:@"\n\n"];
        [combined appendFormat:@"===== %@ =====\n%@",
            files[i][@"name"] ?: @"log", files[i][@"content"] ?: @""];
    }
    return combined;
}

- (nullable NSDictionary *)ame428_tryEndpoint:(NSInteger)endpointIndex
                                         files:(NSArray<NSDictionary<NSString *, NSString *> *> *)files
                                      metadata:(NSArray<NSDictionary<NSString *, NSString *> *> *)metadata
                                     failNote:(NSString **)failNote {
    NSString *appVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    // ★Task428：source 拼接 BuildTag.h ame415_buildTag（任务口径「Prisma/7.x」的
    //   版本位 = bundle 短版本 + 构建代际标签）
    NSString *source = [NSString stringWithFormat:@"Prisma/%@ · %@", appVer, ame415_buildTag];

    NSMutableURLRequest *request = nil;
    if (endpointIndex == 0) {
        // logshare.cn：POST /v1/log（JSON：files/source/metadata）
        NSURL *url = [NSURL URLWithString:[kAme428LogshareAPI stringByAppendingString:@"/v1/log"]];
        if (!url) {
            if (failNote) *failNote = @"logshare.cn: bad URL";
            return nil;
        }
        NSError *encodeError = nil;
        NSData *body = [NSJSONSerialization dataWithJSONObject:
                        @{ @"files": files,
                           @"source": source,
                           @"metadata": (metadata ?: @[]) }
                                                           options:0
                                                             error:&encodeError];
        if (!body || encodeError) {
            if (failNote) *failNote = [NSString stringWithFormat:@"logshare.cn: payload encode failed (%@)",
                                       encodeError.localizedDescription];
            return nil;
        }
        request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        request.timeoutInterval = kAme428EndpointTimeout;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        request.HTTPBody = body;
    } else {
        // mclo.gs：POST /1/log（form-urlencoded：content=<文本>）
        NSURL *url = [NSURL URLWithString:[kAme428MclogsAPI stringByAppendingString:@"/1/log"]];
        if (!url) {
            if (failNote) *failNote = @"mclo.gs: bad URL";
            return nil;
        }
        NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
        [allowed addCharactersInString:@"-._~"];
        NSString *combined = [self.class ame428_combinedContentForMclogs:files];
        NSString *encoded = [combined stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        if (encoded.length == 0) {
            if (failNote) *failNote = @"mclo.gs: encode failed";
            return nil;
        }
        NSData *body = [[NSString stringWithFormat:@"content=%@", encoded]
            dataUsingEncoding:NSUTF8StringEncoding];
        request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        request.timeoutInterval = kAme428EndpointTimeout;
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        request.HTTPBody = body;
    }
    return [self ame428_sendRequest:request failNote:failNote];
}

#pragma mark - 统一入口（后台执行、主线程回调）

- (void)uploadFiles:(NSArray<NSDictionary<NSString *, NSString *> *> *)files
           metadata:(nullable NSArray<NSDictionary<NSString *, NSString *> *> *)metadata
         completion:(void (^)(BOOL ok, NSString * _Nullable url, NSString * _Nullable rawUrl,
                              NSString * _Nullable deleteToken, NSError * _Nullable error))completion {
    if (!completion) return;
    dispatch_async(self.eme428_queue, ^{
        // —— 入参规整（files ≤200 / metadata ≤100 契约钳制 + 类型防御）——
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *cleanFiles = [NSMutableArray array];
        for (NSDictionary *file in files) {
            if (cleanFiles.count >= kAme428MaxFiles) break;
            if (![file isKindOfClass:NSDictionary.class]) continue;
            NSString *name = [file[@"name"] isKindOfClass:NSString.class] ? file[@"name"] : @"log.txt";
            NSString *content = [file[@"content"] isKindOfClass:NSString.class] ? file[@"content"] : @"";
            if (content.length == 0) continue;
            [cleanFiles addObject:@{ @"name": name, @"content": content }];
        }
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *cleanMeta = [NSMutableArray array];
        for (NSDictionary *item in (metadata ?: @[])) {
            if (cleanMeta.count >= kAme428MaxMetadata) break;
            if (![item isKindOfClass:NSDictionary.class]) continue;
            [cleanMeta addObject:item];
        }

        if (cleanFiles.count == 0) {
            NSError *error = [NSError errorWithDomain:PLLogShareErrorDomain
                                                 code:kAme428ErrNoFiles
                                             userInfo:@{ NSLocalizedDescriptionKey: localize(@"ame428.upload.no_content", nil) }];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, nil, nil, error);
            });
            return;
        }

        // —— 脱敏 + 尺寸策略（先脱敏后截尾：凭证洗掉再算载荷）——
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *redactedFiles = [NSMutableArray array];
        for (NSDictionary<NSString *, NSString *> *file in cleanFiles) {
            [redactedFiles addObject:@{ @"name": file[@"name"],
                                        @"content": [self.class ame428_redactLogContent:file[@"content"]] }];
        }
        NSArray<NSDictionary<NSString *, NSString *> *> *finalFiles =
            [self.class ame428_applySizePolicy:redactedFiles appendedMetadata:cleanMeta];

        // —— 双端点 failover：大陆序 [logshare.cn, mclo.gs]，海外反序 ——
        BOOL mainland = [self.class ame428_isMainlandNetwork];
        NSArray<NSNumber *> *order = mainland ? @[@0, @1] : @[@1, @0];
        NSUInteger totalBytes = 0;
        for (NSDictionary<NSString *, NSString *> *file in finalFiles) totalBytes += [file[@"content"] length];
        NSLog(@"[Task428] upload begin: %lu file(s), %lu bytes, mainland=%d, order=%@",
              (unsigned long)finalFiles.count, (unsigned long)totalBytes, mainland,
              mainland ? @"logshare.cn→mclo.gs" : @"mclo.gs→logshare.cn");

        NSMutableArray<NSString *> *failNotes = [NSMutableArray array];
        for (NSNumber *endpointIndex in order) {
            NSString *failNote = nil;
            NSDictionary *result = [self ame428_tryEndpoint:endpointIndex.integerValue
                                                       files:finalFiles
                                                    metadata:cleanMeta
                                                   failNote:&failNote];
            if (result) {
                NSLog(@"[Task428] upload ok via endpoint %ld: %@",
                      (long)endpointIndex.integerValue, result[@"url"]);
                NSString *url = result[@"url"];
                NSString *rawUrl = [result[@"raw"] length] > 0 ? result[@"raw"] : nil;
                NSString *deleteToken = [result[@"deleteToken"] length] > 0 ? result[@"deleteToken"] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, url, rawUrl, deleteToken, nil);
                });
                return;
            }
            if (failNote.length > 0) [failNotes addObject:failNote];
            NSLog(@"[Task428] endpoint %ld failed: %@", (long)endpointIndex.integerValue, failNote);
        }

        // —— 全部失败：聚合报错（i18n 主文案 + 技术细节附录）——
        NSString *detail = [failNotes componentsJoinedByString:@"; "];
        NSString *message = localize(@"ame428.upload.failed_both", nil);
        if (detail.length > 0) {
            message = [NSString stringWithFormat:@"%@ (%@)", message, detail];
        }
        NSError *error = [NSError errorWithDomain:PLLogShareErrorDomain
                                             code:kAme428ErrBothEndpoints
                                         userInfo:@{ NSLocalizedDescriptionKey: message }];
        NSLog(@"[Task428] upload failed on both endpoints: %@", message);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, nil, nil, nil, error);
        });
    });
}

@end
