#import "PLRendererPluginService.h"
#import "AmePluginPermissions.h"
#import "utils.h"   // ★Task449：localize（演示插件档显示名 i18n 化）
#import "UnzipKit.h"

#import <UIKit/UIKit.h>

// ═══════════════════════════════════════════════════════════════════
// PLRendererPluginService 实现（★Task429 / PDF v5 §11.4 + v6 §3.2.1）
// 口径注释：
//  · 校验先行（manifest 三字段 → dylib 白名单 → ABI 过滤），全过才落位，
//    失败不产生半成品目录（AmePluginManager.installFromZip 同纪律）
//  · 同 id 重装 = 覆盖，enabled 态保留（升级不丢启停，JS 插件同语义）
//  · 解压使用 UnzipKit（与 JS 插件安装同源依赖，零新增链接）
//  · dylib 白名单：仅 ①插件 renderer 目录内 ②bundle Frameworks 回退
//    （随包内置绑定）两处来源；其余路径一律不收编（§11.4 判例）
//  · state.json 启停/删除复用 AmePluginPermissions（管理端与 JS 插件
//    共用同一注册表——§11.4"仅包格式校验不同"）
//  · 本 TU 未进构建（主控未补 CMakeLists 行）时消费方 NSClassFromString
//    得 nil，全部消费面跳过——零崩溃（ame428 软链判例）
// ═══════════════════════════════════════════════════════════════════

// manifest / 注册表键（常量实名判例）
static NSString * const kPL429ManifestRendererName = @"rendererName";
static NSString * const kPL429ManifestDriverType   = @"driverType";
static NSString * const kPL429ManifestABI          = @"abi";
static NSString * const kPL429ManifestDylib        = @"dylib";
static NSString * const kPL429DriverConfigFile     = @"driver.json";
static NSString * const kPL429RegistryFile         = @".ame429-renderers.json";
static NSString * const kPL429BuiltinMarker        = @".ame429-builtin";
static NSString * const kPL429BundleBuiltinDir     = @"builtin-renderers";
static NSString * const kPL429DeviceABI            = @"arm64";
static NSString * const kPL429DriverMobileGlues    = @"mobileglues";
static NSString * const kPL429DemoBuiltinId        = @"mobileglues-demo";

/// 内置渲染器插件包兜底清单（bundle builtin-renderers 缺席时的代码侧
/// 种子——第六版"清单注册"单一链路的保底通道：随包 dylib 绑定走 bundle
/// Frameworks 回退（libmobileglues.dylib 恒随包），manifest/driver 配置
/// 由此处落到插件目录后与 zip 安装件完全同生命周期。防御守卫配真实现：
/// 资源打包通道（主控补 CMakeLists Resources 行）就绪前链条照常可证）。
static NSDictionary *kPL429SeedBuiltinManifest(void) {
    return @{
        @"id": kPL429DemoBuiltinId,
        @"name": localize(@"ame449.plugin.mg_demo_name", @"MobileGlues 渲染器插件（内置演示档）"),
        @"version": @"1.0.0",
        kPL429ManifestRendererName: localize(@"ame449.plugin.mg_plugin_name", @"MobileGlues（渲染器插件档）"),
        kPL429ManifestDriverType: kPL429DriverMobileGlues,
        kPL429ManifestABI: @[kPL429DeviceABI],
        kPL429ManifestDylib: @"libmobileglues.dylib",
        @"description": localize(@"ame449.plugin.mg_demo_desc", @"内置渲染器插件包单条链路演示：清单注册→扫描→启动注入→UI 呈现渲染器档位。dylib 绑定随包 Frameworks/libmobileglues.dylib（白名单回退源②）。"),
    };
}

static NSDictionary *kPL429SeedBuiltinDriverConfig(void) {
    // 与 MobileGlues config.json 同构的驱动配置种子（仅演示覆盖层链路：
    // 用户分区偏好照常生效，本表仅在该插件档会话做末位覆盖）
    return @{ @"enableNoError": @0 };
}

