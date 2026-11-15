//
// ZL2AggregatedSearchService.m — ★Task428（4.3）：聚合搜索服务实现
//
// 实现细节与旧页 DownloadViewController.m Task291（ame291_* 家族）逐段对表
// （复制适配）：normalizeKey / parseISO8601 / 7 天合并窗口 / addIfDistinct /
// mergeCurse（CF 前置交错）为算法同款复制；双源并行 + 单源降级 warning 为
// ame291_aggregateFetchWithFilters 同语义服务化（分页推进从"两源结果计数"
// 升级为"两源 total + hasMore"以适配 ZL2 页码控制器）。
//

#import "ZL2AggregatedSearchService.h"
#import "utils.h"   // localize：降级提示文案（ame291 既有键复用 + ame428 新键）

// ★Task428：#import 手术口径（ZL2AssetSearchViewController.m 7.0-UI-10-f 判例
// 同源）：ModrinthAPI.h / CurseForgeAPI.h 的传递链（→ ModpackAPI.h →
// ModpackUtils.h → UnzipKit.h）在 ui_fluent_smoke COMMON 的 -I（仅 Natives
// 根）下不可达——本 TU 以本地最小 @interface 替代真实头（签名逐条照抄
// installer/modpack/ModrinthAPI.h / CurseForgeAPI.h，仅收本 TU 消费面）。
// ame428/classID 系列成员预览桩（Natives/Preview/ZL2PagesStub.m）暂未提供
// ——运行时 respondsToSelector 守卫降级（预览无网络层：分类相关路径直接走
// "无分类"语义，不崩不假红）；正式构建由真实 .m 提供实现。
@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
@property (nonatomic, assign) NSUInteger lastSearchTotalCount;
@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;
@property (nonatomic, assign) NSUInteger lastSearchTotalCount;
// ★Task428（4.4）：分类失配回退感知（异步搜索路径写侧置位）
@property (nonatomic, copy, nullable) NSString *ame428_lastCategoryFallbackSlug;
// ★Task429 N6b：读后即清（take 语义）消费口（真实 .h 同名声明照抄）
- (nullable NSString *)ame428_takeLastCategoryFallbackSlug;
// classId 推导与 CF 分类树列举（CurseForgeAPI.h ★Task428 起公开的成员）
- (nullable NSNumber *)classIDForProjectType:(NSString *)projectType;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_categoryListForClassId:(NSInteger)classId;
@end

@implementation ZL2AggregatedSearchService

+ (instancetype)sharedService {
    static ZL2AggregatedSearchService *ame428_shared = nil;
    static dispatch_once_t ame428_once;
    dispatch_once(&ame428_once, ^{
        ame428_shared = [[ZL2AggregatedSearchService alloc] init];
    });
    return ame428_shared;
}

#pragma mark - FCL ④：归一化去重 + 交错合并（旧页 ame291_* 算法同款复制）

/// 条目唯一键：仅保留字母数字并转小写（FCL normalizeKey 同语义；
/// 空串返回 nil 不参与去重）
+ (NSString *)ame428_normalizeKey:(NSString *)value {
    if (value.length == 0) return nil;
    NSMutableString *normalized = [NSMutableString stringWithCapacity:value.length];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
            [normalized appendFormat:@"%C", c];
        }
    }
    NSString *key = normalized.lowercaseString;
    return key.length > 0 ? key : nil;
}

/// ISO8601 时间戳解析（Modrinth date_modified / CurseForge dateModified 同构；
/// 失败返回 0）
+ (NSTimeInterval)ame428_parseISO8601:(NSString *)value {
    if (value.length == 0) return 0;
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'";
    });
    NSDate *date = [formatter dateFromString:value];
    if (!date) {
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        date = [formatter dateFromString:value];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'";
    }
    return date ? [date timeIntervalSince1970] : 0;
}

