//
//  FileLayoutService.m
//  Amethyst
//
//  Task316 实现见头注释。核心不变量：
//  - 迁移只做 move-if-absent / symlink 化，绝不覆盖、绝不删除内容数据；
//  - 导入只做 copy-if-absent，源目录只读不写；
//  - marker 幂等，任何一步异常记日志后继续（不因单目录损坏阻塞启动）。
//

#import "FileLayoutService.h"
#import <UIKit/UIKit.h>

#define FLLog(fmt, ...) NSLog(@"[FileLayout] ame316: " fmt, ##__VA_ARGS__)

@implementation FileLayoutService

#pragma mark - Primitives

/// 目录内容逐条 move-if-absent 合并（src 的每个子项在 dst 不存在才搬）。
/// 返回搬移条数。
+ (NSInteger)fl_mergeMoveFromDir:(NSString *)src toDir:(NSString *)dst {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
    NSInteger moved = 0;
    for (NSString *item in [fm contentsOfDirectoryAtPath:src error:nil]) {
        if ([item hasPrefix:@"."]) continue;   // 工作区/隐藏项不动
        NSString *from = [src stringByAppendingPathComponent:item];
        NSString *to = [dst stringByAppendingPathComponent:item];
        if ([fm fileExistsAtPath:to]) continue; // 目标已有 → 绝不覆盖
        if ([fm moveItemAtPath:from toPath:to error:nil]) moved++;
    }
    return moved;
}

/// 目录内容逐条 copy-if-absent 合并（源只读；导入语义）。
+ (NSInteger)fl_mergeCopyFromDir:(NSString *)src toDir:(NSString *)dst {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
    NSInteger copied = 0;
    for (NSString *item in [fm contentsOfDirectoryAtPath:src error:nil]) {
        if ([item hasPrefix:@"."]) continue;
        NSString *from = [src stringByAppendingPathComponent:item];
        NSString *to = [dst stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:from isDirectory:&isDir]) continue;
        if ([fm fileExistsAtPath:to]) continue;
        BOOL ok = isDir ? [fm copyItemAtPath:from toPath:to error:nil]
                        : [fm copyItemAtPath:from toPath:to error:nil];
        if (ok) copied++;
    }
    return copied;
}

/// 把 srcDir（真实目录）的条目并入 sharedDir，然后 srcDir 原位替换为指向
/// sharedDir 的符号链接。sharedDir 已有同名条目则保留 shared 侧（核心层
/// 同名 = 同内容，Constitution 与 vanilla 命名规则保证）。
+ (BOOL)fl_absorbIntoSharedCoreDir:(NSString *)srcDir sharedDir:(NSString *)sharedDir name:(NSString *)name {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL srcIsDir = NO;
    if (![fm fileExistsAtPath:srcDir isDirectory:&srcIsDir] || !srcIsDir) return YES; // 无此层视为已就绪
    NSDictionary *attrs = [fm attributesOfItemAtPath:srcDir error:nil];
    if ([attrs fileType] == NSFileTypeSymbolicLink) return YES;                        // 已链接
    [fm createDirectoryAtPath:sharedDir.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    // 换名暂存 → 建链接 → 旧目录内容并入链接目标（经链接写入即落 shared）
    NSString *staging = [srcDir.stringByDeletingLastPathComponent
        stringByAppendingPathComponent:[NSString stringWithFormat:@".ame316_stage_%@", name]];
    [fm removeItemAtPath:staging error:nil];
    if (![fm moveItemAtPath:srcDir toPath:staging error:nil]) {
        FLLog(@"absorb: move-to-staging failed for %@", srcDir);
        return NO;
    }
    if (![fm createSymbolicLinkAtPath:srcDir withDestinationPath:sharedDir error:nil]) {
        // 链接失败 → 回滚原目录，绝不丢数据
        [fm moveItemAtPath:staging toPath:srcDir error:nil];
        FLLog(@"absorb: symlink create failed, rolled back %@", srcDir);
        return NO;
    }
    NSInteger moved = [self fl_mergeMoveFromDir:staging toDir:sharedDir];
    // 残余（隐藏项等）退回 shared 侧同级备份名，保证 staging 可删
    NSArray *left = [fm contentsOfDirectoryAtPath:staging error:nil] ?: @[];
    for (NSString *leftItem in left) {
        NSString *from = [staging stringByAppendingPathComponent:leftItem];
        NSString *to = [sharedDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@".ame316_leftover_%@_%@", name, leftItem]];
        if (![fm fileExistsAtPath:to]) [fm moveItemAtPath:from toPath:to error:nil];
    }
    [fm removeItemAtPath:staging error:nil];
    FLLog(@"absorb: %@ -> %@ (moved %ld)", name, sharedDir.lastPathComponent, (long)moved);
    return YES;
}

