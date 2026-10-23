#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginDetailViewController（Task 317）
// -------------------------------------------------------------------
// 插件详情：信息卡 / 启用开关 / 权限组实时开关（高危红标）/ 卸载。
// 权限翻转实时生效：授权=下一次桥接调用即通过；撤权=下一次调用即拒；
// 运行中插件的权限变更走静默重载保证贡献行/主题令牌状态一致。
// ═══════════════════════════════════════════════════════════════════

@interface ZL2PluginDetailViewController : UIViewController
- (instancetype)initWithPluginId:(NSString *)pluginId NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
