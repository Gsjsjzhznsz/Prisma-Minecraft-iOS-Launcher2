#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginListViewController（Task 317）
// -------------------------------------------------------------------
// 插件管理主页（MD3）：
//   · 已装插件卡列表（名称/版本/作者 + 启用开关 ZL2M3Switch）→ 点卡进详情
//   · 右上 + = 安装 .ameplugin（文档选择器选 zip → 校验 → 权限确认弹窗）
//   · 「插件贡献行」区 = 启用中插件经 ui.rows 添加的启动器设置行
// ═══════════════════════════════════════════════════════════════════

@interface ZL2PluginListViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