// ★Task429-r10：类扩展 readwrite 重声明（同文件服务 @implementation 给
//   PLRendererPluginEntry 装配只读属性——跨 @implementation 私有 ivar 直访
//   = "instance variable is private" 判例族；setter 经 Entry @synthesize 链接）。
@interface PLRendererPluginEntry ()
@property (nonatomic, copy, readwrite) NSString *pluginId;
@property (nonatomic, copy, readwrite) NSString *rendererName;
@property (nonatomic, copy, readwrite) NSString *driverType;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *abi;
@property (nonatomic, copy, readwrite) NSString *version;
@property (nonatomic, copy, readwrite, nullable) NSString *dylibFile;
@property (nonatomic, copy, readwrite) NSString *packageDir;
@property (nonatomic, copy, readwrite, nullable) NSString *resolvedDylibPath;
@property (nonatomic, copy, readwrite, nullable) NSString *driverConfigPath;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *driverConfig;
@property (nonatomic, assign, readwrite) BOOL enabled;
@end

@implementation PLRendererPluginEntry
@end

@interface PLRendererPluginService ()
@property (nonatomic, strong) NSArray<PLRendererPluginEntry *> *scanCache;
// ★Task429（审计补全）：类方法先声明后实现 —— pl429_trimmed 在 manifest
//   校验（pl429_validateRendererManifest）首行前消费、
//   pl429_bootstrapBuiltinRendererPackages 在 availableRenderers 首行前消费
//   （两处消费点均早于 @implementation 内的完整定义）；类扩展内前置声明
//   消除 use-before-declaration 告警面，实现体位置保持不动。
+ (nullable NSDictionary *)pl429_trimmed:(id)raw;
+ (void)pl429_bootstrapBuiltinRendererPackages;
@end

@implementation PLRendererPluginService

+ (instancetype)sharedService {
    static PLRendererPluginService *svc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        svc = [[PLRendererPluginService alloc] init];
    });
    return svc;
}

+ (NSString *)rendererPluginsRootDir {
    // Prisma2/plugins/renderer（AmePluginManager.installedPluginIds 扫描
    // 只收根目录带 manifest.json 的目录——renderer 子目录天然不可见）
    NSString *root = [ame317_pluginsRootDir() stringByAppendingPathComponent:@"renderer"];
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}

#pragma mark - 缓存失效

- (void)pl429_invalidateScanCache {
    @synchronized(self) {
        self.scanCache = nil;
    }
}

#pragma mark - manifest 校验（渲染器插件包格式）

