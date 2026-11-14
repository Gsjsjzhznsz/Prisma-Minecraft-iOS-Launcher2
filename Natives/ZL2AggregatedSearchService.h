//
// ZL2AggregatedSearchService.h — ★Task428（4.3）：聚合搜索服务
//
// 旧下载页 DownloadViewController.m 的 Task291 聚合搜索（ame291_* 家族）能力
// 服务化（复制适配而非搬移——旧页属 P2 退役对象，除收藏钮小改外保持原样
// 不动），供 ZL2 搜索页（ZL2AssetSearchViewController 平台档「聚合」，本任务
// 起为第一项且默认档）消费。
//
// 吸收 FCL DownloadPage.searchAggregated 四个成熟细节：
//   ① 双源并行：dispatch_group 并行打 Modrinth + CurseForge（同 filters 双路）；
//   ② 分类映射：filters[@"category"]（Modrinth slug 口径）双源透传——CF 侧由
//     CurseForgeAPI 异步搜索路径经 ame316 归一匹配 + 别名表解析 categoryId
//     （slug 精确 / name 小写 / 别名命中），失配时 CF 侧去分类参数回退继续
//     搜（本服务读 ame428_lastCategoryFallbackSlug 感知失配，并入 warning 交
//     UI 提示）；仅单侧有的分类，分类参数只在有映射的一侧生效（聚合档分类
//     值域为 Modrinth 口径，CF-only 分类不会出现在选择面，此分支实际不可达）；
//   ③ 单源失败降级：另一源结果照常返回（warning 带失败来源名），双源全失败
//     才以 error 返回——不整页报错；
//   ④ 交错合并：同序号 CurseForge 条目前置，slug/标题归一化去重（最近更新
//     时间相差 ≤7 天视为同一工程的同步数据，超窗/时间不可得则两平台条目
//     都显示——PCL 保守合并策略，FCL 同值）。
//
// 【头文件零 API 依赖】：只 import Foundation——不引入 ModrinthAPI.h /
// CurseForgeAPI.h 传递链（→ ModpackAPI.h → ModpackUtils.h → UnzipKit.h 在
// ui_fluent_smoke COMMON 的 -I（仅 Natives 根）下不可达；ZL2AssetSearchView
// Controller.m 7.0-UI-10-f #import 手术判例同源）。API 声明全部收在 .m 内的
// 本地最小 @interface。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2AggregatedSearchService : NSObject

+ (instancetype)sharedService;

/// 双源并行聚合搜索（FCL searchAggregated 语义）。filters 键与 ZL2 搜索页
/// 单源路径同构：limit / offset / query / projectType / isModpack / sort /
/// mcVersion / loader / category（Modrinth slug 口径）。
///
/// completion 主线程回调：
///   merged   交错合并后的结果数组（CurseForge 在前；条目自带 apiSource，
///            1=Modrinth / 2=CurseForge；双源全失败时为 nil）
///   cfTotal  CurseForge 响应 total（该侧失败时为 0；页码总数 = cfTotal +
///            mrTotal 的上界口径——去重后实际条数略少）
///   mrTotal  Modrinth 响应 total_hits（该侧失败时为 0）
///   hasMore  任一源本页满页（结果数 ≥ limit）即认为还有下一页
///   error    双源全失败时的错误（单源失败不报错，走 warning 降级）
///   warning  降级提示（单源失败 / CF 分类失配回退；已本地化可直显；
///            多条以换行连接；nil = 无降级）
- (void)searchAggregatedWithFilters:(NSDictionary *)filters
                         completion:(void (^)(NSArray<NSDictionary *> * _Nullable merged,
                                              NSUInteger cfTotal,
                                              NSUInteger mrTotal,
                                              BOOL hasMore,
                                              NSError * _Nullable error,
                                              NSString * _Nullable warning))completion;

/// CF 官方分类树（/categories?gameId=432&classId=X，按 classId 缓存，与
/// CurseForgeAPI ame316 同缓存池）。同步网络调用——调用方必须后台线程调用。
/// 返回 @{@"slug":…, @"name":…} 字典数组（ZL2 筛选面板源=CurseForge 档的
/// 分类值域；空数组 = 拉取失败 / 预览桩无网络层，调用方回退通用口径）。
- (NSArray<NSDictionary<NSString *, NSString *> *> *)curseForgeCategoryListForProjectType:(NSString *)projectType;

@end

NS_ASSUME_NONNULL_END