/// 跨平台保守合并窗口：最近更新时间相差 ≤7 天才视为同一工程的同步数据
/// （PCL 策略，FCL 同值；旧页 kAme291MergeWindowSeconds 同款）
static const NSTimeInterval kAme428MergeWindowSeconds = 7.0 * 24.0 * 3600.0;

/// ★Task429 N6a：聚合等待总上界（秒）——仅对 completion 悬挂场景兜底降级
///   （与 N7 端点信号量上界 20s 同族；正常慢响应由源自身 timeoutInterval
///   承接，不在此截断）
static const NSTimeInterval kAme428AggWaitCapSeconds = 20.0;

/// 去重入列：slug 优先、标题兜底双键；命中且时间同步（≤7 天窗）视为重复
/// 跳过，时间不可得或差超窗则两平台条目都显示（数据不同步时的保守策略）
+ (void)ame428_addIfDistinct:(NSDictionary *)item
                        into:(NSMutableArray<NSDictionary *> *)merged
                        seen:(NSMutableDictionary<NSString *, NSNumber *> *)seen {
    NSString *slugKey = [self ame428_normalizeKey:item[@"slug"]];
    NSString *titleKey = [self ame428_normalizeKey:item[@"title"]];
    NSString *hitKey = nil;
    if (slugKey.length > 0 && seen[[@"slug:" stringByAppendingString:slugKey]] != nil) {
        hitKey = [@"slug:" stringByAppendingString:slugKey];
    } else if (titleKey.length > 0 && seen[[@"title:" stringByAppendingString:titleKey]] != nil) {
        hitKey = [@"title:" stringByAppendingString:titleKey];
    }
    NSTimeInterval modified = [self ame428_parseISO8601:item[@"lastUpdated"]];
    if (hitKey != nil) {
        NSTimeInterval existing = [seen[hitKey] doubleValue];
        NSTimeInterval delta = (existing > modified) ? (existing - modified) : (modified - existing);
        if (existing <= 0 || modified <= 0 || delta > kAme428MergeWindowSeconds) {
            [merged addObject:item];
        }
        return;
    }
    if (slugKey.length > 0) seen[[@"slug:" stringByAppendingString:slugKey]] = @(modified);
    if (titleKey.length > 0) seen[[@"title:" stringByAppendingString:titleKey]] = @(modified);
    [merged addObject:item];
}

/// 交错合并：同序号 CurseForge 前置（FCL 同语义）
+ (NSMutableArray<NSDictionary *> *)ame428_mergeCurseForge:(NSArray *)curseForge
                                                  modrinth:(NSArray *)modrinth {
    NSMutableArray *merged = [NSMutableArray arrayWithCapacity:curseForge.count + modrinth.count];
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    NSUInteger count = MAX(curseForge.count, modrinth.count);
    for (NSUInteger i = 0; i < count; i++) {
        if (i < curseForge.count) [self ame428_addIfDistinct:curseForge[i] into:merged seen:seen];
        if (i < modrinth.count) [self ame428_addIfDistinct:modrinth[i] into:merged seen:seen];
    }
    return merged;
}

#pragma mark - ①②③：双源并行 + 分类映射 + 单源失败降级

