//
//  ModpackConfiguration.m
//  Amethyst
//
//  Created by iFlow on 2024/11/29.
//

#import "ModpackConfiguration.h"
// ★Task428：探测/归一需要 zip 单条目读取（与 ModpackUtils.h 同源的 UnzipKit 引入方式）
#import "UnzipKit.h"
#import "utils.h"

@implementation ModpackFileInformation

- (instancetype)initWithPath:(NSString *)path fileHash:(NSString *)fileHash downloadURL:(NSString *)downloadURL fileSize:(NSUInteger)fileSize {
    self = [super init];
    if (self) {
        _path = path;
        _fileHash = fileHash;
        _downloadURL = downloadURL;
        _fileSize = fileSize;
    }
    return self;
}

- (BOOL)validate {
    if (!_path || _path.length == 0) {
        NSLog(@"[ModpackConfiguration] File path is empty");
        return NO;
    }
    if (!_fileHash || _fileHash.length == 0) {
        NSLog(@"[ModpackConfiguration] File hash is empty for path: %@", _path);
        return NO;
    }
    return YES;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _path = dict[@"path"];
        _fileHash = dict[@"hashes"][@"sha1"];
        _downloadURL = dict[@"downloads"][0];
        _fileSize = [dict[@"fileSize"] unsignedIntegerValue];
    }
    return self;
}

@end

@implementation ModpackConfiguration

- (instancetype)initWithName:(NSString *)name version:(NSString *)version gameVersion:(NSString *)gameVersion {
    self = [super init];
    if (self) {
        _name = name;
        _version = version;
        _gameVersion = gameVersion;
        _files = [NSArray array];
        _dependencies = [NSDictionary dictionary];
    }
    return self;
}

- (void)saveToFile:(NSString *)filePath error:(NSError **)error {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"name"] = self.name;
    dict[@"version"] = self.version;
    dict[@"gameVersion"] = self.gameVersion;
    
    if (self.author) {
        dict[@"author"] = self.author;
    }
    if (self.packDescription) {
        dict[@"description"] = self.packDescription;
    }
    
    NSMutableArray *filesArray = [NSMutableArray array];
    for (ModpackFileInformation *fileInfo in self.files) {
        NSDictionary *fileDict = @{
            @"path": fileInfo.path,
            @"hashes": @{@"sha1": fileInfo.fileHash},
            @"downloads": @[fileInfo.downloadURL],
            @"fileSize": @(fileInfo.fileSize)
        };
        [filesArray addObject:fileDict];
    }
    dict[@"files"] = filesArray;
    
    if (self.dependencies) {
        dict[@"dependencies"] = self.dependencies;
    }
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:error];
    if (jsonData) {
        [jsonData writeToFile:filePath atomically:YES];
    }
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)filePath error:(NSError **)error {
    self = [super init];
    if (self) {
        NSData *jsonData = [NSData dataWithContentsOfFile:filePath options:0 error:error];
        if (!jsonData) {
            return nil;
        }
        
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
        if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        
        _name = dict[@"name"];
        _version = dict[@"version"];
        _gameVersion = dict[@"gameVersion"];
        _author = dict[@"author"];
        _packDescription = dict[@"description"];
        _dependencies = dict[@"dependencies"];
        
        NSArray *filesArray = dict[@"files"];
        if ([filesArray isKindOfClass:[NSArray class]]) {
            NSMutableArray *files = [NSMutableArray array];
            for (NSDictionary *fileDict in filesArray) {
                if ([fileDict isKindOfClass:[NSDictionary class]]) {
                    ModpackFileInformation *fileInfo = [[ModpackFileInformation alloc] initWithDictionary:fileDict];
                    if (fileInfo) {
                        [files addObject:fileInfo];
                    }
                }
            }
            _files = [files copy];
        }
    }
    return self;
}

- (BOOL)validate {
    if (!_name || _name.length == 0) {
        NSLog(@"[ModpackConfiguration] Name is empty");
        return NO;
    }
    if (!_version || _version.length == 0) {
        NSLog(@"[ModpackConfiguration] Version is empty");
        return NO;
    }
    if (!_gameVersion || _gameVersion.length == 0) {
        NSLog(@"[ModpackConfiguration] Game version is empty");
        return NO;
    }

    for (ModpackFileInformation *fileInfo in self.files) {
        if (![fileInfo validate]) {
            return NO;
        }
    }

    return YES;
}

