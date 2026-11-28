//
//  FileLayoutService.m
//  Amethyst
//
//  ★ Task483（单根终局）：ame316 instances 布局迁移体（共享核心去重/整合包
//  实例扁平化/profile 重写）已随 instances 布局整体退役删除——单一真实数据根
//  = lasm（Library/Application Support/minecraft），instances 目录永不重建，
//  存量收编由 main.m Task483 单根迁移承担。本文件仅保留跨启动器导入器。
//  核心不变量：
//  - 导入只做 copy-if-absent，源目录只读不写；
//  - 任何一步异常记日志后继续（不因单目录损坏阻塞启动）。
//

#import "FileLayoutService.h"
#import "utils.h"   // ★Task449：localize（跨启动器导入报告 i18n 化）
#import <UIKit/UIKit.h>

#define FLLog(fmt, ...) NSLog(@"[FileLayout] ame316: " fmt, ##__VA_ARGS__)

@implementation FileLayoutService

#pragma mark - Primitives

// ★ Task483：fl_mergeMoveFromDir / fl_mergeCopyFromDir /
//   fl_absorbIntoSharedCoreDir 已随 ame316 迁移链一并删除
//   （instances 布局退役；main.m Task483 单根迁移为唯一收编路径）。

// ★ Task483：fl_absorbIntoSharedCoreDir + ame316_migrateIfNeeded /
//   ame316_migrateInner / ame316_rewriteProfilesAt 整链删除（instances
//   布局退役；存量收编由 main.m Task483 单根迁移承担）。

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
                                userInfo:@{NSLocalizedDescriptionKey : localize(@"ame449.filexlate.not_dir", @"所选路径不是文件夹")}];
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
        NSString *kind = localize(@"ame449.filexlate.kind_content", @"通用内容目录");
        BOOL fullRoot = NO;   // 含核心层（versions/libraries/assets）的 .minecraft 全量根
        if (hasMMCPack) {
            kind = localize(@"ame449.filexlate.kind_multimc", @"MultiMC/Prism 实例");
            contentRoot = hasDotMCContent ? dotMC : srcPath;
        } else if (hasDotMCContent) {
            kind = localize(@"ame449.filexlate.kind_desktop_mc", @"桌面启动器目录（.minecraft）");
            contentRoot = dotMC;
            fullRoot = YES;   // .minecraft 子目录所在 = 上级即全量根（版本隔离外层）
        } else if ([fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"versions"]]
                || [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"launcher_profiles.json"]]) {
            kind = localize(@"ame449.filexlate.kind_mc_root", @".minecraft 全量根");
            fullRoot = YES;
            contentRoot = srcPath;
        } else if ([fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"saves"]]
                || [fm fileExistsAtPath:[srcPath stringByAppendingPathComponent:@"mods"]]) {
            kind = localize(@"ame449.filexlate.kind_contents", @"内容目录（HMCL/PCL 隔离目录或纯内容）");
        }
        [report appendFormat:localize(@"ame449.filexlate.kind_fmt", @"识别类型：%@"), kind];

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

        [report appendFormat:localize(@"ame449.filexlate.core_fmt", @"\n核心层并入：%ld 项（版本/库/资产，全实例共享）"), (long)coreCopied];
        [report appendFormat:localize(@"ame449.filexlate.content_fmt", @"\n内容层合入：%ld 项（存档/模组/资源包等 → 当前实例）"), (long)contentCopied];
        [report appendFormat:localize(@"ame449.filexlate.skip_fmt", @"\n已存在跳过：%ld 项（不覆盖你的既有数据）"), (long)skipped];
        [report appendString:localize(@"ame449.filexlate.src_ro", @"\n源目录只读未改动。")];
        if (fullRoot) [report appendString:localize(@"ame449.filexlate.tip_full", @"\n提示：源目录的启动器配置（账号/配置）不迁移，游戏数据已就位。")];
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