- (void)searchAggregatedWithFilters:(NSDictionary *)filters
                         completion:(void (^)(NSArray<NSDictionary *> * _Nullable,
                                              NSUInteger,
                                              NSUInteger,
                                              BOOL,
                                              NSError * _Nullable,
                                              NSString * _Nullable))completion {
    if (!completion) return;

    // 页大小（hasMore 满页判定基准；缺省 30 = ZL2 搜索页页大小）
    NSInteger ame428_limit = 30;
    if ([filters[@"limit"] respondsToSelector:@selector(integerValue)]) {
        NSInteger ame428_rawLimit = [filters[@"limit"] integerValue];
        if (ame428_rawLimit > 0) ame428_limit = ame428_rawLimit;
    }

    // ② 分类映射：filters 整体透传双源（Modrinth 侧消费 @"category" 同步键 /
    //     CF 侧由异步路径 ame316 解析 categoryId，失配回退 + 感知标记——
    //     见类头注释与 CurseForgeAPI.m ★Task428 段）
    NSDictionary *ame428_cfFilters = [filters copy];
    NSDictionary *ame428_mrFilters = [filters copy];

    __block NSArray *ame428_cfResults = nil;
    __block NSArray *ame428_mrResults = nil;
    __block NSError *ame428_cfError = nil;
    __block NSError *ame428_mrError = nil;
    dispatch_group_t ame428_group = dispatch_group_create();
    dispatch_queue_t ame428_queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    // ① 双源并行（CF 不可用时单跑 Modrinth——Task162 口径下 CF 恒可用，
    //    此分支为防御位；另一源结果照常返回，warning 降级不整页报错）
    BOOL ame428_cfAvailable = [CurseForgeAPI isSourceAvailable];
    if (ame428_cfAvailable) {
        dispatch_group_enter(ame428_group);
        dispatch_async(ame428_queue, ^{
            [[CurseForgeAPI sharedInstance] searchModWithFilters:ame428_cfFilters
                                                       completion:^(NSArray *results, NSError *error) {
                ame428_cfResults = results;
                ame428_cfError = error;
                dispatch_group_leave(ame428_group);
            }];
        });
    }
    dispatch_group_enter(ame428_group);
    dispatch_async(ame428_queue, ^{
        [[ModrinthAPI sharedInstance] searchModWithFilters:ame428_mrFilters
                                                completion:^(NSArray *results, NSError *error) {
            ame428_mrResults = results;
            ame428_mrError = error;
            dispatch_group_leave(ame428_group);
        }];
    });

    // ★Task429 N6a（第六版报告）：dispatch_group_notify 恒等全源回源——任一源
    //   completion 丢失/悬挂则 completion 永不触发 = 整页 spinner 永久卡死。
    //   修法：等待加上限降级——后台 dispatch_group_wait 20s 上界（与 N7 端点
    //   信号量上界同族；仅对"超时机制失效"的悬挂场景兜底），超时按已回源
    //   先渲染，单源缺席走下方既有 aggregate_partial 降级提示（Toast 注明
    //   部分结果）。notify 退役后迟到侧 completion 无二次回调点（enter/leave
    //   仍配平，迟到结果只落变量不再触发渲染）。
    dispatch_async(ame428_queue, ^{
        if (dispatch_group_wait(ame428_group,
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(kAme428AggWaitCapSeconds * NSEC_PER_SEC))) != 0) {
            NSLog(@"[Agg] ★Task429 N6a: aggregate wait timeout (%.0fs) -- render partial results",
                  kAme428AggWaitCapSeconds);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *ame428_cf = [ame428_cfResults isKindOfClass:NSArray.class] ? ame428_cfResults : nil;
            NSArray *ame428_mr = [ame428_mrResults isKindOfClass:NSArray.class] ? ame428_mrResults : nil;

            // ③ 双源全失败 → error（旧页 ame291.dl.aggregate_failed 同款文案）
            if (ame428_cf == nil && ame428_mr == nil) {
                NSError *ame428_error = ame428_cfError ?: ame428_mrError
                    ?: [NSError errorWithDomain:@"ZL2AggregatedSearchService" code:-428
                                       userInfo:@{NSLocalizedDescriptionKey: localize(@"ame291.dl.aggregate_failed", nil)}];
                completion(nil, 0, 0, NO, ame428_error, nil);
                return;
            }

            // ④ 交错合并（CurseForge 前置）+ slug/标题归一化去重
            NSMutableArray<NSDictionary *> *ame428_merged =
                [ZL2AggregatedSearchService ame428_mergeCurseForge:(ame428_cf ?: @[])
                                                          modrinth:(ame428_mr ?: @[])];

            // 分页 total：仅计成功侧（失败侧 lastSearchTotalCount 是陈旧值不作数；
            // 成功侧写侧在 completion 回调前赋值，读侧在此之后——happens-before 成立）
            NSUInteger ame428_cfTotal = 0;
            NSUInteger ame428_mrTotal = 0;
            if (ame428_cf != nil) {
                ame428_cfTotal = [[CurseForgeAPI sharedInstance] lastSearchTotalCount];
            }
            if (ame428_mr != nil) {
                ame428_mrTotal = [[ModrinthAPI sharedInstance] lastSearchTotalCount];
            }
            BOOL ame428_hasMore = (ame428_cf.count >= (NSUInteger)ame428_limit ||
                                   ame428_mr.count >= (NSUInteger)ame428_limit);

            // ③ 单源失败/缺席降级提示（另一源照常返回；旧页 ame291.dl.aggregate_partial
            //    同款——★Task429 N6a 超时降级同走此口 = Toast 注明部分结果）
            NSMutableArray<NSString *> *ame428_warnings = [NSMutableArray array];
            if (ame428_cf == nil && ame428_mr != nil) {
                [ame428_warnings addObject:[NSString stringWithFormat:localize(@"ame291.dl.aggregate_partial", nil),
                                            localize(@"ame291.dl.source_curseforge", nil),
                                            localize(@"ame291.dl.source_modrinth", nil)]];
            } else if (ame428_mr == nil && ame428_cf != nil) {
                [ame428_warnings addObject:[NSString stringWithFormat:localize(@"ame291.dl.aggregate_partial", nil),
                                            localize(@"ame291.dl.source_modrinth", nil),
                                            localize(@"ame291.dl.source_curseforge", nil)]];
            }

            // ② CF 分类失配回退提示（CF 侧照常返回全部结果；感知标记由 CF 异步
            //    路径写侧在请求发出前置位，读侧在此之后——顺序安全。预览桩未
            //    实现该成员时静默跳过。★Task429 N6b：读后即清（take 语义），
            //    单例粘态不再跨请求串味）
            if ([[CurseForgeAPI sharedInstance] respondsToSelector:@selector(ame428_takeLastCategoryFallbackSlug)]) {
                NSString *ame428_cfFallback =
                    [(CurseForgeAPI *)[CurseForgeAPI sharedInstance] ame428_takeLastCategoryFallbackSlug];
                if (ame428_cfFallback.length > 0) {
                    [ame428_warnings addObject:localize(@"ame428.agg.category_fallback",
                                                        @"该分类在 CurseForge 不存在，CF 侧已回退全部结果")];
                }
            }

            NSString *ame428_warning = (ame428_warnings.count > 0)
                ? [ame428_warnings componentsJoinedByString:@"\n"] : nil;
            completion(ame428_merged, ame428_cfTotal, ame428_mrTotal, ame428_hasMore, nil, ame428_warning);
        });
    });
}

#pragma mark - CF 分类树（ZL2 筛选面板 CF 口径值域）

- (NSArray<NSDictionary<NSString *, NSString *> *> *)curseForgeCategoryListForProjectType:(NSString *)projectType {
    if (![projectType isKindOfClass:NSString.class] || projectType.length == 0) {
        projectType = @"mod";
    }
    CurseForgeAPI *ame428_cf = [CurseForgeAPI sharedInstance];
    // 预览桩守卫：未实现 CF 分类成员（无网络层）→ 空表，调用方回退通用口径
    if (![ame428_cf respondsToSelector:@selector(ame428_categoryListForClassId:)] ||
        ![ame428_cf respondsToSelector:@selector(classIDForProjectType:)]) {
        return @[];
    }
    NSNumber *ame428_classId = [ame428_cf classIDForProjectType:projectType];
    if (![ame428_classId isKindOfClass:NSNumber.class]) return @[];
    return [ame428_cf ame428_categoryListForClassId:[ame428_classId integerValue]];
}

@end