#pragma mark - ★Task428：格式探测前置层 + Technic/FTB 归一化（工作项一 2.2）

static NSString *const kAme428ErrorDomain = @"Ame428FormatProbe";

/// .ini 风格（key=value）解析：段落头 [xxx] 忽略、键大小写不敏感、
/// 值去掉首尾空白与成对引号。供 Technic modpack.cfg 消费。
static NSDictionary<NSString *, NSString *> *ame428_parseIniStyleConfig(NSString *content) {
    if (![content isKindOfClass:[NSString class]] || content.length == 0) return @{};
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *rawLine in [content componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        unichar first = [line characterAtIndex:0];
        if (first == '[' || first == '#' || first == ';') continue;   // 段落头 / 注释
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) continue;
        NSString *key = [[line substringToIndex:eq.location] lowercaseString];
        NSString *value = [line substringFromIndex:eq.location + eq.length];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (value.length >= 2 && ([value hasPrefix:@"\""] && [value hasSuffix:@"\""])) {
            value = [value substringWithRange:NSMakeRange(1, value.length - 2)];
        }
        if (key.length == 0 || value.length == 0) continue;
        out[key] = value;
    }
    return [out copy];
}

/// 顶层 .minecraft 结构特征（与 ModpackImportService.isPlainZipModpack 同一清单，
/// 服务文件只读不可复用，此处保持逐位一致以便探测层/服务层结论一致）
static NSArray<NSString *> *ame428_plainZipSignatureEntries(void) {
    return @[
        @"mods/", @"config/", @"versions/", @"saves/", @"resourcepacks/",
        @"shaderpacks/", @"defaultconfigs/", @"kubejs/", @"scripts/",
        @"localization/", @"patchouli_books/", @"options.txt",
        @"optionsof.txt", @"optionsshaders.txt", @"servers.dat",
        @"launcher_profiles.json", @"hotbar.nbt"
    ];
}

/// zip 内是否含顶层 .minecraft 结构（兼容 .minecraft/ 前缀；跳过 __MACOSX 与隐藏文件）
+ (BOOL)ame428_hasPlainZipStructure:(UZKArchive *)archive {
    __block BOOL hit = NO;
    [archive performOnFilesInArchive:^(UZKFileInfo *fileInfo, BOOL *stop) {
        NSString *filename = fileInfo.filename;
        if (![filename isKindOfClass:[NSString class]] || filename.length == 0) return;
        if ([filename hasPrefix:@"__MACOSX/"]) return;
        if ([filename.lastPathComponent hasPrefix:@"."]) return;
        NSString *normalized = filename;
        if ([normalized hasPrefix:@".minecraft/"]) {
            normalized = [normalized substringFromIndex:@".minecraft/".length];
        }
        for (NSString *entry in ame428_plainZipSignatureEntries()) {
            if ([normalized hasPrefix:entry]) {
                hit = YES;
                *stop = YES;
                return;
            }
        }
    } error:nil];
    return hit;
}

/// zip 内 versions/<v>/<v>.json 推断 MC 版本（优先无 loader 后缀的纯版本；
/// 与 ModpackImportService.detectMinecraftVersionFromArchive 同口径，只读服务不可复用）
+ (nullable NSString *)ame428_detectMinecraftVersionInArchive:(UZKArchive *)archive {
    __block NSString *detected = nil;
    [archive performOnFilesInArchive:^(UZKFileInfo *fileInfo, BOOL *stop) {
        NSString *filename = fileInfo.filename;
        if (![filename isKindOfClass:[NSString class]]) return;
        if ([filename hasPrefix:@".minecraft/"]) {
            filename = [filename substringFromIndex:@".minecraft/".length];
        }
        if ([filename hasPrefix:@"versions/"] && [filename hasSuffix:@".json"]) {
            NSArray *parts = [filename componentsSeparatedByString:@"/"];
            if (parts.count >= 3) {
                NSString *versionFromPath = parts[parts.count - 2];
                if (detected.length == 0) detected = versionFromPath;
                if (![versionFromPath containsString:@"-forge-"] &&
                    ![versionFromPath containsString:@"-neoforge-"] &&
                    ![versionFromPath containsString:@"-fabric-"] &&
                    ![versionFromPath containsString:@"-quilt-"]) {
                    detected = versionFromPath;
                    *stop = YES;
                }
            }
        }
    } error:nil];
    return detected;
}