#pragma mark - A+B: one-time migration

+ (void)ame316_migrateIfNeeded {
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    if (home.length == 0) return;
    NSString *marker = [home stringByAppendingPathComponent:@"ame316_filelayout.done"];
    if ([NSFileManager.defaultManager fileExistsAtPath:marker]) return;

    @try {
        [self ame316_migrateInner:home];
    } @catch (NSException *e) {
        FLLog(@"migrate exception: %@ (%@) -- continuing legacy layout", e.name, e.reason);
    }
    [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    FLLog(@"migration marker written: %@", marker);
}

+ (void)ame316_migrateInner:(NSString *)home {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *instancesDir = [home stringByAppendingPathComponent:@"instances"];
    BOOL hasInstances = NO;
    if (![fm fileExistsAtPath:instancesDir isDirectory:&hasInstances] || !hasInstances) {
        FLLog(@"no instances dir -- fresh install, nothing to migrate");
        return;
    }

    // ---- A. 共享核心去重（所有实例的 versions/libraries/assets → shared_core）----
    NSString *sharedCore = [home stringByAppendingPathComponent:@"shared_core"];
    NSArray *coreNames = @[@"versions", @"libraries", @"assets"];
    NSArray<NSString *> *instanceNames =
        [fm contentsOfDirectoryAtPath:instancesDir error:nil] ?: @[];
    for (NSString *instName in instanceNames) {
        if ([instName hasPrefix:@"."]) continue;
        NSString *instDir = [instancesDir stringByAppendingPathComponent:instName];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:instDir isDirectory:&isDir] || !isDir) continue;
        for (NSString *coreName in coreNames) {
            NSString *src = [instDir stringByAppendingPathComponent:coreName];
            NSString *shared = [sharedCore stringByAppendingPathComponent:coreName];
            [self fl_absorbIntoSharedCoreDir:src sharedDir:shared name:coreName];
        }
    }

    // ---- B1. 整合包实例扁平化（instances/<inst>/custom_gamedir/<id> → instances/<id>）----
    NSMutableDictionary<NSString *, NSString *> *flattened = [NSMutableDictionary dictionary];
    for (NSString *instName in instanceNames) {
        if ([instName hasPrefix:@"."]) continue;
        NSString *customRoot = [[instancesDir stringByAppendingPathComponent:instName]
            stringByAppendingPathComponent:@"custom_gamedir"];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:customRoot isDirectory:&isDir] || !isDir) continue;
        for (NSString *packId in [fm contentsOfDirectoryAtPath:customRoot error:nil]) {
            if ([packId hasPrefix:@"."]) continue;
            NSString *src = [customRoot stringByAppendingPathComponent:packId];
            NSString *dst = [instancesDir stringByAppendingPathComponent:packId];
            if ([fm fileExistsAtPath:dst]) continue;   // 顶层同名已存在 → 不动旧档
            if ([fm moveItemAtPath:src toPath:dst error:nil]) {
                flattened[packId] = dst;
                FLLog(@"flatten: custom_gamedir/%@ (from instance %@) -> instances/%@", packId, instName, packId);
            }
        }
        // 清空壳归档（绝不删数据：残余退回 .ame316_leftover_custom_gamedir_<inst>）
        NSArray *left = [fm contentsOfDirectoryAtPath:customRoot error:nil] ?: @[];
        if (left.count == 0) {
            [fm removeItemAtPath:customRoot error:nil];
        } else {
            [fm moveItemAtPath:customRoot
                toPath:[[instancesDir stringByAppendingPathComponent:instName]
                    stringByAppendingPathComponent:
                        [NSString stringWithFormat:@".ame316_leftover_custom_gamedir_%@", instName]]
                error:nil];
        }
    }

    // ---- B2. profile gameDir 重写（custom_gamedir/<id> → 绝对 instances/<id>）----
    for (NSString *instName in instanceNames) {
        if ([instName hasPrefix:@"."]) continue;
        NSString *profilesPath = [[instancesDir stringByAppendingPathComponent:instName]
            stringByAppendingPathComponent:@"launcher_profiles.json"];
        [self ame316_rewriteProfilesAt:profilesPath flattened:flattened home:home];
    }

    // ---- B3. 共享核心符号链接回填：迁移后顶层实例目录若缺核心层（老整合包
    // 实例原本借当前实例核心），补一条 instances/<id>/versions 符号链接不必要
    // ——启动核心层一律走 POJAV_GAME_DIR 根（Tools.DIR_HOME_VERSION），内容
    // 层走 profile gameDir 绝对路径，互不相干。此处仅记日志说明语义。----
    FLLog(@"migration done: shared_core=%@ flattened=%lu", sharedCore.lastPathComponent, (unsigned long)flattened.count);
}

