#import "utils.h"
#import "ZL2GamePath.h" // ★Task473: ZL2 版本隔离系统单入口
//
//  PLWorldBackupService.m
//  Amethyst
//
//  ★Task429（PDF 六 §4.4 世界备份/复制/删除 + 恢复同源）实现。
//  设计注记见 .h 头注释；关键决策：
//    · zip 写器 = UnzipKit（世界导入/解压链同库，备份↔恢复对称；data 入内存
//      按文件写——region 文件单件 ≤ 数 MB 量级，无需流式）；
//    · 回收站语义 = trashRoot/<时间戳子目录>/<原名>（带时间戳子目录防同名
//      覆盖，判例：删除必须可找回）；
//    · gameDir 解析 = PLProfiles 隔离决策树（显式 gameDir → ame225 嗅探 →
//      ame428 版本级有效隔离），与 JavaLauncher 启动链同源（§3.3 红线）；
//    · 坏 zip / 结构异常一律 fail-loud（NSError 上抛 + 删半成品），不静默。
//

#import "PLWorldBackupService.h"
#import "PLProfiles.h"
#import "ModService.h"          // Task225 隔离嗅探（与启动链/WorldService 同源）
#import "UZKArchive.h"

#pragma mark - 常量实名（判例族）

/// 备份 zip 存放根目录名（POJAV_HOME 下）
static NSString * const kAme429S1BackupsDirectoryName = @"world_backups";
/// 回收站根目录名（POJAV_HOME 下）
static NSString * const kAme429S1TrashDirectoryName = @"trash";
/// 恢复 staging 目录名前缀（NSTemporaryDirectory 下）
static NSString * const kAme429S1RestoreStagingPrefix = @"PLWorldBackupRestore_";
/// 时间戳格式（备份 zip 名与回收站子目录共用）
static NSString * const kAme429S1TimestampFormat = @"yyyyMMdd_HHmmss";
/// 世界有效性判据文件（与 WorldService 扫描同判据）
static NSString * const kAme429S1LevelDatFileName = @"level.dat";
/// 复制去重后缀首段
static NSString * const kAme429S1CopySuffix = @"_Copy";

#pragma mark - 内部工具（static 声明序：先声明后消费）

/// 时间戳串（回收站子目录毫秒位防同秒冲突）
static NSString *ame429_s1_timestampString(BOOL withMilliseconds) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = withMilliseconds ? @"yyyyMMdd_HHmmss_SSS" : kAme429S1TimestampFormat;
    return [fmt stringFromDate:[NSDate date]];
}

/// POJAV_HOME（空 → NSHomeDirectory 兜底；stringWithUTF8String 直构造，
/// 禁 @(nullable) 判例：可空 char* 侧经非空判据后再构造）
static NSString *ame429_s1_homeDir(void) {
    const char *homeC = getenv("POJAV_HOME");
    if (homeC && *homeC) return [NSString stringWithUTF8String:homeC];
    return NSHomeDirectory();
}

/// 递归计算目录字节数（listWorlds 的 size 字段；符号链接不跟随）
static unsigned long long ame429_s1_sizeOfDirectoryAtPath(NSString *path) {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    NSString *rel;
    while ((rel = enumerator.nextObject) != nil) {
        NSDictionary *attrs = [enumerator fileAttributes];
        if (attrs) total += [attrs fileSize];
    }
    return total;
}

/// 目录移动（优先 rename 语义 move；跨设备/失败回退深拷贝+删源，双败 fail-loud）
// ★Task429-r7 热修（dev run 43691459560 实录：:69 顶层声明误写 ObjC selector
//   形态 ame429_s1_movePath:（expected ';' after top level declarator +
//   redefinition of 'NSString' as different kind of symbol × 5 连锁）——
//   本函数是 C 函数（三调用点全 C 式传参），声明改回 C 形参表。
static BOOL ame429_s1_movePath(NSString *src, NSString *dst, BOOL deleteOnCopy, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *moveError = nil;
    if ([fm moveItemAtPath:src toPath:dst error:&moveError]) return YES;
    NSError *copyError = nil;
    if ([fm copyItemAtPath:src toPath:dst error:&copyError]) {
        if (deleteOnCopy) {
            NSError *removeError = nil;
            if (![fm removeItemAtPath:src error:&removeError]) {
                NSLog(@"[PLWorldBackup] Task429: copy-fallback left source in place (remove failed: %@)",
                      removeError.localizedDescription);
            }
        }
        return YES;
    }
    // 双败 fail-loud：带两侧底层错误上抛（坏路径/权限/跨设备均可见）
    if (error) {
        NSString *fmt = localize(@"ame429.s1.err.move_failed",
            @"目录移动/复制失败：%1$@ → %2$@（%3$@ / %4$@）");
        *error = [NSError errorWithDomain:@"PLWorldBackupService" code:10
                                 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:fmt,
             src.lastPathComponent ?: @"", dst.lastPathComponent ?: @"",
             moveError.localizedDescription ?: @"", copyError.localizedDescription ?: @""]}];
    }
    return NO;
}