/// zip 内是否含指定文件（条目名完全匹配）
+ (BOOL)ame428_archiveContainsFile:(UZKArchive *)archive name:(NSString *)name {
    if (name.length == 0) return NO;
    NSData *data = [archive extractDataFromFile:name error:nil];
    return data.length > 0;
}

/// 整合包图标提取（icon.png/modpack.png/pack.png → data URI base64；
/// 与 ModpackImportService.extractIconFromArchive 同一候选清单，只读服务不可复用）
+ (nullable NSString *)ame428_extractIconFromArchive:(UZKArchive *)archive {
    for (NSString *name in @[@"icon.png", @"modpack.png", @"pack.png"]) {
        NSData *data = [archive extractDataFromFile:name error:nil];
        if (data.length > 0) {
            return [NSString stringWithFormat:@"data:image/png;base64,%@",
                    [data base64EncodedStringWithOptions:0]];
        }
    }
    return nil;
}

/// 探测矩阵（判定顺序 = ModpackImportService.parseModpackAtURL 既有顺序，二者结论保持一致）：
///   modrinth.index.json → Modrinth（现有，走既有链）
///   mmc-pack.json        → MultiMC（现有，走既有链；instance.cfg 可选）
///   manifest.json        → CurseForge（现有，走既有链；MCBBS addons 变体由服务链细分）
///   modpack.cfg          → Technic（新，本层归一）
///   webmanifest.json     → FTB（新，本层归一）
///   顶层 .minecraft 结构   → PlainZip（现有，走既有链）
///   其余                  → Unknown（明确报错，不再笼统「无效整合包」）
+ (ModpackFormatKind)ame428_probeFormatAtURL:(NSURL *)fileURL {
    NSString *path = fileURL.path;
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        return ModpackFormatKindUnknown;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return ModpackFormatKindUnknown;
    }
    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&archiveError];
    if (!archive || archiveError) {
        return ModpackFormatKindUnknown;
    }

    // 逐签名文件探测（单条目读取，失败视为不存在）
    if ([self ame428_archiveContainsFile:archive name:@"modrinth.index.json"]) {
        return ModpackFormatKindModrinth;
    }
    if ([self ame428_archiveContainsFile:archive name:@"mmc-pack.json"]) {
        if (![self ame428_archiveContainsFile:archive name:@"instance.cfg"]) {
            NSLog(@"[Task428] MMC pack without instance.cfg — pack name falls back to file name");
        }
        return ModpackFormatKindMultiMC;
    }
    if ([self ame428_archiveContainsFile:archive name:@"manifest.json"]) {
        return ModpackFormatKindCurseForge;
    }
    if ([self ame428_archiveContainsFile:archive name:@"modpack.cfg"]) {
        return ModpackFormatKindTechnic;
    }
    if ([self ame428_archiveContainsFile:archive name:@"webmanifest.json"]) {
        return ModpackFormatKindFTB;
    }
    if ([self ame428_hasPlainZipStructure:archive]) {
        return ModpackFormatKindPlainZip;
    }
    return ModpackFormatKindUnknown;
}