/// 渲染器包 manifest 校验：id 沿用 JS 插件同一字符集，三字段（渲染器名/
/// 驱动类型/ABI 架构）必填，dylib 可选（纯文件名，禁路径段）。
/// 通过返回规范化字典；失败返回 nil 并填充 errCode。
+ (nullable NSDictionary *)pl429_validateRendererManifest:(NSDictionary *)dict
                                                 errCode:(AmePluginInstallResult *)errCode {
    AmePluginInstallResult fail = AmePluginInstallErrBadSchema;
    if (![dict isKindOfClass:[NSDictionary class]]) {
        fail = AmePluginInstallErrBadJSON;
        if (errCode) *errCode = fail;
        return nil;
    }
    NSString *pid = [self pl429_trimmed:dict[@"id"]];
    if (pid.length < 3 || pid.length > 64) {
        if (errCode) *errCode = fail;
        return nil;
    }
    NSCharacterSet *pl429_idChars = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    unichar pl429_c0 = [pid characterAtIndex:0];
    if (![[NSCharacterSet characterSetWithCharactersInString:
           @"abcdefghijklmnopqrstuvwxyz0123456789"] characterIsMember:pl429_c0] ||
        [pid isEqualToString:@"renderer"]) {
        // id 白名单 + 防与 renderer 子目录自身同名（目录自引用自愈不可达）
        if (errCode) *errCode = fail;
        return nil;
    }
    for (NSUInteger i = 0; i < pid.length; i++) {
        if (![pl429_idChars characterIsMember:[pid characterAtIndex:i]]) {
            if (errCode) *errCode = fail;
            return nil;
        }
    }
    NSString *rname = [self pl429_trimmed:dict[kPL429ManifestRendererName]];
    if (rname.length == 0 || rname.length > 64) {
        if (errCode) *errCode = fail;
        return nil;
    }
    NSString *dtype = [self pl429_trimmed:dict[kPL429ManifestDriverType]];
    if (dtype.length == 0 || dtype.length > 32) {
        if (errCode) *errCode = fail;
        return nil;
    }
    id abiRaw = dict[kPL429ManifestABI];
    if (![abiRaw isKindOfClass:[NSArray class]] || [(NSArray *)abiRaw count] == 0) {
        if (errCode) *errCode = fail;
        return nil;
    }
    NSMutableArray<NSString *> *abi = [NSMutableArray array];
    for (id item in abiRaw) {
        NSString *s = [self pl429_trimmed:item];
        if (s.length == 0 || s.length > 32) {
            if (errCode) *errCode = fail;
            return nil;
        }
        if (![abi containsObject:s]) [abi addObject:s];
    }
    NSString *dylib = [self pl429_trimmed:dict[kPL429ManifestDylib]];
    if (dylib != nil) {
        // dylib 必须是纯文件名（禁路径段/禁 .. ——白名单拼接的前提）
        if (dylib.length > 128 || [dylib hasPrefix:@"/"] ||
            [dylib containsString:@"/"] || [dylib containsString:@".."] ||
            ![dylib hasSuffix:@".dylib"]) {
            if (errCode) *errCode = fail;
            return nil;
        }
    }
    NSString *ver = [self pl429_trimmed:dict[@"version"]];
    if (ver.length == 0 || ver.length > 32) {
        if (errCode) *errCode = fail;
        return nil;
    }
    return @{@"id": pid,
             kPL429ManifestRendererName: rname,
             kPL429ManifestDriverType: dtype,
             kPL429ManifestABI: abi,
             @"version": ver,
             kPL429ManifestDylib: dylib ?: @""};
}

+ (nullable NSString *)pl429_trimmed:(id)raw {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length ? s : nil;
}

#pragma mark - dylib 白名单解析

/// 白名单两处来源（§11.4）：①插件 renderer 目录内 ②bundle Frameworks
/// （随包内置绑定回退——内置演示档引用随包 libmobileglues.dylib）。
/// 返回 nil = 两处皆缺（不上架渲染器列表）。
+ (nullable NSString *)pl429_resolveDylibPath:(NSString *)dylibFile
                                    packageDir:(NSString *)packageDir {
    if (dylibFile.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *inPackage = [packageDir stringByAppendingPathComponent:dylibFile];
    if ([fm fileExistsAtPath:inPackage]) return inPackage;
    // 回退源②：bundle Frameworks（内置绑定；物理上等同经典渲染器随包件，
    // dlopen 按 dyld 路径去重——内置档会话与经典选择共享同一镜像）
    NSString *inFrameworks = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:[@"Frameworks" stringByAppendingPathComponent:dylibFile]];
    if ([fm fileExistsAtPath:inFrameworks]) return inFrameworks;
    return nil;
}

#pragma mark - 条目构造