// ★Task473：备份源/恢复落点改经 ZL2GamePath 单入口（旧 ame428 决策树前向
//   声明分类随体系退役；解析链三层拼装由单入口取代）。
@interface PLProfiles (Ame429Task429S1)
@end

@implementation PLWorldBackupService

#pragma mark 目录解析（PLProfiles 隔离决策树——与启动路径同源）

+ (nullable NSString *)ame429_s1_gameDirForProfileName:(NSString *)profileName
                                              versionId:(NSString *)versionId {
    // ★Task473（上游 Version.getGameDir 同构）：备份源与恢复目标唯一取值口
    //   经 ZL2GamePath 单入口（与启动 chdir / 各服务同源）：版本级隔离 ENABLE →
    //   versions/<vid>/；FOLLOW_GLOBAL 折叠全局档；否则实例自定义路径 / 主游戏根。
    //   （旧 ①显式gameDir→②嗅探→③ame428 决策树三层拼装退役——Task472 判例延续）
    return [ZL2GamePath gameDirForProfile:profileName];
}

+ (NSString *)ame429_s1_backupsRoot {
    return [ame429_s1_homeDir() stringByAppendingPathComponent:kAme429S1BackupsDirectoryName];
}

+ (NSString *)ame429_s1_trashRoot {
    return [ame429_s1_homeDir() stringByAppendingPathComponent:kAme429S1TrashDirectoryName];
}

#pragma mark 世界列表

+ (NSArray<NSDictionary *> *)ame429_s1_listWorldsForGameDir:(NSString *)gameDir {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if (gameDir.length == 0) return [rows copy];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *savesDir = [gameDir stringByAppendingPathComponent:@"saves"];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:savesDir error:nil];
    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."]) continue;   // 隐藏隔离条目
        NSString *full = [savesDir stringByAppendingPathComponent:entry];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || !isDir) continue;
        // 世界判据：level.dat 存在（与 WorldService 扫描同判据）
        if (![fm fileExistsAtPath:[full stringByAppendingPathComponent:kAme429S1LevelDatFileName]]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        NSDate *modified = [attrs fileModificationDate] ?: [NSDate date];
        [rows addObject:@{
            @"name": entry,
            @"path": full,
            @"modified": modified,
            @"size": @(ame429_s1_sizeOfDirectoryAtPath(full)),
        }];
    }
    // 修改时间新 → 旧
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"modified"] compare:a[@"modified"]];
    }];
    return [rows copy];
}

#pragma mark 备份（世界目录 → zip）

+ (void)ame429_s1_backupWorldAtPath:(NSString *)worldPath
                          completion:(void (^)(BOOL, NSString *, NSError *))completion {
    void (^safeCompletion)(BOOL, NSString *, NSError *) = ^(BOOL ok, NSString *zipPath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, zipPath, error); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *zipPath = [self ame429_s1_backupWorldSync:worldPath error:&error];
        if (!zipPath) {
            NSLog(@"[PLWorldBackup] Task429: backup failed for %@: %@",
                  worldPath.lastPathComponent, error.localizedDescription);
            safeCompletion(NO, nil, error);
            return;
        }
        NSLog(@"[PLWorldBackup] Task429: backup ok: %@ -> %@", worldPath.lastPathComponent, zipPath);
        safeCompletion(YES, zipPath, nil);
    });
}

