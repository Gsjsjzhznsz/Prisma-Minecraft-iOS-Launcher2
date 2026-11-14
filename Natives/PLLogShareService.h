//
//  PLLogShareService.h
//  Amethyst
//
//  ★Task428（报告 5.3 日志上传系统）：logshare.cn 对接 + ZL2 双端点
//    failover 对标。此前全仓零网络上传（PLLogOutputView/PLCrashView 只有
//    UIActivityViewController 本地分享），本服务补上「上传并获取链接」通道。
//
//  契约要点：
//    · 主端点 https://api.logshare.cn（mclo.gs 中国镜像）POST /v1/log，
//      JSON body {files:[{name,content}]（≤200 个、展开合计 ≤20MiB 官方上限，
//      本服务按 2MB 简化阈值先行截尾）、source、metadata:[{key,value,label}]
//      （≤100 条）}；响应含 id / url（浏览页）/ raw（原始地址）/ 删除凭证
//      （字段名做兜底兼容）。
//    · 备端点 https://api.mclo.gs POST /1/log，application/x-www-form-
//      urlencoded，body content=<日志文本>；响应 {id, url, raw}。
//    · 大陆序 [logshare.cn, mclo.gs]，海外反序；逐个尝试，单端点 15s 超时，
//      全部失败才报错。
//    · 上传前正则脱敏（JWT / xuid / 命名 token / Bearer，只动明确凭证形态）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLLogShareService : NSObject

/// 单例（内部串行队列执行网络与文本清洗）
+ (instancetype)sharedService;

/// ★Task428：统一上传入口（后台线程执行、主线程回调）。
/// @param files       @{name:NSString, content:NSString} 字典数组（≤200 条，超出截断）
/// @param metadata    @{key, value, label} 字典数组（≤100 条，超出截断；可空）
/// @param completion  主线程回调：ok=YES 时 url/rawUrl 非空（deleteToken 仅
///                    logshare.cn 返回，mclo.gs 无删除凭证 → nil）
- (void)uploadFiles:(NSArray<NSDictionary<NSString *, NSString *> *> *)files
           metadata:(nullable NSArray<NSDictionary<NSString *, NSString *> *> *)metadata
         completion:(void (^)(BOOL ok, NSString * _Nullable url, NSString * _Nullable rawUrl,
                              NSString * _Nullable deleteToken, NSError * _Nullable error))completion;

/// ★Task428：采集 latestlog.txt → files 形态（文件缺失/为空返回空数组）
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_collectLatestlogFile;

/// ★Task428：采集崩溃三件套 → files 形态（latestlog.txt + fatal_trace.txt +
///   最新 hs_err_pid*.log，各自存在才带上；同 PLCrashView shareLog 证据链）
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_collectCrashFiles;

/// ★Task428：默认 metadata（启动器版本 / MC 版本 / 加载器——后两者从当前
///   profile lastVersionId 反解，取不到就只带启动器版本；版本串拼接
///   BuildTag.h ame415_buildTag）
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_buildDefaultMetadata;

/// ★Task428：脱敏（上传前对内容正则清洗，保守只动明确凭证形态）
+ (NSString *)ame428_redactLogContent:(NSString *)content;

/// ★Task428：尺寸策略（总载荷按 2MB 简化阈值执行；超限逐文件「保留最后
///   2000 行」截尾，name 保持原名不动，truncated 标记追加进 metadata）
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)ame428_applySizePolicy:(NSArray<NSDictionary<NSString *, NSString *> *> *)files
                                                          appendedMetadata:(NSMutableArray<NSDictionary<NSString *, NSString *> *> *)metadata;

/// ★Task428：大陆判据（仓内无既有地域探测 → Asia/Shanghai 时区 + zh 语言/CN
///   区域组合兜底）
+ (BOOL)ame428_isMainlandNetwork;

/// ★Task428：共用上传图标（CoreGraphics 自绘「上箭头+托盘」模板图，零 SF
///   Symbols；按钮 tint 着色，PLLogOutputView / PLCrashView 两视图共用）
+ (UIImage *)ame428_uploadIconImage;

@end

NS_ASSUME_NONNULL_END