/// IR（ModpackConfiguration）→ 既有安装链 modpackInfo 字典。
/// loader 从 dependencies（Modrinth 键风格）反解，命名对齐安装链
/// installModLoader/versionIdForModpack 的入参口径（Fabric/Quilt/Forge/NeoForge/Vanilla）；
/// files 输出 Modrinth 条目形态（path/downloads/hashes），安装链下载分支原样消费。
+ (NSDictionary *)ame428_installInfoFromConfiguration:(ModpackConfiguration *)cfgIR
                                         installFormat:(NSString *)installFormat
                                         displayFormat:(NSString *)displayFormat
                                                 fileId:(NSString *)modpackId
                                               filePath:(NSString *)filePath
                                        localLoaderJar:(BOOL)localLoaderJar
                                           iconBase64:(nullable NSString *)iconBase64 {
    NSDictionary *deps = [cfgIR.dependencies isKindOfClass:[NSDictionary class]]
        ? cfgIR.dependencies : @{};
    NSString *mcVersion = [deps[@"minecraft"] isKindOfClass:[NSString class]] ? deps[@"minecraft"] : nil;
    if (mcVersion.length == 0) mcVersion = cfgIR.gameVersion;
    if (mcVersion.length == 0) mcVersion = @"unknown";

    NSString *loader = @"Vanilla";
    NSString *loaderVersion = @"";
    if ([deps[@"forge"] isKindOfClass:[NSString class]] && deps[@"forge"].length > 0) {
        loader = @"Forge"; loaderVersion = deps[@"forge"];
    } else if ([deps[@"neoforge"] isKindOfClass:[NSString class]] && deps[@"neoforge"].length > 0) {
        loader = @"NeoForge"; loaderVersion = deps[@"neoforge"];
    } else if ([deps[@"fabric-loader"] isKindOfClass:[NSString class]] && deps[@"fabric-loader"].length > 0) {
        loader = @"Fabric"; loaderVersion = deps[@"fabric-loader"];
    } else if ([deps[@"quilt-loader"] isKindOfClass:[NSString class]] && deps[@"quilt-loader"].length > 0) {
        loader = @"Quilt"; loaderVersion = deps[@"quilt-loader"];
    }

    // files → Modrinth 条目形态（安装链下载分支按 path 前缀分发目录）
    NSMutableArray *fileEntries = [NSMutableArray arrayWithCapacity:cfgIR.files.count];
    for (ModpackFileInformation *f in cfgIR.files) {
        if (![f.path isKindOfClass:[NSString class]] || f.path.length == 0) continue;
        NSString *safePath = f.path;
        while ([safePath hasPrefix:@"/"]) safePath = [safePath substringFromIndex:1];
        NSString *url = [f.downloadURL isKindOfClass:[NSString class]] ? f.downloadURL : @"";
        NSString *hash = [f.fileHash isKindOfClass:[NSString class]] ? f.fileHash : @"";
        [fileEntries addObject:@{
            @"path": safePath,
            @"downloads": url.length > 0 ? @[url] : @[],
            @"hashes": @{@"sha1": hash},
            @"fileSize": @(f.fileSize)
        }];
    }

    return @{
        @"id": modpackId,
        @"name": cfgIR.name ?: modpackId,
        @"version": cfgIR.version ?: @"1.0.0",
        @"minecraftVersion": mcVersion,
        @"loader": loader,
        @"loaderVersion": loaderVersion,
        @"filePath": filePath,
        @"format": installFormat,
        @"files": [fileEntries copy],
        @"iconBase64": iconBase64 ?: @"",
        @"ame428_displayFormat": displayFormat,
        @"ame428_localLoaderJar": @(localLoaderJar)
    };
}

/// Technic 归一（modpack.cfg：.ini 风格，关键键 name/version/download）：
///   - 包名 ← cfg name（缺失回退文件名）；版本 ← cfg version（缺失 1.0.0）
///   - download=（zip url）仅记录透传，不自动拉取（最小实现降级决策）
///   - bin/modpack.jar 存在 → 标记本地加载器；不自动执行（旧式 Technic 加载器
///     在 iOS 端无法headless执行），走 Vanilla 安装 + 导入页明确提示手动装加载器
///   - 内容按 zip 根安装（format=plainzip 语义： Technic 包内容在根目录，
///     versions/ 特例由既有链处理）
+ (nullable NSDictionary *)ame428_technicModpackInfo:(UZKArchive *)archive
                                            filePath:(NSString *)filePath
                                                error:(NSError **)error {
    NSDictionary *cfg = ame428_parseIniStyleConfig(
        [[NSString alloc] initWithData:[archive extractDataFromFile:@"modpack.cfg" error:nil]
                              encoding:NSUTF8StringEncoding] ?: @"");
    NSString *name = cfg[@"name"];
    if (![name isKindOfClass:[NSString class]] || name.length == 0) {
        name = [filePath.lastPathComponent stringByDeletingPathExtension];
    }
    NSString *version = cfg[@"version"];
    if (![version isKindOfClass:[NSString class]] || version.length == 0) {
        version = @"1.0.0";
    }
    NSString *downloadURL = cfg[@"download"];   // 仅读键里有的字段，不编造端点行为

    NSString *mcVersion = [self ame428_detectMinecraftVersionInArchive:archive] ?: @"unknown";
    BOOL hasLocalLoader = [self ame428_archiveContainsFile:archive name:@"bin/modpack.jar"];
    if (downloadURL.length > 0) {
        NSLog(@"[Task428] Technic modpack.cfg download url recorded (not auto-fetched): %@", downloadURL);
    }

    // 归一到 ModpackConfiguration 中间表示
    ModpackConfiguration *cfgIR = [[ModpackConfiguration alloc] initWithName:name version:version gameVersion:mcVersion];
    cfgIR.dependencies = @{@"minecraft": mcVersion};   // 无 loader 元数据 → Vanilla（本地加载器降级）
    cfgIR.files = @[];

    return [self ame428_installInfoFromConfiguration:cfgIR
                                       installFormat:@"plainzip"
                                       displayFormat:@"technic"
                                               fileId:[NSString stringWithFormat:@"technic_%@", [[NSUUID UUID] UUIDString]]
                                             filePath:filePath
                                      localLoaderJar:hasLocalLoader
                                         iconBase64:[self ame428_extractIconFromArchive:archive]];
}