/// 备份同步实现（后台队列专用；失败删除半成品 = 不留坏 zip）
+ (nullable NSString *)ame429_s1_backupWorldSync:(NSString *)worldPath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:worldPath isDirectory:&isDir] || !isDir) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:1
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.world_missing", @"世界目录不存在或已失效")}];
        return nil;
    }
    NSString *worldName = worldPath.lastPathComponent;
    if (![fm fileExistsAtPath:[worldPath stringByAppendingPathComponent:kAme429S1LevelDatFileName]]) {
        // 守卫配真实现：无 level.dat 的目录不是世界（fail-loud 而非产空包）
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.not_a_world", @"目录缺少 level.dat，不是有效世界存档")}];
        return nil;
    }

    // 落点名：<世界名>_<时间戳>.zip（同秒冲突 _2/_3 去重）
    NSString *root = [self ame429_s1_backupsRoot];
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:3
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.backup_dir", @"备份目录创建失败")}];
        return nil;
    }
    NSString *stamp = ame429_s1_timestampString(NO);
    NSString *zipPath = [root stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@_%@.zip", worldName, stamp]];
    NSUInteger dedupe = 2;
    while ([fm fileExistsAtPath:zipPath]) {
        zipPath = [root stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@_%@_%lu.zip", worldName, stamp, (unsigned long)dedupe]];
        dedupe++;
        if (dedupe > 99) break;   // 防御上限（不构成真实现依赖）
    }

    // UnzipKit 写器：按文件 writeData（备份 zip ↔ 恢复解压同库对称）
    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&archiveError];
    if (!archive) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:4
                                            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:localize(@"ame429.s1.err.zip_open", @"备份包创建失败：%@"),
                 archiveError.localizedDescription ?: @"unknown"]}];
        return nil;
    }
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:worldPath];
    NSString *rel;
    NSUInteger fileCount = 0;
    while ((rel = enumerator.nextObject) != nil) {
        if ([rel.lastPathComponent isEqualToString:@".DS_Store"]) continue;
        NSString *src = [worldPath stringByAppendingPathComponent:rel];
        BOOL entryIsDir = NO;
        if (![fm fileExistsAtPath:src isDirectory:&entryIsDir] || entryIsDir) continue;
        NSData *data = [NSData dataWithContentsOfFile:src];
        if (!data) {
            // 读失败 fail-loud（半读的备份比没备份更危险）
            if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:5
                                                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:localize(@"ame429.s1.err.read_file", @"读取文件失败：%@"), rel]}];
            [fm removeItemAtPath:zipPath error:nil];
            return nil;
        }
        NSString *zipEntry = [NSString stringWithFormat:@"%@/%@", worldName, rel];
        NSDictionary *attrs = [enumerator fileAttributes];
        NSError *writeError = nil;
        BOOL ok = [archive writeData:data
                            filePath:zipEntry
                            fileDate:[attrs fileModificationDate]
                   compressionMethod:UZKCompressionMethodDefault
                            password:nil
                               error:&writeError];
        if (!ok || writeError) {
            if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:6
                                                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:localize(@"ame429.s1.err.zip_write", @"写入备份包失败（%@）：%@"),
                     rel, writeError.localizedDescription ?: @"unknown"]}];
            [fm removeItemAtPath:zipPath error:nil];
            return nil;
        }
        fileCount++;
    }
    if (fileCount == 0) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:7
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.empty_world", @"世界目录为空，未生成备份")}];
        [fm removeItemAtPath:zipPath error:nil];
        return nil;
    }

    // 写后回读校验（坏 zip fail-loud 判例）：可打开 + 清单含 <世界名>/level.dat
    NSError *verifyError = nil;
    UZKArchive *verify = [[UZKArchive alloc] initWithPath:zipPath error:&verifyError];
    NSArray<NSString *> *names = verify ? [verify listFilenames:&verifyError] : nil;
    NSString *levelEntry = [NSString stringWithFormat:@"%@/%@", worldName, kAme429S1LevelDatFileName];
    if (!verify || !names || verifyError || ![names containsObject:levelEntry]) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:8
                                            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:localize(@"ame429.s1.err.zip_verify", @"备份完整性校验失败（缺 %@）：%@"),
                 levelEntry, verifyError.localizedDescription ?: @"unknown"]}];
        [fm removeItemAtPath:zipPath error:nil];
        return nil;
    }
    NSLog(@"[PLWorldBackup] Task429: backup verified (%lu files): %@",
          (unsigned long)fileCount, zipPath.lastPathComponent);
    return zipPath;
}

+ (NSArray<NSDictionary *> *)ame429_s1_listBackups {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:[self ame429_s1_backupsRoot] error:nil];
    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."]) continue;
        if (![entry.pathExtension.lowercaseString isEqualToString:@"zip"]) continue;
        NSString *full = [[self ame429_s1_backupsRoot] stringByAppendingPathComponent:entry];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        [rows addObject:@{
            @"name": entry,
            @"path": full,
            @"size": @([attrs fileSize]),
            @"modified": [attrs fileModificationDate] ?: [NSDate date],
        }];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"modified"] compare:a[@"modified"]];
    }];
    return [rows copy];
}

