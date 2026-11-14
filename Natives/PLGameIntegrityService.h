#import <Foundation/Foundation.h>
// ★Task428：契约体逐字采用（PDF v5 §3.3 任务书原文）；UIViewController
// 参数类型需要 UIKit——纯 Foundation 导入下该类型不可见，补一行 UIKit 导入
//（不影响契约接口文本，调用方按原签名调用）。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// ★Task428：游戏完整性校验与补全服务（HMCL checkGameState 对标，PDF v5 §3.3）
@interface PLGameIntegrityService : NSObject

+ (instancetype)sharedService;

/// 启动前快速校验（存在性级：版本 jar + libraries 清单 + assets 索引；后台线程执行，主线程回调）。
/// report 键：@"ok" (BOOL)、@"missing" (NSArray<NSString*>)、@"checked" (NSNumber)、@"profile" (NSString*)
- (void)preLaunchCheckForCurrentProfile:(void(^)(BOOL ok, NSDictionary<NSString *, id> * _Nullable report))completion;

/// 交互式「校验并补全」：自包含流程（进度 UI + 缺失/损坏/修复三类清单 + 补全执行走现有下载队列）
- (void)runInteractiveVerifyAndRepairFromViewController:(UIViewController *)presentingVC;

@end

NS_ASSUME_NONNULL_END