+ (nullable PLRendererPluginEntry *)pl429_entryAtDir:(NSString *)dir pluginId:(NSString *)pid {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *data = [NSData dataWithContentsOfFile:
        [dir stringByAppendingPathComponent:@"manifest.json"]];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    AmePluginInstallResult code = AmePluginInstallOK;
    NSDictionary *m = [self pl429_validateRendererManifest:json errCode:&code];
    if (!m) {
        NSLog(@"[Ame429] renderer plugin '%@' skipped (manifest errCode=%ld)", pid, (long)code);
        return nil;
    }
    // ABI 过滤：manifest 声明的架构必须含本机 ABI（iOS 设备恒 arm64）
    if (![m[kPL429ManifestABI] containsObject:kPL429DeviceABI]) {
        NSLog(@"[Ame429] renderer plugin '%@' skipped (abi %@ lacks %@)",
              pid, [m[kPL429ManifestABI] componentsJoinedByString:@","], kPL429DeviceABI);
        return nil;
    }
    PLRendererPluginEntry *e = [[PLRendererPluginEntry alloc] init];
    e.pluginId = pid;
    e.rendererName = m[kPL429ManifestRendererName];
    e.driverType = m[kPL429ManifestDriverType];
    e.abi = m[kPL429ManifestABI];   // ★Task429-r11：validate 的 abi 局部数组未回写 m，此处取 manifest 原始数组（条目已在 validate 过长度闸）
    e.version = m[@"version"];
    e.dylibFile = ([m[kPL429ManifestDylib] length] > 0 ? m[kPL429ManifestDylib] : nil);
    e.packageDir = dir;
    e.resolvedDylibPath = [self pl429_resolveDylibPath:e.dylibFile packageDir:dir];
    // 驱动配置（可选；解析失败按缺省——宁缺勿错）
    NSString *cfgPath = [dir stringByAppendingPathComponent:kPL429DriverConfigFile];
    NSData *cfgData = [NSData dataWithContentsOfFile:cfgPath];
    if (cfgData) {
        id cfg = [NSJSONSerialization JSONObjectWithData:cfgData options:0 error:nil];
        if ([cfg isKindOfClass:[NSDictionary class]]) {
            e.driverConfigPath = cfgPath;
            e.driverConfig = cfg;
        } else {
            NSLog(@"[Ame429] renderer plugin '%@' driver.json is not a JSON object -- ignored", pid);
        }
    }
    e.enabled = [AmePluginPermissions pluginEnabled:pid];
    return e;
}

#pragma mark - 扫描

+ (NSArray<PLRendererPluginEntry *> *)availableRenderers {
    PLRendererPluginService *svc = [self sharedService];
    @synchronized(svc) {
        if (svc.scanCache) return svc.scanCache;
    }
    [self pl429_bootstrapBuiltinRendererPackages];
    NSMutableArray<PLRendererPluginEntry *> *out = [NSMutableArray array];
    NSString *root = [self rendererPluginsRootDir];
    NSArray<NSString *> *dirs = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:root error:nil];
    for (NSString *name in dirs) {
        if ([name hasPrefix:@"."]) continue;   // 隐藏/临时/隔离目录
        NSString *dir = [root stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        PLRendererPluginEntry *e = [self pl429_entryAtDir:dir pluginId:name];
        if (e) [out addObject:e];
    }
    [out sortUsingComparator:^NSComparisonResult(PLRendererPluginEntry *a, PLRendererPluginEntry *b) {
        return [a.pluginId compare:b.pluginId];
    }];
    @synchronized(svc) {
        svc.scanCache = [out copy];
    }
    return [out copy];
}

+ (nullable PLRendererPluginEntry *)entryForRendererKey:(NSString *)key {
    if (key.length == 0) return nil;
    for (PLRendererPluginEntry *e in [self availableRenderers]) {
        if ([e.pluginId isEqualToString:key]) return e;
    }
    return nil;
}

+ (BOOL)isRendererPluginId:(NSString *)key {
    return [self entryForRendererKey:key] != nil;
}

#pragma mark - 渲染器列表动态扩展（消费面）

