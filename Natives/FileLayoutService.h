//
//  FileLayoutService.h
//  Amethyst
//
//  ★ Task483（单根终局）：ame316 instances 布局迁移（共享核心去重/整合包
//  实例扁平化）已随 instances 布局整体退役删除——单一真实数据根 = lasm
//  （Library/Application Support/minecraft），instances 目录永不重建；
//  存量收编由 main.m Task483 单根迁移承担。本文件仅保留跨启动器导入器：
//  C. 跨启动器导入器 —— 识别 .minecraft 全量根 / HMCL·PCL 版本隔离目录 /
//     MultiMC·Prism 实例 / ZL2·Pojav 安卓布局，核心层并轨、内容层逐文件
//     跳已存在合入（绝不覆盖用户既有数据，绝不删除源数据）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FileLayoutService : NSObject

// ★ Task483：ame316_migrateIfNeeded 已删除（instances 布局退役，
//   main.m 预 init 的单根迁移为唯一收编路径）。

/// 跨启动器文件夹导入（文档选择器 URL，需安全作用域）。
/// 返回人类可读摘要（中文，含识别类型与各分类迁移计数）。
+ (NSString *)ame316_importExternalLauncherFolder:(NSURL *)folderURL error:(NSError **)error;

/// 当前实例根（POJAV_GAME_DIR；仅供导入器落位）。
+ (NSString *)ame316_currentGameDir;

@end

NS_ASSUME_NONNULL_END
