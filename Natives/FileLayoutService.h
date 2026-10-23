//
//  FileLayoutService.h
//  Amethyst
//
//  Task316：游戏文件层桌面/安卓同构改造（用户指令"使用像桌面和安卓端的
//  启动器游戏文件逻辑…与其他平台通用的启动器直接文件迁移"）。
//
//  三件套：
//  A. 共享核心去重 —— 各实例的 versions/libraries/assets 迁入
//     POJAV_HOME/shared_core/ 并以符号链接回指（桌面 .minecraft 语义：
//     核心层全实例共用一份，GB 级重复清零）。
//  B. 整合包实例扁平化 —— 旧 instances/<inst>/custom_gamedir/<id> 双层
//     嵌套迁为顶层 instances/<id>（MultiMC 实例同构），profile gameDir
//     重写为绝对路径（Task275 F5 全链绝对路径直通口径，与当前实例解耦）。
//  C. 跨启动器导入器 —— 识别 .minecraft 全量根 / HMCL·PCL 版本隔离目录 /
//     MultiMC·Prism 实例 / ZL2·Pojav 安卓布局，核心层并轨、内容层逐文件
//     跳已存在合入（绝不覆盖用户既有数据，绝不删除源数据）。
//
//  迁移安全性：单向 marker（ame316_filelayout.done）幂等；仅 move 补缺/
//  符号链接化，绝不删除内容条目；异常逐项隔离（单项失败记日志继续）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FileLayoutService : NSObject

/// 一次性布局迁移（main.m 预 init 调用；marker 幂等，重复调用零开销）。
/// 迁移日志走 NSLog [FileLayout] ame316 前缀。
+ (void)ame316_migrateIfNeeded;

/// 跨启动器文件夹导入（文档选择器 URL，需安全作用域）。
/// 返回人类可读摘要（中文，含识别类型与各分类迁移计数）。
+ (NSString *)ame316_importExternalLauncherFolder:(NSURL *)folderURL error:(NSError **)error;

/// 当前实例根（POJAV_GAME_DIR；仅供导入器落位）。
+ (NSString *)ame316_currentGameDir;

@end

NS_ASSUME_NONNULL_END