+ (BOOL)ame429_s1_trashBackupAtPath:(NSString *)zipPath error:(NSError **)error {
    // 回收站语义（与世界删除同族）：移入 trashRoot/<时间戳>_<毫秒>/，不直删
    return [self ame429_s1_moveToTrash:zipPath error:error];
}

#pragma mark 回收站语义

/// 内部：任意路径移入 trashRoot/<时间戳子目录>/（时间戳子目录带毫秒防同秒
/// 覆盖；子目录内同名冲突 _2 去重）。移动失败回退拷贝+删源，双败 fail-loud。
+ (BOOL)ame429_s1_moveToTrash:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:11
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.trash_missing", @"目标不存在，无法移入回收站")}];
        return NO;
    }
    NSString *stampDir = [self ame429_s1_trashRoot];
    stampDir = [stampDir stringByAppendingPathComponent:ame429_s1_timestampString(YES)];
    if (![fm createDirectoryAtPath:stampDir withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:12
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.trash_dir", @"回收站目录创建失败")}];
        return NO;
    }
    NSString *base = path.lastPathComponent;
    NSString *dst = [stampDir stringByAppendingPathComponent:base];
    NSUInteger dedupe = 2;
    while ([fm fileExistsAtPath:dst]) {
        dst = [stampDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)dedupe]];
        dedupe++;
        if (dedupe > 99) break;
    }
    BOOL ok = ame429_s1_movePath(path, dst, YES, error);
    if (ok) {
        NSLog(@"[PLWorldBackup] Task429: trashed %@ -> %@", base, dst);
    }
    return ok;
}

#pragma mark 恢复（zip → 决策树目标 saves/）