+ (NSArray<NSDictionary *> *)rendererChoiceOverrides {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (PLRendererPluginEntry *e in [self availableRenderers]) {
        // 仅收编：已启用 + dylib 白名单校验通过（管理信息不因停用丢失——
        // 停用条目仍可在 availableRenderers/管理页可见，只是不出渲染器档）
        if (!e.enabled) continue;
        if (e.resolvedDylibPath.length == 0) continue;
        [out addObject:@{@"key": e.pluginId,
                         @"name": e.rendererName,
                         @"file": e.dylibFile ?: @""}];
    }
    return [out copy];
}

#pragma mark - 启停（state.json，与 JS 插件同源）

+ (BOOL)isRendererPluginEnabled:(NSString *)pluginId {
    if (pluginId.length == 0) return NO;
    return [AmePluginPermissions pluginEnabled:pluginId];
}

+ (void)setRendererPluginEnabled:(BOOL)enabled pluginId:(NSString *)pluginId {
    if (pluginId.length == 0) return;
    [AmePluginPermissions setPluginEnabled:enabled pluginId:pluginId];
    [[self sharedService] pl429_invalidateScanCache];
    NSLog(@"[Ame429] renderer plugin '%@' enabled=%d (state.json shared with JS plugins)", pluginId, enabled ? 1 : 0);
}

#pragma mark - 登记

/// 登记清单（.ame429-renderers.json：点前缀 = JS 插件扫描天然跳过）。
/// 结构 {installed: {id: {name, version, installedAt}}} —— 扫描面以目录为
/// 准（登记仅承载安装时间/来源审计），写失败不阻断安装。
+ (void)pl429_noteInstalled:(NSString *)pid name:(NSString *)name version:(NSString *)version {
    NSString *path = [[self rendererPluginsRootDir] stringByAppendingPathComponent:kPL429RegistryFile];
    NSMutableDictionary *reg = nil;
    NSData *old = [NSData dataWithContentsOfFile:path];
    id json = old ? [NSJSONSerialization JSONObjectWithData:old options:0 error:nil] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) reg = [json mutableCopy];
    if (!reg) reg = [NSMutableDictionary dictionary];
    NSMutableDictionary *installed = [([reg[@"installed"] isKindOfClass:[NSDictionary class]]
        ? reg[@"installed"] : @{}) mutableCopy];
    installed[pid] = @{@"name": name ?: @"",
                       @"version": version ?: @"",
                       @"installedAt": @([NSDate date].timeIntervalSince1970)};
    reg[@"installed"] = installed;
    NSData *out = [NSJSONSerialization dataWithJSONObject:reg
                                                  options:NSJSONWritingPrettyPrinted error:nil];
    if (out) [out writeToFile:path atomically:YES];
}

#pragma mark - 安装

