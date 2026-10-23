#pragma once

// ═══════════════════════════════════════════════════════════════════
// AmePlugin 插件系统伞头文件（Task 317）
// -------------------------------------------------------------------
// 消费方按需 import 本文件即可拿到全套 API：
//   AmePluginRuntime    — 装载/启停/事件派发（外部只与它说话）
//   AmePluginManager    — 发现/安装/卸载/manifest 校验
//   AmePluginPermissions— 权限注册表/授权存取/运行时检查
//   AmePluginBridge     — 桥接 API 面（Runtime 内部注入，勿直接用）
// 主题令牌覆盖钩子在 ZL2Theme.h（ame317_setPluginThemeTokens）。
// ═══════════════════════════════════════════════════════════════════

#import "AmePluginPermissions.h"
#import "AmePluginManager.h"
#import "AmePluginBridge.h"
#import "AmePluginRuntime.h"
#import "ZL2PluginListViewController.h"
#import "ZL2PluginDetailViewController.h"