/// FTB 归一（webmanifest.json：name/version/targets；files 内嵌清单）：
///   - targets: minecraft→gameVersion；forge/fabric/neoforge/quilt→loader+版本
///   - files: 仅读 JSON 里有的字段（path/url/hash）→ Modrinth 条目形态；
///     无内嵌 files 且 zip 根无 .minecraft 结构 → 明确报错（在线清单拉取不实现在线行为）
+ (nullable NSDictionary *)ame428_ftbModpackInfo:(UZKArchive *)archive
                                        filePath:(NSString *)filePath
                                            error:(NSError **)error {
    NSData *wmData = [archive extractDataFromFile:@"webmanifest.json" error:nil];
    if (wmData.length == 0) {
        if (error) *error = [self ame428_unrecognizedFormatError:nil];
        return nil;
    }
    NSError *jsonError = nil;
    NSDictionary *wm = [NSJSONSerialization JSONObjectWithData:wmData options:0 error:&jsonError];
    if (jsonError || ![wm isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:kAme428ErrorDomain code:101
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"ame428.import.ftb.malformed", nil)}];
        }
        return nil;
    }

    NSString *name = [wm[@"name"] isKindOfClass:[NSString class]] ? wm[@"name"] : nil;
    if (name.length == 0) name = [filePath.lastPathComponent stringByDeletingPathExtension];
    NSString *version = [wm[@"version"] isKindOfClass:[NSString class]] ? wm[@"version"] : nil;
    if (version.length == 0) version = @"1.0.0";

    // targets → gameVersion + loader（依赖键用 Modrinth 键风格，安装链反解）
    NSString *mcVersion = @"unknown";
    NSString *loaderKey = nil;
    NSString *loaderVersion = nil;
    NSArray *targets = [wm[@"targets"] isKindOfClass:[NSArray class]] ? wm[@"targets"] : @[];
    for (NSDictionary *target in targets) {
        if (![target isKindOfClass:[NSDictionary class]]) continue;
        NSString *tid = [target[@"id"] isKindOfClass:[NSString class]] ? target[@"id"] : nil;
        NSString *tver = [target[@"version"] isKindOfClass:[NSString class]] ? target[@"version"] : nil;
        if (tid.length == 0 || tver.length == 0) continue;
        if ([tid isEqualToString:@"minecraft"]) {
            mcVersion = tver;
        } else if ([tid isEqualToString:@"forge"]) {
            loaderKey = @"forge"; loaderVersion = tver;
        } else if ([tid isEqualToString:@"fabric"]) {
            loaderKey = @"fabric-loader"; loaderVersion = tver;
        } else if ([tid isEqualToString:@"neoforge"]) {
            loaderKey = @"neoforge"; loaderVersion = tver;
        } else if ([tid isEqualToString:@"quilt"]) {
            loaderKey = @"quilt-loader"; loaderVersion = tver;
        }
    }

    // files：内嵌清单 → IR 文件列表（path/url/hash 只取 JSON 里有的字段）
    NSMutableArray *irFiles = [NSMutableArray array];
    NSArray *filesArr = [wm[@"files"] isKindOfClass:[NSArray class]] ? wm[@"files"] : @[];
    for (NSDictionary *f in filesArr) {
        if (![f isKindOfClass:[NSDictionary class]]) continue;
        NSString *fpath = [f[@"path"] isKindOfClass:[NSString class]] ? f[@"path"] : nil;
        if (fpath.length == 0) continue;
        while ([fpath hasPrefix:@"/"]) fpath = [fpath substringFromIndex:1];
        // 路径穿越防护：含 ".." 段的条目丢弃（安装链亦有同款守卫，这里前置拦截）
        if ([[fpath pathComponents] containsObject:@".."]) continue;
        NSString *furl = [f[@"url"] isKindOfClass:[NSString class]] ? f[@"url"] : @"";
        NSString *fhash = [f[@"hash"] isKindOfClass:[NSString class]] ? f[@"hash"] : @"";
        // FTB hash 常见 "sha1:xxxx" 形态；剥前缀后仅 40 位 hex 才透传（安装链只认 40 位）
        NSRange colon = [fhash rangeOfString:@":"];
        if (colon.location != NSNotFound) fhash = [fhash substringFromIndex:colon.location + 1];
        if (fhash.length != 40) fhash = @"";
        NSUInteger fsize = [f[@"size"] isKindOfClass:[NSNumber class]] ? [f[@"size"] unsignedIntegerValue] : 0;
        [irFiles addObject:[[ModpackFileInformation alloc] initWithPath:fpath
                                                               fileHash:fhash
                                                           downloadURL:furl.length > 0 ? furl : @""
                                                               fileSize:fsize]];
    }

    // 空包判定：无内嵌 files 且 zip 根无 .minecraft 结构 → 明确错误
    if (irFiles.count == 0 && ![self ame428_hasPlainZipStructure:archive]) {
        if (error) {
            *error = [NSError errorWithDomain:kAme428ErrorDomain code:102
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"ame428.import.ftb.empty", nil)}];
        }
        return nil;
    }

    // 归一到 ModpackConfiguration 中间表示
    ModpackConfiguration *cfgIR = [[ModpackConfiguration alloc] initWithName:name version:version gameVersion:mcVersion];
    NSMutableDictionary *deps = [NSMutableDictionary dictionaryWithObject:mcVersion forKey:@"minecraft"];
    if (loaderKey.length > 0 && loaderVersion.length > 0) {
        deps[loaderKey] = loaderVersion;
    }
    cfgIR.dependencies = [deps copy];
    cfgIR.files = [irFiles copy];
    cfgIR.packDescription = [wm[@"description"] isKindOfClass:[NSString class]] ? wm[@"description"] : nil;

    // FTB 内容在 zip 根（.minecraft 前缀由既有链剥离）→ format=plainzip 安装语义
    return [self ame428_installInfoFromConfiguration:cfgIR
                                       installFormat:@"plainzip"
                                       displayFormat:@"ftb"
                                               fileId:[NSString stringWithFormat:@"ftb_%@", [[NSUUID UUID] UUIDString]]
                                             filePath:filePath
                                      localLoaderJar:NO
                                         iconBase64:[self ame428_extractIconFromArchive:archive]];
}

