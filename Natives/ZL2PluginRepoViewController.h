#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginRepoViewController（Task 318 内置插件仓库）
// -------------------------------------------------------------------
// 浏览随包预置的示例插件（.app/builtin-plugins/<id>/）并一键安装：
//  · 列表 = 包内 builtin-plugins/ 子目录扫描 + manifest 校验（复用
//    AmePluginManager validateManifestDictionary，非法目录静默跳过）
//  · 安装 = 后台队列把插件目录打临时 zip（UZK writeData）→ 走
//    installFromZip 全量校验链（manifest/防逃逸/首装授权）→ 权限
//    预览 M3 对话框 → 自动装载（与手动导入流完全同链，零旁路）
//  · 已装项 = 直接 push 插件详情页（权限/启停/卸载管理在详情页）
// 入口：插件列表页顶栏「仓库」钮 + 设置→启动器 group3 行。
// ═══════════════════════════════════════════════════════════════════

@interface ZL2PluginRepoViewController : UIViewController
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