+ (AmePluginInstallResult)installRendererPluginFromZip:(NSString *)zipPath
                                                 outId:(NSString *_Nullable *_Nullable)outId {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (outId) *outId = nil;

    NSError *aErr = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&aErr];
    if (!archive) return AmePluginInstallErrReadZip;

    // ① 根部 manifest.json（兼容单层子目录包裹——JS 插件同判例）
    NSData *manifestData = [archive extractDataFromFile:@"manifest.json" error:nil];
    NSString *stripPrefix = @"";
    if (!manifestData) {
        __block NSString *pl429_singleDir = nil;
        __block BOOL pl429_ambiguous = NO;
        [archive performOnFilesInArchive:^(UZKFileInfo *info, BOOL *stop) {
            NSString *name = info.filename;
            if (name.length == 0) return;
            NSArray<NSString *> *segs = [name pathComponents];
            if (segs.count < 2) return;
            NSString *top = segs[0];
            if ([top hasPrefix:@"."]) return;
            if (pl429_singleDir == nil) { pl429_singleDir = top; }
            else if (![pl429_singleDir isEqualToString:top]) { pl429_ambiguous = YES; *stop = YES; }
        } error:nil];
        if (pl429_singleDir && !pl429_ambiguous) {
            stripPrefix = [pl429_singleDir stringByAppendingString:@"/"];
            manifestData = [archive extractDataFromFile:
                [stripPrefix stringByAppendingString:@"manifest.json"] error:nil];
        }
    }
    if (!manifestData) return AmePluginInstallErrNoManifest;

    // ② 渲染器包 manifest 校验（三字段 + id + dylib 文件名形态）
    id json = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
    AmePluginInstallResult code = AmePluginInstallOK;
    NSDictionary *m = [self pl429_validateRendererManifest:json errCode:&code];
    if (!m) return code;
    NSString *pid = m[@"id"];

    // ③ 解压到暂存目录
    NSString *tmpRoot = [NSTemporaryDirectory()
        stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ame429-install-%@", [NSUUID UUID].UUIDString]];
    if (![fm createDirectoryAtPath:tmpRoot withIntermediateDirectories:YES attributes:nil error:nil]) {
        return AmePluginInstallErrMove;
    }
    NSError *xErr = nil;
    BOOL extracted = [archive extractFilesTo:tmpRoot overwrite:YES error:&xErr];
    if (!extracted) {
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrReadZip;
    }
    NSString *stagedDir = tmpRoot;
    if (stripPrefix.length) {
        stagedDir = [tmpRoot stringByAppendingPathComponent:
            [stripPrefix substringToIndex:stripPrefix.length - 1]];
    }

    // ④ dylib 存在性（包内 或 随包 Frameworks 回退；两处皆缺 =
    //    ErrBadEntry——渲染器档无库即死条目，拒装）
    NSString *dylibFile = m[kPL429ManifestDylib];
    if (dylibFile.length > 0) {
        NSString *resolved = [self pl429_resolveDylibPath:dylibFile packageDir:stagedDir];
        if (resolved.length == 0) {
            NSLog(@"[Ame429] install rejected: %@ dylib '%@' found neither in package nor bundle Frameworks", pid, dylibFile);
            [fm removeItemAtPath:tmpRoot error:nil];
            return AmePluginInstallErrBadEntry;
        }
    }
    // ABI 预检：非本机架构包拒装（宁拒勿藏——扫描面静默过滤只对存量件）
    if (![m[kPL429ManifestABI] containsObject:kPL429DeviceABI]) {
        NSLog(@"[Ame429] install rejected: %@ abi %@ lacks device abi %@",
              pid, [m[kPL429ManifestABI] componentsJoinedByString:@","], kPL429DeviceABI);
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrBadSchema;
    }

    // ⑤ 落位到 renderer 子目录（同 id 覆盖，enabled 态保留）
    NSString *destDir = [[self rendererPluginsRootDir] stringByAppendingPathComponent:pid];
    NSString *rootDir = [self rendererPluginsRootDir];
    NSString *backup = [rootDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@".ame429-old-%@", [NSUUID UUID].UUIDString]];
    if ([fm fileExistsAtPath:destDir]) {
        [fm moveItemAtPath:destDir toPath:backup error:nil];
    }
    BOOL moved = [fm moveItemAtPath:stagedDir toPath:destDir error:nil];
    if (!moved) {
        if ([fm fileExistsAtPath:backup]) [fm moveItemAtPath:backup toPath:destDir error:nil];
        [fm removeItemAtPath:tmpRoot error:nil];
        return AmePluginInstallErrMove;
    }
    [fm removeItemAtPath:backup error:nil];
    [fm removeItemAtPath:tmpRoot error:nil];

    // ⑥ 登记清单 + 首装默认启用（渲染器档只新增列表项，不劫持用户当前
    //    选中值——默认启用与 JS 插件安装语义一致且无越权面）
    [self pl429_noteInstalled:pid name:m[kPL429ManifestRendererName] version:m[@"version"]];
    if (![AmePluginPermissions pluginEnabled:pid]) {
        [AmePluginPermissions setPluginEnabled:YES pluginId:pid];
    }
    [[self sharedService] pl429_invalidateScanCache];
    NSLog(@"[Ame429] renderer plugin installed: %@ (%@ v%@, driver=%@, abi=%@)",
          pid, m[kPL429ManifestRendererName], m[@"version"], m[kPL429ManifestDriverType],
          [m[kPL429ManifestABI] componentsJoinedByString:@","]);
    if (outId) *outId = pid;
    return AmePluginInstallOK;
}