+ (nullable NSDictionary *)ame428_modpackInfoForURL:(NSURL *)fileURL
                                               kind:(ModpackFormatKind)kind
                                              error:(NSError **)error {
    if (kind != ModpackFormatKindTechnic && kind != ModpackFormatKindFTB) {
        // 其余格式走 ModpackImportService 既有解析（分发层负责，本层不重复实现）
        if (error) *error = [self ame428_unrecognizedFormatError:nil];
        return nil;
    }
    NSString *path = fileURL.path;
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        if (error) *error = [self ame428_unrecognizedFormatError:nil];
        return nil;
    }
    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = [self ame428_unrecognizedFormatError:archiveError];
        return nil;
    }
    if (kind == ModpackFormatKindTechnic) {
        return [self ame428_technicModpackInfo:archive filePath:path error:error];
    }
    return [self ame428_ftbModpackInfo:archive filePath:path error:error];
}

+ (NSError *)ame428_unrecognizedFormatError:(nullable NSError *)originalError {
    NSString *message = localize(@"ame428.import.unrecognized", nil);
    if (originalError.localizedDescription.length > 0) {
        message = [NSString stringWithFormat:@"%@\n(%@)", message, originalError.localizedDescription];
    }
    return [NSError errorWithDomain:kAme428ErrorDomain code:100
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end