+ (void)ame429_s1_restoreBackupAtPath:(NSString *)zipPath
                              gameDir:(NSString *)gameDir
                           completion:(void (^)(BOOL, NSString *, NSError *))completion {
    void (^safeCompletion)(BOOL, NSString *, NSError *) = ^(BOOL ok, NSString *name, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, name, error); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *error = nil;
        NSString *worldName = nil;

        // staging 解压（临时目录隔离，坏 zip 不落 saves）
        NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [kAme429S1RestoreStagingPrefix stringByAppendingString:[[NSUUID UUID] UUIDString]]];
        [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];
        void (^cleanup)(void) = ^{
            [fm removeItemAtPath:staging error:nil];
        };

        NSError *archiveError = nil;
        UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&archiveError];
        if (!archive) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:20
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:localize(@"ame429.s1.err.zip_open", @"备份包创建失败：%@"),
                 archiveError.localizedDescription ?: @"unknown"]}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }
        NSError *extractError = nil;
        if (![archive extractFilesTo:staging overwrite:YES error:&extractError]) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:21
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:localize(@"ame429.s1.err.zip_extract", @"备份包解压失败：%@"),
                 extractError.localizedDescription ?: @"unknown"]}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }

        // 单一顶层目录识别（备份写器恒以 <世界名>/ 为顶层；散装形态 = 结构异常 fail-loud）
        NSArray<NSString *> *top = [fm contentsOfDirectoryAtPath:staging error:nil];
        NSMutableArray<NSString *> *topDirs = [NSMutableArray array];
        NSMutableArray<NSString *> *topFiles = [NSMutableArray array];
        for (NSString *entry in top) {
            if ([entry hasPrefix:@"."]) continue;
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:[staging stringByAppendingPathComponent:entry] isDirectory:&isDir] && isDir) {
                [topDirs addObject:entry];
            } else {
                [topFiles addObject:entry];
            }
        }
        if (topDirs.count != 1 || topFiles.count > 0) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:22
                                    userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.zip_structure", @"备份包结构异常：应为单一顶层世界目录")}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }
        worldName = topDirs.firstObject;
        NSString *stagedWorld = [staging stringByAppendingPathComponent:worldName];

        // 世界判据（防 zip-slip 后置校验之一：level.dat 必须在顶层目录内）
        if (![fm fileExistsAtPath:[stagedWorld stringByAppendingPathComponent:kAme429S1LevelDatFileName]]) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:23
                                    userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.not_a_world", @"目录缺少 level.dat，不是有效世界存档")}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }
        // zip-slip 防御：解产物必须仍在 staging 内（staging 路径前缀判据）
        NSString *stagingNorm = [staging stringByStandardizingPath];
        NSString *stagedNorm = [stagedWorld stringByStandardizingPath];
        if (![stagedNorm hasPrefix:stagingNorm]) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:24
                                    userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.zip_slip", @"备份包路径越界（zip-slip 防御拦截）")}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }

        // 目标 saves/（决策树 gameDir → saves；目录惰性创建）
        if (gameDir.length == 0) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:25
                                    userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.no_gamedir", @"游戏目录解析失败（PLProfiles 决策树空值）")}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }
        NSString *savesDir = [gameDir stringByAppendingPathComponent:@"saves"];
        if (![fm createDirectoryAtPath:savesDir withIntermediateDirectories:YES attributes:nil error:nil]) {
            error = [NSError errorWithDomain:@"PLWorldBackupService" code:26
                                    userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.saves_dir", @"存档目录创建失败")}];
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }

        // 同名现存档先入回收站（移不动即中止——绝不覆盖活档）
        NSString *target = [savesDir stringByAppendingPathComponent:worldName];
        if ([fm fileExistsAtPath:target]) {
            NSError *trashError = nil;
            if (![self ame429_s1_moveToTrash:target error:&trashError]) {
                error = [NSError errorWithDomain:@"PLWorldBackupService" code:27
                                        userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:localize(@"ame429.s1.err.existing", @"同名现存档移入回收站失败：%@"),
                     trashError.localizedDescription ?: @"unknown"]}];
                cleanup();
                safeCompletion(NO, nil, error);
                return;
            }
        }
        // 防撞后缀（回收站竞态兜底）
        NSString *finalName = worldName;
        NSUInteger dedupe = 2;
        while ([fm fileExistsAtPath:[savesDir stringByAppendingPathComponent:finalName]]) {
            finalName = [NSString stringWithFormat:@"%@ (restore %lu)", worldName, (unsigned long)dedupe];
            dedupe++;
            if (dedupe > 99) break;
        }
        NSString *finalPath = [savesDir stringByAppendingPathComponent:finalName];
        if (!ame429_s1_movePath(stagedWorld, finalPath, YES, &error)) {
            cleanup();
            safeCompletion(NO, nil, error);
            return;
        }
        cleanup();
        NSLog(@"[PLWorldBackup] Task429: restore ok: %@ -> %@", zipPath.lastPathComponent, finalPath);
        safeCompletion(YES, finalName, nil);
    });
}

#pragma mark 复制 / 删除（就地操作）

+ (nullable NSString *)ame429_s1_duplicateWorldAtPath:(NSString *)worldPath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:worldPath isDirectory:&isDir] || !isDir) {
        if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:30
                                            userInfo:@{NSLocalizedDescriptionKey:
                localize(@"ame429.s1.err.world_missing", @"世界目录不存在或已失效")}];
        return nil;
    }
    NSString *savesDir = worldPath.stringByDeletingLastPathComponent;
    NSString *base = worldPath.lastPathComponent;
    // 新名 = <名>_Copy / <名>_Copy2 / …首个未占用项（就地复制语义）
    NSString *candidate = [base stringByAppendingString:kAme429S1CopySuffix];
    NSUInteger dedupe = 2;
    while ([fm fileExistsAtPath:[savesDir stringByAppendingPathComponent:candidate]]) {
        candidate = [NSString stringWithFormat:@"%@%lu", [base stringByAppendingString:kAme429S1CopySuffix],
                     (unsigned long)dedupe];
        dedupe++;
        if (dedupe > 999) {
            if (error) *error = [NSError errorWithDomain:@"PLWorldBackupService" code:31
                                                userInfo:@{NSLocalizedDescriptionKey:
                    localize(@"ame429.s1.err.dup_name", @"可用副本名耗尽（999 项上限）")}];
            return nil;
        }
    }
    NSString *dst = [savesDir stringByAppendingPathComponent:candidate];
    if (!ame429_s1_movePath(worldPath, dst, NO, error)) {
        return nil;
    }
    NSLog(@"[PLWorldBackup] Task429: duplicated %@ -> %@", base, candidate);
    return candidate;
}

+ (BOOL)ame429_s1_trashWorldAtPath:(NSString *)worldPath error:(NSError **)error {
    return [self ame429_s1_moveToTrash:worldPath error:error];
}

@end