#pragma mark - 卸载

+ (BOOL)uninstallRendererPlugin:(NSString *)pluginId {
    if (pluginId.length == 0 || [pluginId isEqualToString:@"renderer"]) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [[self rendererPluginsRootDir] stringByAppendingPathComponent:pluginId];
    BOOL ok = YES;
    if ([fm fileExistsAtPath:dir]) {
        ok = [fm removeItemAtPath:dir error:nil];
    }
    // 与 JS 插件卸载同款：purge grants + enabled（state.json 同一注册表）
    [AmePluginPermissions purgePluginState:pluginId];
    // 登记清单同步摘除（审计面不留幽灵条目）
    NSString *regPath = [[self rendererPluginsRootDir] stringByAppendingPathComponent:kPL429RegistryFile];
    NSData *old = [NSData dataWithContentsOfFile:regPath];
    id json = old ? [NSJSONSerialization JSONObjectWithData:old options:0 error:nil] : nil;
    if ([json isKindOfClass:[NSDictionary class]] && json[@"installed"][pluginId] != nil) {
        NSMutableDictionary *reg = [json mutableCopy];
        NSMutableDictionary *installed = [([reg[@"installed"] isKindOfClass:[NSDictionary class]]
            ? reg[@"installed"] : @{}) mutableCopy];
        [installed removeObjectForKey:pluginId];
        reg[@"installed"] = installed;
        NSData *out = [NSJSONSerialization dataWithJSONObject:reg
                                                      options:NSJSONWritingPrettyPrinted error:nil];
        if (out) [out writeToFile:regPath atomically:YES];
    }
    [[self sharedService] pl429_invalidateScanCache];
    NSLog(@"[Ame429] renderer plugin uninstalled: %@ (ok=%d)", pluginId, ok ? 1 : 0);
    return ok;
}

#pragma mark - 内置渲染器插件包引导（第六版单条链路：清单注册）