/// 把 launcher_profiles.json 里指向 custom_gamedir/<id> 的 gameDir 重写为
/// 绝对路径 instances/<id>（Task275 F5：绝对路径全链直通，与当前实例解耦）。
+ (void)ame316_rewriteProfilesAt:(NSString *)path
                       flattened:(NSDictionary<NSString *, NSString *> *)flattened
                            home:(NSString *)home {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) return;
    NSData *raw = [NSData dataWithContentsOfFile:path];
    if (!raw) return;
    NSError *jsonErr = nil;
    NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&jsonErr] mutableCopy];
    if (!root || ![root isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *profiles = [root[@"profiles"] isKindOfClass:NSDictionary.class]
        ? [root[@"profiles"] mutableCopy] : nil;
    if (!profiles) return;
    BOOL changed = NO;
    for (NSString *profileName in profiles.allKeys) {
        NSMutableDictionary *profile = [profiles[profileName] isKindOfClass:NSDictionary.class]
            ? [profiles[profileName] mutableCopy] : nil;
        if (!profile) continue;
        NSString *gd = [profile[@"gameDir"] isKindOfClass:NSString.class] ? profile[@"gameDir"] : nil;
        if (gd.length == 0 || ![gd containsString:@"custom_gamedir"]) continue;
        // 提取 <id>：custom_gamedir/ 之后的首段（Task269 同规则：只认一层）
        NSRange keyRange = [gd rangeOfString:@"custom_gamedir/"];
        if (keyRange.location == NSNotFound) continue;
        NSString *tail = [gd substringFromIndex:NSMaxRange(keyRange)];
        NSString *packId = [[tail componentsSeparatedByString:@"/"] firstObject] ?: @"";
        if (packId.length == 0) continue;
        NSString *abs = flattened[packId]
            ?: [[home stringByAppendingPathComponent:@"instances"] stringByAppendingPathComponent:packId];
        if (![NSFileManager.defaultManager fileExistsAtPath:abs]) continue;  // 目录不存在 → 不改（宁不迁移不误伤）
        profile[@"gameDir"] = abs;
        profiles[profileName] = profile;
        changed = YES;
        FLLog(@"profile rewrite: %@ gameDir -> %@", profileName, abs);
    }
    if (!changed) return;
    root[@"profiles"] = profiles;
    NSData *out = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (out) {
        // 原文件留 .ame316 备份（绝不删数据）
        if (![fm fileExistsAtPath:[path stringByAppendingString:@".ame316"]]) {
            [fm copyItemAtPath:path toPath:[path stringByAppendingString:@".ame316"] error:nil];
        }
        [out writeToFile:path atomically:YES];
    }
}

#pragma mark - C: cross-launcher importer

+ (NSString *)ame316_currentGameDir {
    const char *gd = getenv("POJAV_GAME_DIR");
    if (gd && strlen(gd) > 0) return @(gd);
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    return [home stringByAppendingPathComponent:@"Library/Application Support/minecraft"];
}

+ (NSString *)ame316_importExternalLauncherFolder:(NSURL *)folderURL error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *srcPath = folderURL.path;
    NSMutableString *report = [NSMutableString string];

    // 安全作用域（文档选择器 URL 必需；失败直接报错）
    BOOL scoped = [folderURL startAccessingSecurityScopedResource];
    @try {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:srcPath isDirectory:&isDir] || !isDir) {
            if (error) *error = [NSError errorWithDomain:@"FileLayoutService" code:1
                                userInfo:@{NSLocalizedDescriptionKey : @"所选路径不是文件夹"}];
            return nil;
        }

        // ---- 布局识别 ----
        BOOL hasMMCPack = [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"mmc-pack.json"]]
                       || [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"instance.cfg"]];
        NSString *dotMC = [srcPath stringByAppendingPathComponent:@".minecraft"];
        BOOL hasDotMCContent = [fm fileExistsAtPath:dotMC]
            && ([fm fileExistsAtPath:[dotMC stringByAppendingPathComponent:@"saves"]]
             || [fm fileExistsAtPath:[dotMC stringByAppendingPathComponent:@"mods"]]);
        NSString *contentRoot = srcPath;
        NSString *kind = @"通用内容目录";
        BOOL fullRoot = NO;   // 含核心层（versions/libraries/assets）的 .minecraft 全量根
        if (hasMMCPack) {
            kind = @"MultiMC/Prism 实例";
            contentRoot = hasDotMCContent ? dotMC : srcPath;
        } else if (hasDotMCContent) {
            kind = @"桌面启动器目录（.minecraft）";
            contentRoot = dotMC;
            fullRoot = YES;   // .minecraft 子目录所在 = 上级即全量根（版本隔离外层）
        } else if ([fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"versions"]]
                || [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"launcher_profiles.json"]]) {
            kind = @".minecraft 全量根";
            fullRoot = YES;
            contentRoot = srcPath;
        } else if ([fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"saves"]]
                || [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"mods"]]) {
            kind = @"内容目录（HMCL/PCL 隔离目录或纯内容）";
        }
        [report appendFormat:@"识别类型：%@", kind];

        NSString *gameDir = [self ame316_currentGameDir];
        NSInteger coreCopied = 0, contentCopied = 0, skipped = 0;

        // ---- 核心层并轨（全量根才有；落 POJAV_GAME_DIR，经实例符号链接即共享核心）----
        if (fullRoot) {
            for (NSString *coreName in @[@"versions", @"libraries", @"assets"]) {
                NSString *src = [contentRoot stringByAppendingPathComponent:coreName];
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) continue;
                coreCopied += [self fl_mergeCopyCountedFrom:src to:[gameDir stringByAppendingPathComponent:coreName] skipped:&skipped];
            }
        }

        // ---- 内容层合入当前实例根（逐文件跳已存在，绝不覆盖）----
        for (NSString *contentName in @[@"saves", @"mods", @"resourcepacks", @"shaderpacks",
                                        @"config", @"screenshots", @"crash-reports",
                                        @"options.txt", @"servers.dat", @"servers.dat_old",
                                        @"usercache.json", @"hotbar.nbt", @"realms_persistence.json"]) {
            NSString *src = [contentRoot stringByAppendingPathComponent:contentName];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:src isDirectory:&isDir]) continue;
            NSString *dst = [gameDir stringByAppendingPathComponent:contentName];
            if (isDir) {
                contentCopied += [self fl_mergeCopyCountedFrom:src to:dst skipped:&skipped];
            } else {
                if (![fm fileExistsAtPath:dst]) {
                    if ([fm copyItemAtPath:src toPath:dst error:nil]) contentCopied++;
                } else {
                    skipped++;
                }
            }
        }

        [report appendFormat:@"\n核心层并入：%ld 项（版本/库/资产，全实例共享）", (long)coreCopied];
        [report appendFormat:@"\n内容层合入：%ld 项（存档/模组/资源包等 → 当前实例）", (long)contentCopied];
        [report appendFormat:@"\n已存在跳过：%ld 项（不覆盖你的既有数据）", (long)skipped];
        [report appendString:@"\n源目录只读未改动。"];
        if (fullRoot) [report appendString:@"\n提示：源目录的启动器配置（账号/配置）不迁移，游戏数据已就位。"];
        FLLog(@"import: kind=%@ core=%ld content=%ld skipped=%ld src=%@",
              kind, (long)coreCopied, (long)contentCopied, (long)skipped, srcPath);
        return report;
    } @finally {
        if (scoped) [folderURL stopAccessingSecurityScopedResource];
    }
}

/// copy-if-absent 带跳过计数（递归按文件计）。
+ (NSInteger)fl_mergeCopyCountedFrom:(NSString *)src to:(NSString *)dst skipped:(NSInteger *)skipped {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL srcIsDir = NO;
    if (![fm fileExistsAtPath:src isDirectory:&srcIsDir]) return 0;
    if (!srcIsDir) {
        if ([fm fileExistsAtPath:dst]) { if (skipped) (*skipped)++; return 0; }
        return [fm copyItemAtPath:src toPath:dst error:nil] ? 1 : 0;
    }
    [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
    NSInteger copied = 0;
    for (NSString *item in [fm contentsOfDirectoryAtPath:src error:nil]) {
        NSString *from = [src stringByAppendingPathComponent:item];
        NSString *to = [dst stringByAppendingPathComponent:item];
        copied += [self fl_mergeCopyCountedFrom:from to:to skipped:skipped];
    }
    return copied;
}

@end
