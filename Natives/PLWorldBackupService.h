//
//  PLWorldBackupService.h
//  Amethyst
//
//  ★Task429（PDF 六 §4.4「Horizon 支持 S1 速齐」世界备份四件之三）：新 TU。
//
//  世界存档 备份/复制/删除/恢复 服务（纯服务层，无 UI——弹层在
//  ZL2VersionPages.m 概览页，与「导出整合包」入口并列）：
//    · 备份：世界目录 zip 化（UnzipKit 写器——世界导入/解压链同库对称；
//      仓内另有 DataTransferService ame224 自研 store 级 zip 写器先例，其为
//      POJAV_HOME 全量分区导出专用流水线，不直接复用）；
//    · 删除：回收站语义——移入 POJAV_HOME/trash/<时间戳>/ 而非直删；
//    · 恢复：备份 zip 解到 staging → 顶层目录识别 + level.dat 校验 →
//      同名现存档先入回收站 → 落回目标 saves/；
//    · 复制：saves/ 内就地深拷贝（_Copy 去重后缀）。
//
//  ★同源红线（第六版 §3.3）：世界列表源目录与恢复目标目录统一走
//  +ame429_s1_gameDirForProfileName:versionId: 取值——PLProfiles 隔离决策树
//  （显式 gameDir → Task225 嗅探 → Task428 版本级有效隔离）与 JavaLauncher
//  启动链 gameDir 解析同源。隔离态实例的存档必须落 versions/<vid>/saves/，
//  恢复到共享根的存档在隔离态下游戏读不到（决策树判例）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLWorldBackupService : NSObject

#pragma mark 目录解析（PLProfiles 隔离决策树——与启动路径同源）

/// 解析某实例（profile）在指定版本（vid）下的游戏数据根目录。
/// 解析链（JavaLauncher :3010-3089 同源只读版）：
///   ① profile[@"gameDir"] 显式绝对路径 → 原样；显式相对路径 → 相对
///      POJAV_GAME_DIR 拼接（剥 "./" 前缀）；
///   ② 缺失 / "." / "./"（实例隔离未开形态）→ Task225 隔离嗅探
///      （+[ModService ame225_sniffedIsolationGameDirForProfile:]）→ 未命中
///      回落 POJAV_GAME_DIR；
///   ③ vid 非空且非 latest 别名 → PLProfiles 隔离决策树 B 层
///      （+ame428_effectiveIsolationForVid:profile:）：1=隔离 → versions/<vid>/
///      （0=共享 → 仅当现值恰为 versions/<vid> 形时重指回实例根；-1=自定义
///      路径 / latest 别名 → 零触碰，保留 ①② 结果）。
/// 备份源（世界列表枚举）与恢复目标（落回 saves/）统一走本方法。
/// env 双缺（POJAV_GAME_DIR/POJAV_HOME）时 NSHomeDirectory 兜底（防御守卫，
/// 与 ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName 同口径）。
+ (nullable NSString *)ame429_s1_gameDirForProfileName:(nullable NSString *)profileName
                                              versionId:(nullable NSString *)versionId;

/// 备份 zip 存放根：POJAV_HOME/world_backups/（env 缺失 → NSHomeDirectory 兜底）。
+ (NSString *)ame429_s1_backupsRoot;

/// 回收站根：POJAV_HOME/trash/（env 缺失 → NSHomeDirectory 兜底）。
+ (NSString *)ame429_s1_trashRoot;

#pragma mark 世界列表（源目录 = 决策树 gameDir/saves）

/// 枚举 gameDir/saves/ 下的有效世界（子目录 + level.dat 存在判据，与
/// WorldService 扫描同判据）。每项：name（目录名）/ path / modified（NSDate）/
/// size（NSNumber 字节）。同步方法，调用方自行放后台队列。
+ (NSArray<NSDictionary *> *)ame429_s1_listWorldsForGameDir:(NSString *)gameDir;

#pragma mark 备份（世界目录 → zip）

/// 备份单个世界目录：zip 落 backupsRoot/<世界名>_<时间戳>.zip（秒级时间戳，
/// 同名秒内冲突自动 _2 去重）。写后回读校验（listFilenames 含
/// <世界名>/level.dat）= 坏 zip fail-loud（失败即删半成品并报错，不留坏件）。
/// completion 主线程回调。
+ (void)ame429_s1_backupWorldAtPath:(NSString *)worldPath
                          completion:(void (^)(BOOL ok,
                                               NSString * _Nullable zipPath,
                                               NSError * _Nullable error))completion;

/// 备份清单：backupsRoot 下全部 .zip（文件名升序），每项：name / path /
/// size（NSNumber 字节）/ modified（NSDate）。同步方法。
+ (NSArray<NSDictionary *> *)ame429_s1_listBackups;

/// 删除单个备份 zip（回收站语义：移入 trashRoot/<时间戳>/，不直删）。
+ (BOOL)ame429_s1_trashBackupAtPath:(NSString *)zipPath error:(NSError **)error;

#pragma mark 恢复（zip → 决策树目标 saves/）

/// 从备份 zip 恢复世界到 gameDir/saves/：
///   staging 解压（UnzipKit）→ 单一顶层目录识别 + level.dat 存在校验
///   （坏 zip / 结构异常 fail-loud）→ 目标同名现存档移入回收站（移不动即
///   中止，绝不覆盖活档）→ 顶层目录改名落回 saves/（防撞后缀）→ 清理 staging。
/// completion 主线程回调（ok=NO 时 restoredWorldName 为 nil、error 必填）。
+ (void)ame429_s1_restoreBackupAtPath:(NSString *)zipPath
                              gameDir:(NSString *)gameDir
                           completion:(void (^)(BOOL ok,
                                                NSString * _Nullable restoredWorldName,
                                                NSError * _Nullable error))completion;

#pragma mark 复制 / 删除（就地操作）

/// 就地复制世界目录（saves/ 内深拷贝；新名 = <名>_Copy / _Copy2 / …首个
/// 未占用项）。返回新目录名；失败返回 nil 并带 error。
+ (nullable NSString *)ame429_s1_duplicateWorldAtPath:(NSString *)worldPath
                                                error:(NSError **)error;

/// 删除世界（回收站语义：移入 trashRoot/<时间戳>/<世界名>/，可手动找回；
/// 移动失败回退深拷贝+删源，双败 fail-loud）。
+ (BOOL)ame429_s1_trashWorldAtPath:(NSString *)worldPath error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