/// 内置包引导（幂等）：bundle builtin-renderers/<dir> 有而未装即落位
/// （manifest + driver.json 双件，dylib 缺省走 Frameworks 回退）；bundle
/// 通道缺席时代码侧种子清单保底（防御守卫配真实现）。首方信任语义
/// （Task326 heal 同族）：内置档自动启用——启用仅新增渲染器列表档位，
/// 不改写用户当前选中渲染器，无越权面。
+ (void)pl429_bootstrapBuiltinRendererPackages {
    static dispatch_once_t pl429_once;
    dispatch_once(&pl429_once, ^{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundleRoot = [[NSBundle mainBundle].resourcePath
        stringByAppendingPathComponent:kPL429BundleBuiltinDir];
    NSArray<NSString *> *bundled = [fm contentsOfDirectoryAtPath:bundleRoot error:nil];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSString *dir in bundled) {
        if ([dir hasPrefix:@"."]) continue;
        NSData *mf = [NSData dataWithContentsOfFile:
            [[bundleRoot stringByAppendingPathComponent:dir]
             stringByAppendingPathComponent:@"manifest.json"]];
        if (mf) [ids addObject:dir];
    }
    BOOL seeded = NO;
    // bundle 通道缺席时代码侧种子（第六版链路保底：装机无需等待资源打包线）
    if (ids.count == 0) {
        [ids addObject:kPL429DemoBuiltinId];
        seeded = YES;
    }
    for (NSString *pid in ids) {
        NSString *dstDir = [[self rendererPluginsRootDir] stringByAppendingPathComponent:pid];
        if ([fm fileExistsAtPath:[dstDir stringByAppendingPathComponent:@"manifest.json"]]) {
            continue;   // 已装（幂等；重装/升级走管理端 zip 链）
        }
        NSDictionary *manifest = nil;
        NSDictionary *driverCfg = nil;
        NSString *srcDir = nil;
        if (!seeded) {
            srcDir = [bundleRoot stringByAppendingPathComponent:pid];
            NSData *mf = [NSData dataWithContentsOfFile:
                [srcDir stringByAppendingPathComponent:@"manifest.json"]];
            id json = mf ? [NSJSONSerialization JSONObjectWithData:mf options:0 error:nil] : nil;
            if (![json isKindOfClass:[NSDictionary class]]) continue;
            manifest = json;
            NSData *cfg = [NSData dataWithContentsOfFile:
                [srcDir stringByAppendingPathComponent:kPL429DriverConfigFile]];
            id cfgJson = cfg ? [NSJSONSerialization JSONObjectWithData:cfg options:0 error:nil] : nil;
            if ([cfgJson isKindOfClass:[NSDictionary class]]) driverCfg = cfgJson;
        } else {
            manifest = kPL429SeedBuiltinManifest();
            driverCfg = kPL429SeedBuiltinDriverConfig();
        }
        AmePluginInstallResult code = AmePluginInstallOK;
        if (![self pl429_validateRendererManifest:manifest errCode:&code]) {
            NSLog(@"[Ame429] builtin renderer bootstrap skipped: %@ (manifest errCode=%ld)", pid, (long)code);
            continue;
        }
        if (![fm createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil]) continue;
        NSData *mfOut = [NSJSONSerialization dataWithJSONObject:manifest
                                                        options:NSJSONWritingPrettyPrinted error:nil];
        BOOL ok = mfOut && [mfOut writeToFile:[dstDir stringByAppendingPathComponent:@"manifest.json"]
                                      atomically:YES];
        if (driverCfg) {
            NSData *cfgOut = [NSJSONSerialization dataWithJSONObject:driverCfg
                                                             options:NSJSONWritingPrettyPrinted error:nil];
            ok = ok && cfgOut &&
                [cfgOut writeToFile:[dstDir stringByAppendingPathComponent:kPL429DriverConfigFile]
                            atomically:YES];
        }
        // 包内 dylib 随拷（bundle 件自带库时落位；无库 = Frameworks 回退）
        if (!seeded && srcDir) {
            NSString *pl429_bundleDylib = manifest[kPL429ManifestDylib];
            if (pl429_bundleDylib.length > 0) {
                NSString *srcDylib = [srcDir stringByAppendingPathComponent:pl429_bundleDylib];
                if ([fm fileExistsAtPath:srcDylib]) {
                    [fm copyItemAtPath:srcDylib
                               toPath:[dstDir stringByAppendingPathComponent:pl429_bundleDylib]
                                error:nil];
                }
            }
        }
        if (!ok) {
            NSLog(@"[Ame429] builtin renderer bootstrap write FAILED: %@", pid);
            [fm removeItemAtPath:dstDir error:nil];
            continue;
        }
        // 首方信任：内置档自动启用 + 内置标记（卸载保护留给管理端提示面）
        [AmePluginPermissions setPluginEnabled:YES pluginId:pid];
        [@"builtin" writeToFile:[dstDir stringByAppendingPathComponent:kPL429BuiltinMarker]
                     atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [self pl429_noteInstalled:pid
                             name:manifest[kPL429ManifestRendererName]
                          version:manifest[@"version"]];
        NSLog(@"[Ame429] builtin renderer bootstrap install: %@ (driver=%@, dylib binding=%@, chain: manifest->scan->inject->UI tier)",
              pid, manifest[kPL429ManifestDriverType], manifest[kPL429ManifestDylib]);
    }
    });
}

@end
