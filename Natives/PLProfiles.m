//
//  PLProfiles.m
//  Amethyst
//
//  Profile manager with JSON-safe save
//

#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"
#import "ModLoaderIconHelper.h"   // ★Task428：AUTO 档 loader 标记判据（detectLoaderFromVersionId）
#import <UIKit/UIKit.h>           // ★Task428：共享迁移确认流（UIAlertController；宿主 = 本模型类——页面间零直连纪律）
#include <string.h>               // ★Task428：zip 快照写器 memset

static PLProfiles* current;

// ★ Task353：进程内“最后已知完好注册表”路径锚——读成功才记录；
//   initWithCurrentInstance 读失守时优先回读该锚（零写入），防启动期版本根
//   对齐窗口内 updateCurrent 把出厂注册表误写进无注册表的实例根（病历见
//   initWithCurrentInstance 注）。仅进程内生命周期，冷启动无锚走原语义。
static NSString *_ame353_registryLastGoodPath = nil;

// ---------------------------------------------------------------------------
// ★Task428：本节 C 助手（文件级；zip 快照写器专用）——小端写入 / DOS
// 时间戳 / CRC32（zlib 链式语义兼容：初值 0、返回值可直接续传；表驱动
// poly 0xEDB88320，零链接期依赖）。文件属性一律 NSFileSize/
// NSFileModificationDate 下标取值（main.m CI 判例：属性点语法在部分编译
// 单元不可见）。
// ---------------------------------------------------------------------------
static void ame428_put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xff); p[1] = (uint8_t)(v >> 8);
}
static void ame428_put32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xff); p[1] = (uint8_t)((v >> 8) & 0xff);
    p[2] = (uint8_t)((v >> 16) & 0xff); p[3] = (uint8_t)((v >> 24) & 0xff);
}
static uint32_t ame428_crc32(uint32_t crc, const void *buf, unsigned len) {
    static uint32_t ame428_tab[256];
    static dispatch_once_t ame428_once;
    dispatch_once(&ame428_once, ^{
        for (unsigned ame428_n = 0; ame428_n < 256; ame428_n++) {
            uint32_t ame428_c = (uint32_t)ame428_n;
            for (int ame428_k = 0; ame428_k < 8; ame428_k++) {
                ame428_c = (ame428_c & 1) ? (0xEDB88320u ^ (ame428_c >> 1)) : (ame428_c >> 1);
            }
            ame428_tab[ame428_n] = ame428_c;
        }
    });
    crc = crc ^ 0xFFFFFFFFu;
    const uint8_t *ame428_b = (const uint8_t *)buf;
    while (len--) crc = ame428_tab[(crc ^ *ame428_b++) & 0xff] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}
static void ame428_dosDateTime(NSDate *when, uint16_t *outTime, uint16_t *outDate) {
    if (!outTime || !outDate) return;
    NSCalendar *ame428_cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *ame428_c = [ame428_cal components:
        (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
         NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
        fromDate:(when ?: [NSDate date])];
    if (!ame428_c) { *outTime = 0; *outDate = (1 << 21) | (1 << 16) | 1; return; }
    NSInteger ame428_year = ame428_c.year < 1980 ? 1980 : (ame428_c.year > 2107 ? 2107 : ame428_c.year);
    *outDate = (uint16_t)(((ame428_year - 1980) << 9)
        | ((ame428_c.month ?: 1) << 5) | (ame428_c.day ?: 1));
    *outTime = (uint16_t)(((ame428_c.hour ?: 0) << 11)
        | ((ame428_c.minute ?: 0) << 5) | (((ame428_c.second ?: 0) / 2) & 0x1f));
}

@interface PLProfiles()
// ---------------------------------------------------------------------------
// ★Task428（1.3）：主页有效性判定——扫描口径轻量子集。
// 「存在且可解析」= 在列（版本列表同判据）。路径序（Task351/255/256 原序
// 保留，仅把 fileExists 收紧为 parseable）：
//   ① latest 别名恒有效（在线解析下载流，Task351 原语义）；
//   ② profile 自身 gameDir 根（版本隔离/自定义实例的版本实体在自己根）；
//   ③ 现役根（GAME_DIR = instances/<当前实例>）；
//   ④ POJAV_HOME 旧布局兜底（仅当主根来自 GAME_DIR）。
// 宿主 = 本模型类：ZL2Home 与版本页共用，页面间零直连（ZL2Home 文件头
// Task323 判例纪律）。
// ---------------------------------------------------------------------------
+ (BOOL)ame428_jsonManifestParsesAtPath:(NSString *)path {
    if (path.length == 0) return NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return NO;
    NSMutableDictionary *ame428_parsed = parseJSONFromFile(path);
    return [ame428_parsed isKindOfClass:[NSDictionary class]] && !ame428_parsed[@"NSErrorObject"];
}

@end

@implementation PLProfiles

+ (id)defaultProfiles {
    return @{
        @"profiles": @{
            @"(Default)": @{
                @"name": @"(Default)",
                @"lastVersionId": @"latest-release"
            }
        },
        @"selectedProfile": @"(Default)"
    }.mutableCopy;
}

+ (PLProfiles *)current {
    // ★ Task274-h S3：单例创建/整体替换本身收进类锁——两线程同见 nil 会双建实例
    // （后建者胜，先建实例上未落盘的写全部丢失）。updateCurrent 供会话中重载
    // （AI 安装流等），原子性同样由类锁保证。锁序：类锁 → 实例锁（init 内 save），
    // 实例方法从不回调 +current/+updateCurrent，无环。
    @synchronized (self) {
        if (!current) {
            [self updateCurrent];
        }
        return current;
    }
}

+ (void)updateCurrent {
    @synchronized (self) {
        current = [[PLProfiles alloc] initWithCurrentInstance];
    }
}

+ (id)profile:(NSMutableDictionary *)profile resolveKey:(id)key {
    id rawValue = profile[key];
    // 兼容 javaVersion 字段：Mojang 规范是 NSDictionary（{component, majorVersion}），
    // 但部分代码（如 ForgeDirectInstaller）也写入 NSDictionary。PLProfiles 期望返回 NSString。
    if ([rawValue isKindOfClass:[NSDictionary class]]) {
        // javaVersion: 返回 majorVersion 的字符串值；缺失则落入下方 valueDefaults
        id major = rawValue[@"majorVersion"];
        if (major) return [major description];
        // 落入下方 valueDefaults 逻辑，避免返回 nil 破坏调用方
    } else if ([rawValue isKindOfClass:[NSString class]] && [(NSString *)rawValue length] > 0) {
        return rawValue;
    }

    NSDictionary *valueDefaults = @{
        @"javaVersion": @"0",
        // LWJGL 版本："auto" = MC 26.x 及以上用 3.4.1，其余用 3.3.3。
        // profile 里显式存 "333"/"341" 时以显式值为准。
        @"lwjglVersion": @"auto",
        @"gameDir": @"."
    };
    if (valueDefaults[key]) {
        return valueDefaults[key];
    }

    NSDictionary *prefDefaults = @{
        @"defaultTouchCtrl": @"control.default_ctrl",
        @"defaultGamepadCtrl": @"control.default_gamepad_ctrl",
        @"javaArgs": @"java.java_args",
        // Task159：分辨率缩放实例化（与上方退役的 renderer 回退同款机制，
        // [可撤销]）——profile 有 resolution 键（NSString）→ 实例显式值；
        // 无键 → 回退全局 video.resolution（存量设备平滑：全局行虽从设置页
        // 移除，存量值仍生效，直到用户在实例里显式设置）。撤销 = 删本行 +
        // 恢复设置页全局行。
        @"resolution": @"video.resolution",
        // Task 150（[可撤销] 删除渲染器全局控制）：renderer 的全局回退键退役
        // ——每个实例强制单独选择渲染器，profile 无 renderer 键时由
        // ame_effective_renderer 落到 "auto"（用户确认的缺省），不再读取
        // 全局 video.renderer（该键随设置页渲染器行一并退役，仅存量设备
        // 偏好文件中残留、无读取方）。撤销 = 恢复本行映射 + 设置页行。
        // @"renderer": @"video.renderer",
        // MC 26.2+ Graphics API（OpenGL/Vulkan 游戏内切换），缺省为 "default"
        // 该字段仅在 MC 26.2+ 生效，旧版本会被 MC 忽略，无副作用。
        @"graphicsApi": @"video.graphics_api"
    };
    // Task 150：nil 守卫——映射里没有的键（如退役后的 renderer）直接返回
    // nil（getPrefObject(nil) 会抛 NSInvalidArgumentException）
    id prefKey = prefDefaults[key];
    return prefKey ? getPrefObject(prefKey) : nil;
}

+ (id)resolveKeyForCurrentProfile:(id)key {
    return [self profile:self.current.selectedProfile resolveKey:key];
}

- (id)initWithCurrentInstance {
    self = [super init];
    self.profilePath = [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:@"launcher_profiles.json"];
    self.profileDict = parseJSONFromFile(self.profilePath);
    if (self.profileDict[@"NSErrorObject"]) {
        // ★ Task353：注册表读失守不立即出厂重置——先回读进程内最后已知完好
        //   锚（零写入）。病历面：启动期版本根对齐（ZL2Home [Ame353]）把
        //   POJAV_GAME_DIR 指到 profile 自洽实例根后，任何
        //   reloadProfileList→updateCurrent 都会按新根读
        //   instances/<x>/launcher_profiles.json——版本轴实例（Ame329 统一）
        //   无自带注册表，旧代码当场 defaultProfiles+[self save] 把出厂注册
        //   表误写进实例根且 selectedProfile 丢失 = 启动半途“请先选择实例”。
        //   收窄面仅“当前注册表读不到”一种：有锚续用（实例根绝不被误写），
        //   无锚（冷启动真首次）维持出厂默认原语义。
        if (_ame353_registryLastGoodPath.length > 0
            && ![_ame353_registryLastGoodPath isEqualToString:self.profilePath]) {
            NSMutableDictionary *ame353_rescued = parseJSONFromFile(_ame353_registryLastGoodPath);
            if ([ame353_rescued isKindOfClass:[NSDictionary class]]
                && !ame353_rescued[@"NSErrorObject"]) {
                self.profileDict = ame353_rescued;
                NSLog(@"[Ame353] registry fallback: %@ unreadable -> last-known-good %@ (no write)",
                      self.profilePath, _ame353_registryLastGoodPath);
                return self;
            }
        }
        self.profileDict = PLProfiles.defaultProfiles;
        [self save];
    } else {
        // 读成功才记锚（失守回读的“最后已知完好”语义）
        _ame353_registryLastGoodPath = [self.profilePath copy];
    }

    return self;
}

- (id)profiles {
    // ★ Task274-h S3：惰性可变换 + 读全部收进实例锁（写方 saveProfile/save 同锁，
    // 消除跨线程 NSMutableDictionary 结构竞态）。返回的仍是活字典（外部直接
    // 变更方依赖该语义，本轮不改变）。
    @synchronized (self) {
        id profiles = self.profileDict[@"profiles"];
        if (![profiles isKindOfClass:[NSDictionary class]]) {
            profiles = [NSMutableDictionary dictionary];
            self.profileDict[@"profiles"] = profiles;
        } else if (![profiles isKindOfClass:[NSMutableDictionary class]]) {
            profiles = [profiles mutableCopy];
            self.profileDict[@"profiles"] = profiles;
        }
        return profiles;
    }
}

- (id)selectedProfile {
    return self.profiles[self.selectedProfileName];
}

- (NSString *)selectedProfileName {
    @synchronized (self) {
        return (id)self.profileDict[@"selectedProfile"];
    }
}

- (void)setSelectedProfileName:(NSString *)name {
    // ★ Task274-h S3：字典写 + save 收进实例锁；SelectedProfileChanged 通知必须发在
    //   锁外——观察者可能同步重入 PLProfiles，锁内发通知构成重入/他线程等待死锁面。
    @synchronized (self) {
        self.profileDict[@"selectedProfile"] = (id)name;
        [self save];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:name];
}

/// 递归清理 NSDate 等非法 JSON 类型，确保保存不崩溃
- (id)jsonSanitizedObject:(id)obj {
    if ([obj isKindOfClass:[NSDate class]]) {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        });
        return [formatter stringFromDate:obj];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *clean = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
        [obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            // ★ Task274-h S9：非字符串键统一走清洗（NSDate→ISO 串、NSURL→absoluteString、
            //   其余→description）——JSON 对象键必须为字符串，此前仅 NSDate 键被处理。
            id safeKey = [key isKindOfClass:[NSString class]] ? key : [self jsonSanitizedObject:key];
            clean[safeKey] = [self jsonSanitizedObject:val];
        }];
        return clean;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *clean = [NSMutableArray arrayWithCapacity:[obj count]];
        for (id item in obj) {
            [clean addObject:[self jsonSanitizedObject:item]];
        }
        return clean;
    } else if ([obj isKindOfClass:[NSURL class]]) {
        // ★ Task274-h S9：NSURL 安全化（JSON 非法类型，整树枚举时一并转字符串）
        return [obj absoluteString] ?: @"";
    }
    // ★ Task274-h S9：兜底——未知类型（NSSet/NSValue/NSNull 等）转 NSString 描述，
    //   绝不抛异常；此前直透传 → isValidJSONObject 失败 → 整次保存被静默丢弃。
    return [obj description] ?: @"";
}

- (void)save {
    // ★ Task274-h S3：全树遍历（jsonSanitizedObject 递归枚举）+ 落盘整体在实例锁内，
    //   防并发变更打断枚举（枚举中字典被改 = 崩溃面）。
    @synchronized (self) {
        id sanitized = [self jsonSanitizedObject:self.profileDict];
        if ([NSJSONSerialization isValidJSONObject:sanitized]) {
            saveJSONToFile(sanitized, self.profilePath);
        } else {
            // ★ Task274-h S9：失败路径可见日志（带上下文+键数量）——此前仅一句
            //   固定文案，isValidJSONObject 不过时整次保存被静默丢弃无从排查。
            NSDictionary *ame274_profiles = ([self.profileDict isKindOfClass:[NSDictionary class]]
                ? self.profileDict[@"profiles"] : nil);
            NSLog(@"[PLProfiles] SAVE FAILED: profileDict still contains invalid JSON types after sanitization"
                  @" (topLevelKeys=%@, profileCount=%ld, selectedProfile=%@, path=%@)",
                  ([self.profileDict isKindOfClass:[NSDictionary class]] ? [self.profileDict allKeys] : nil),
                  (long)([ame274_profiles isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)ame274_profiles count] : -1),
                  self.profileDict[@"selectedProfile"],
                  self.profilePath);
        }
    }
}

- (void)saveProfile:(NSMutableDictionary<NSString *, NSString *> *)profile withName:(NSString *)name {
    // ★ Task274-h S3：读-合并-写全程在实例锁内（save 为同锁可重入）——后台安装器
    //   并发 saveProfile 与主线程读之间此前零锁。
    @synchronized (self) {
    if (!self.profileDict[@"profiles"]) {
        self.profileDict[@"profiles"] = [NSMutableDictionary dictionary];
    }
    // ★ Task271（271-a RC1 根修·自适应恢复）：saveProfile 从【整条替换】改为
    //   【合并覆盖】。旧语义 = 新字典整体顶掉旧条目——同名重装/更新（下载页
    //   Fabric/Quilt、下载页/实例页 OptiFine、AI 安装流等只写部分字段的写入方）
    //   会把既有条目的 gameDir（版本隔离）/icon/javaArgs/renderer/graphicsApi/
    //   jvm_preset/touchController/allocatedMemory/memoryAuto/resolution/serverIp
    //   等全部静默抹掉：用户视角"实例的模组列表变成了共享目录"。合并语义：
    //   既有键保留、新键覆盖同名键——安装器想写的字段照写，其余实例设置原样
    //   存活；全新条目（无同名旧档）行为与旧版一致。
    NSMutableDictionary *ame271_merged =
        [self.profileDict[@"profiles"][name] isKindOfClass:[NSDictionary class]]
            ? [NSMutableDictionary dictionaryWithDictionary:self.profileDict[@"profiles"][name]]
            : [NSMutableDictionary dictionary];
    for (NSString *ame271_key in profile) {
        id ame271_val = profile[ame271_key];
        if (ame271_val == nil) continue;
        ame271_merged[ame271_key] = ame271_val;
    }
    self.profileDict[@"profiles"][name] = ame271_merged;
    [self save];
    }
}

// ★ Task275 F6：锁内批量变更 API（声明见 .h）。
- (void)applyChanges:(void (NS_NOESCAPE ^)(NSMutableDictionary<NSString *, id> *profiles))changes {
    if (!changes) return;
    @synchronized (self) {
        id profiles = self.profileDict[@"profiles"];
        if (![profiles isKindOfClass:[NSMutableDictionary class]]) {
            profiles = [NSMutableDictionary dictionary];
            self.profileDict[@"profiles"] = profiles;
        }
        changes(profiles);
        [self save];   // 同锁可重入（saveProfile 先例）
    }
}

#pragma mark - ★ Task349 孤儿实例目录收编（zip 导入旧包实例列表可见性根修）

// 病历（装机 0ad0735 IMG_0522 + latestlog 第八轮）：Task217 导入 11474 files
// (ok) + Task230 摘要"已恢复 3 个实例"，主页实例网格却只有 "(Default)" 一张卡
// ——实例列表按注册表（launcher_profiles.json）枚举（Task302 判例），恢复进
// instances/ 的目录若无对应条目 = 永久隐身。旧版备份（≤345 无脉柱形态）常见
// 注册表缺席/落位错层（一代全局位 POJAV_HOME 根 vs 现役 POJAV_GAME_DIR 位），
// 导入后注册表被防毒化保留现役（或回退出厂默认），恢复的实例目录全部成为孤儿。
// 修法：扫描收编（导入收尾 + 启动期双挂点，幂等只增）+ 一代全局注册表在
// 现役注册表尚为出厂默认单条时合并导入（改名归档防复燃）。
+ (NSUInteger)ame349_reconcileOrphanInstancesLogTag:(NSString *)tag {
    const char *ame349_home = getenv("POJAV_HOME");
    if (!ame349_home) return 0;
    NSString *ame349_homeStr = [NSString stringWithUTF8String:ame349_home];
    if (ame349_homeStr.length == 0) return 0;

    NSFileManager *ame349_fm = NSFileManager.defaultManager;
    NSString *ame349_instancesDir = [ame349_homeStr stringByAppendingPathComponent:@"instances"];
    NSArray<NSString *> *ame349_entries =
        [ame349_fm contentsOfDirectoryAtPath:ame349_instancesDir error:nil] ?: @[];

    PLProfiles *ame349_mgr = [PLProfiles current];
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *ame349_snapshot =
        [NSDictionary dictionaryWithDictionary:ame349_mgr.profiles];

    // 当前游戏目录（目录名↔注册表键不同名判例：instances/default vs "(Default)"，
    // profile 无 gameDir 键即解析为当前实例——按目录名匹配会误登记现役实例）
    NSString *ame349_currentGameDir =
        getPrefObject(@"general.game_directory") ?: @"default";
    if (![ame349_currentGameDir isKindOfClass:[NSString class]] ||
        ame349_currentGameDir.length == 0) {
        ame349_currentGameDir = @"default";
    }

    // 现役注册表是否尚为"出厂默认单条"（一代全局注册表合并的闸门；用户已
    // 自建/下载过实例则现役注册表为权威，不做合并防复燃）
    BOOL ame349_defaultOnly = NO;
    if (ame349_snapshot.count == 1) {
        NSDictionary *ame349_d = ame349_snapshot[@"(Default)"];
        ame349_defaultOnly = [ame349_d isKindOfClass:[NSDictionary class]] &&
            [ame349_d[@"lastVersionId"] isKindOfClass:[NSString class]] &&
            [ame349_d[@"lastVersionId"] isEqualToString:@"latest-release"];
    }

    // ---- 扫描：真实目录（符号链接/隐藏隔离/.ame344-corrupt-* 一律跳过）----
    NSMutableArray<NSString *> *ame349_orphans = [NSMutableArray array];
    for (NSString *ame349_name in [ame349_entries sortedArrayUsingSelector:@selector(compare:)]) {
        if (ame349_name.length == 0 || [ame349_name hasPrefix:@"."]) continue;
        NSString *ame349_path = [ame349_instancesDir stringByAppendingPathComponent:ame349_name];
        NSDictionary *ame349_attrs = [ame349_fm attributesOfItemAtPath:ame349_path error:nil];
        // attributesOfItemAtPath 不跟随链接：仅真实目录入围（shared_core 级
        // 符号链接与断链天然排除；nil 属性 / 非目录均经 continue 跳过）
        if (![ame349_attrs[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
        // 空目录跳过（setupMultiDir 预建壳/用户未初始化的游戏目录不产生废卡）
        NSArray *ame349_inner = [ame349_fm contentsOfDirectoryAtPath:ame349_path error:nil];
        if (ame349_inner.count == 0) continue;
        BOOL ame349_known = [ame349_name isEqualToString:ame349_currentGameDir];
        if (!ame349_known) {
            for (NSString *ame349_key in ame349_snapshot) {
                if ([ame349_key isEqualToString:ame349_name]) { ame349_known = YES; break; }
                NSString *ame349_gd = ame349_snapshot[ame349_key][@"gameDir"];
                if ([ame349_gd isKindOfClass:[NSString class]] &&
                    [ame349_gd isEqualToString:ame349_path]) { ame349_known = YES; break; }
            }
        }
        if (!ame349_known) [ame349_orphans addObject:ame349_name];
    }

    // ---- 登记孤儿（lastVersionId 尽力从实例自带 launcher_profiles.json 回读）----
    NSMutableArray<NSDictionary *> *ame349_newProfiles = [NSMutableArray array];
    for (NSString *ame349_name in ame349_orphans) {
        NSMutableDictionary *ame349_p = [NSMutableDictionary dictionary];
        ame349_p[@"name"] = ame349_name;
        NSString *ame349_path = [ame349_instancesDir stringByAppendingPathComponent:ame349_name];
        NSDictionary *ame349_own = parseJSONFromFile(
            [ame349_path stringByAppendingPathComponent:@"launcher_profiles.json"]);
        if ([ame349_own isKindOfClass:[NSDictionary class]] &&
            ame349_own[@"NSErrorObject"] == nil) {
            NSDictionary *ame349_ownProfiles = ame349_own[@"profiles"];
            if ([ame349_ownProfiles isKindOfClass:[NSDictionary class]]) {
                id ame349_sel = ame349_own[@"selectedProfile"];
                NSDictionary *ame349_pick = ([ame349_sel isKindOfClass:[NSString class]])
                    ? ame349_ownProfiles[ame349_sel] : nil;
                if (![ame349_pick isKindOfClass:[NSDictionary class]]) {
                    for (NSDictionary *ame349_cand in ame349_ownProfiles.allValues) {
                        if ([ame349_cand isKindOfClass:[NSDictionary class]]) { ame349_pick = ame349_cand; break; }
                    }
                }
                id ame349_lv = [ame349_pick isKindOfClass:[NSDictionary class]]
                    ? ame349_pick[@"lastVersionId"] : nil;
                if ([ame349_lv isKindOfClass:[NSString class]] &&
                    ((NSString *)ame349_lv).length > 0) {
                    ame349_p[@"lastVersionId"] = ame349_lv;
                }
            }
        }
        // ★ Task351：版本推断级联——旧版备份实例目录普遍无自带
        //   launcher_profiles.json（装机 latestlog 实锤：两 modrinth 实例
        //   ParseJSON 三连 miss，收编后 lastVersionId 空缺 → 主页/版本页
        //   全卡"该版本无效"红字 = "导入的数据不完整"观感主源）。回读失败
        //   后按证据硬度级联：② 实例 versions/ 本地实体（<vid>/<vid>.json
        //   真实文件，多候选取版本 JSON mtime 最新——整合包实例常见
        //   vanilla+loader 双实体，loader JSON 通常最后写入）→ ③
        //   modrinth.index.json dependencies.minecraft（Modrinth 整合包
        //   MC 版本，vanilla 版本 id 即 MC 号，启动链可在线解析安装）→
        //   ④ instance.json（其他启动器同族实例元数据 lastVersionId/
        //   gameVersion）。来源留痕 [Ame351] 日志供装机判读。
        // ★ Task352：级联收编为公共方法 ame352_inferVersionForDir:homeRoot:fm:
        //   （孤儿收编与存量空版本修复遍共用；1.0 旧布局根位 versions/ 兜底一并纳入）
        if (![ame349_p[@"lastVersionId"] isKindOfClass:[NSString class]]) {
            NSDictionary *ame352_hit = [self ame352_inferVersionForDir:ame349_path
                                                              homeRoot:ame349_homeStr
                                                                    fm:ame349_fm];
            if (ame352_hit) {
                ame349_p[@"lastVersionId"] = ame352_hit[@"vid"];
                NSLog(@"[Ame351] reconcile: version inferred for %@ -> %@ (source=%@)",
                      ame349_name, ame352_hit[@"vid"], ame352_hit[@"src"]);
            }
        }
        // gameDir 绝对路径锚定（Task316 扁平化判例）；type/created 与 Task302
        // 预登记同族。
        ame349_p[@"gameDir"] = ame349_path;
        ame349_p[@"type"] = @"custom";
        ame349_p[@"created"] = [NSDate date].description;
        [ame349_newProfiles addObject:ame349_p];
    }

    // ---- 一代全局注册表合并（仅出厂默认单条现役时）----
    NSUInteger ame349_legacyMerged = 0;
    NSString *ame349_legacyPath = [ame349_homeStr stringByAppendingPathComponent:@"launcher_profiles.json"];
    NSString *ame349_legacyArchive = nil;
    if (ame349_defaultOnly) {
        NSDictionary *ame349_legacy = parseJSONFromFile(ame349_legacyPath);
        NSDictionary *ame349_legacyProfiles =
            [ame349_legacy isKindOfClass:[NSDictionary class]] ? ame349_legacy[@"profiles"] : nil;
        if ([ame349_legacyProfiles isKindOfClass:[NSDictionary class]] &&
            ame349_legacyProfiles.count > 0 && ame349_legacy[@"NSErrorObject"] == nil) {
            __block NSUInteger ame349_count = 0;
            [ame349_mgr applyChanges:^(NSMutableDictionary<NSString *, id> *profiles) {
                for (NSString *ame349_k in ame349_legacyProfiles) {
                    if (profiles[ame349_k] != nil) continue;
                    NSDictionary *ame349_p = ame349_legacyProfiles[ame349_k];
                    if (![ame349_p isKindOfClass:[NSDictionary class]]) continue;
                    NSMutableDictionary *ame349_copy = [ame349_p mutableCopy];
                    ame349_copy[@"name"] = ame349_k;
                    profiles[ame349_k] = ame349_copy;
                    ame349_count++;
                }
            }];
            ame349_legacyMerged = ame349_count;
            if (ame349_legacyMerged > 0) {
                // 改名归档防复燃（用户此后删除实例不被下次启动复活；数据保留）
                ame349_legacyArchive = [ame349_legacyPath stringByAppendingString:@".ame349-imported"];
                [ame349_fm moveItemAtPath:ame349_legacyPath toPath:ame349_legacyArchive error:nil];
            }
        }
    }

    if (ame349_newProfiles.count > 0) {
        [ame349_mgr applyChanges:^(NSMutableDictionary<NSString *, id> *profiles) {
            for (NSDictionary *ame349_p in ame349_newProfiles) {
                profiles[ame349_p[@"name"]] = [ame349_p mutableCopy];
            }
        }];
    }

    // ---- ★ Task352 存量空版本修复遍（孤儿闸缺口根修）----
    // 病历（装机 286eb30 第十轮 latestlog）：Task351 推断级联只挂在孤儿收编
    // 循环内——导入期 Task227 post-import merge 先登记实例 → reconcile 时
    // orphans=0 → 级联从未执行（装机日志 [Ame351] infer 零行实锤）→ 收编实例
    // lastVersionId 永久空缺 → 主页启动弹"无法获取版本信息"。修法：对注册表
    // 内所有 lastVersionId 空缺的 profile（含现役实例）重跑同一级联：实例
    // gameDir 优先、instances/<键名> 兜底目录定位，根位 versions/ 最后兜底；
    // 命中即回填 + [Ame352] 逐例留痕。幂等：非空即权威跳过，重复 reconcile 不复写。
    __block NSUInteger ame352_repaired = 0;
    __block NSMutableArray<NSString *> *ame352_repairedNames = [NSMutableArray array];
    [ame349_mgr applyChanges:^(NSMutableDictionary<NSString *, id> *profiles) {
        for (NSString *ame352_key in profiles.allKeys) {
            NSDictionary *ame352_p = profiles[ame352_key];
            if (![ame352_p isKindOfClass:[NSDictionary class]]) continue;
            id ame352_lv = ame352_p[@"lastVersionId"];
            if ([ame352_lv isKindOfClass:[NSString class]] &&
                ((NSString *)ame352_lv).length > 0) continue; // 非空即权威，不动
            NSString *ame352_dir = nil;
            id ame352_gd = ame352_p[@"gameDir"];
            if ([ame352_gd isKindOfClass:[NSString class]] &&
                ((NSString *)ame352_gd).length > 0) {
                BOOL ame352_isDir = NO;
                if ([ame349_fm fileExistsAtPath:ame352_gd isDirectory:&ame352_isDir] &&
                    ame352_isDir) ame352_dir = ame352_gd;
            }
            if (!ame352_dir) {
                NSString *ame352_byName = [ame349_instancesDir
                    stringByAppendingPathComponent:ame352_key];
                BOOL ame352_isDir2 = NO;
                if ([ame349_fm fileExistsAtPath:ame352_byName isDirectory:&ame352_isDir2] &&
                    ame352_isDir2) ame352_dir = ame352_byName;
            }
            if (!ame352_dir) continue;
            NSDictionary *ame352_hit = [PLProfiles ame352_inferVersionForDir:ame352_dir
                                                                    homeRoot:ame349_homeStr
                                                                          fm:ame349_fm];
            if (!ame352_hit) continue;
            NSMutableDictionary *ame352_upd = [ame352_p mutableCopy];
            ame352_upd[@"lastVersionId"] = ame352_hit[@"vid"];
            profiles[ame352_key] = ame352_upd;
            ame352_repaired++;
            [ame352_repairedNames addObject:ame352_key];
            NSLog(@"[Ame352] reconcile(%@): version repaired for %@ -> %@ (source=%@)",
                  tag ?: @"?", ame352_key, ame352_hit[@"vid"], ame352_hit[@"src"]);
        }
    }];

    NSUInteger ame349_registered = ame349_newProfiles.count + ame349_legacyMerged;
    NSLog(@"[Ame349] reconcile(%@): scanned=%lu registered=%lu (orphans=%lu legacyMerged=%lu names=%@)",
          tag ?: @"?",
          (unsigned long)ame349_entries.count,
          (unsigned long)ame349_registered,
          (unsigned long)ame349_orphans.count,
          (unsigned long)ame349_legacyMerged,
          [ame349_newProfiles valueForKey:@"name"]);

    NSLog(@"[Ame352] reconcile(%@): empty-version repair pass done (repaired=%lu%@)",
          tag ?: @"?", (unsigned long)ame352_repaired,
          ame352_repairedNames.count > 0
              ? [NSString stringWithFormat:@": %@", [ame352_repairedNames componentsJoinedByString:@", "]]
              : @"");
    if (ame349_registered > 0 || ame352_repaired > 0) {
        // 导入线程/启动期双挂点统一主队列投递（AmePluginRuntime 消费方刷新）
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        });
    }
    return ame349_registered;
}

#pragma mark - ★ Task352 版本推断级联公共体（孤儿收编 + 存量修复遍共用）

// 按证据硬度级联推断实例的 lastVersionId（不落盘，只出证据）：
// ① <dir>/versions/<vid>/<vid>.json 真实实体（多候选取版本 JSON mtime 最新
//    ——整合包实例常见 vanilla+loader 双实体，loader JSON 通常最后写入）；
// ② <dir>/modrinth.index.json dependencies.minecraft（Modrinth 整合包 MC
//    版本，vanilla 版本 id 即 MC 号，启动链可在线解析安装）；
// ③ <dir>/instance.json lastVersionId/gameVersion（其他启动器同族实例元数据）；
// ④ <homeRoot>/versions/ 根位实体（1.0 旧布局：版本集全局存放，实例目录
//    无任何版本证据时的最后兜底，source=versions/(legacy-root) 显式留痕）。
// 命中返回 @{@"vid": id, @"src": 来源}；全空返回 nil（调用方保持空缺如实呈现）。
+ (NSDictionary *)ame352_inferVersionForDir:(NSString *)dir
                                   homeRoot:(NSString *)homeRoot
                                         fm:(NSFileManager *)fm {
    if (dir.length == 0 || !fm) return nil;
    NSString *ame352_vid = nil;
    NSString *ame352_src = nil;
    NSDate *ame352_best = nil;
    NSString *ame352_versionsDir = [dir stringByAppendingPathComponent:@"versions"];
    for (NSString *ame352_v in [fm contentsOfDirectoryAtPath:ame352_versionsDir error:nil] ?: @[]) {
        if (ame352_v.length == 0 || [ame352_v hasPrefix:@"."]) continue;
        NSString *ame352_json = [[ame352_versionsDir
            stringByAppendingPathComponent:ame352_v]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame352_v]];
        if (![fm fileExistsAtPath:ame352_json]) continue;
        NSDate *ame352_mtime = [fm attributesOfItemAtPath:ame352_json error:nil][NSFileModificationDate];
        if (!ame352_best || [ame352_mtime compare:ame352_best] == NSOrderedDescending) {
            ame352_best = ame352_mtime;
            ame352_vid = ame352_v;
            ame352_src = @"versions/";
        }
    }
    if (!ame352_vid) {
        NSDictionary *ame352_mindex = parseJSONFromFile(
            [dir stringByAppendingPathComponent:@"modrinth.index.json"]);
        id ame352_deps = ([ame352_mindex isKindOfClass:[NSDictionary class]]
            ? ame352_mindex[@"dependencies"] : nil);
        id ame352_mc = ([ame352_deps isKindOfClass:[NSDictionary class]]
            ? ame352_deps[@"minecraft"] : nil);
        if ([ame352_mc isKindOfClass:[NSString class]] &&
            ((NSString *)ame352_mc).length > 0) {
            ame352_vid = ame352_mc;
            ame352_src = @"modrinth.index.json";
        }
    }
    if (!ame352_vid) {
        NSDictionary *ame352_meta = parseJSONFromFile(
            [dir stringByAppendingPathComponent:@"instance.json"]);
        if ([ame352_meta isKindOfClass:[NSDictionary class]]) {
            id ame352_lv = ame352_meta[@"lastVersionId"] ?: ame352_meta[@"gameVersion"];
            if ([ame352_lv isKindOfClass:[NSString class]] &&
                ((NSString *)ame352_lv).length > 0) {
                ame352_vid = ame352_lv;
                ame352_src = @"instance.json";
            }
        }
    }
    if (!ame352_vid && homeRoot.length > 0) {
        NSString *ame352_rootVersions = [homeRoot stringByAppendingPathComponent:@"versions"];
        NSDate *ame352_rootBest = nil;
        for (NSString *ame352_v in [fm contentsOfDirectoryAtPath:ame352_rootVersions error:nil] ?: @[]) {
            if (ame352_v.length == 0 || [ame352_v hasPrefix:@"."]) continue;
            NSString *ame352_json = [[ame352_rootVersions
                stringByAppendingPathComponent:ame352_v]
                stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame352_v]];
            if (![fm fileExistsAtPath:ame352_json]) continue;
            NSDate *ame352_mtime = [fm attributesOfItemAtPath:ame352_json error:nil][NSFileModificationDate];
            if (!ame352_rootBest || [ame352_mtime compare:ame352_rootBest] == NSOrderedDescending) {
                ame352_rootBest = ame352_mtime;
                ame352_vid = ame352_v;
                ame352_src = @"versions/(legacy-root)";
            }
        }
    }
    if (!ame352_vid) return nil;
    return @{@"vid": ame352_vid, @"src": ame352_src};
}

#pragma mark - ★ Task353 启动期版本根对齐（“该版本无效/找不到版本信息”终局线）

// 病历（装机 29f8b67 latestlog 实锤）：[Ame352] 修复遍把两个 modrinth profile
// 的 lastVersionId 修复为 fabric-loader-<ver>-<mc>-<hash>（source=versions/，
// 实体真实存在），但点启动必弹 i18n_str_432（[ZL2VersionIndex] unresolved
// loaded=1 localScan=0 disk=0）。根因 = 启动链三级口径全部以全局
// POJAV_GAME_DIR（=偏好当前实例，出厂 default）为根：①ZL2VersionIndex ②③
// 本地扫描；②MRDT versions/<id> 落位与 launchcheck 校验；③Java
// Tools.DIR_HOME_VERSION = POJAV_GAME_DIR/versions。而版本轴实例
// （Ame329 统一后 gameDir = instances/<x>/versions/<vid>）的版本实体在
// profile 自洽根——判定侧 Task351 已吃 profile gameDir（卡片“有效”），
// 启动侧没吃 = 判定/启动两张皮。修法 = 本方法求出版本根 R（
// R/versions/<vid>/<vid>.json 真实存在），调用方（ZL2Home launchGame）在发
// FindVersionInRemoteList 前把 POJAV_GAME_DIR 对齐到 R：索引/MRDT/Java 三段
// 同根自洽，MRDT 校验链（缺啥补啥）顺势把 libraries/assets 补进 profile
// 自根 = 版本隔离安装语义闭环。
// 探测顺序 = gameDir 展开点的祖先链（近→远，实例局部优先于根位；版本轴深
// 层形态第三级命中），锚点兜底 POJAV_GAME_DIR（自定义 gameDir 而版本装在
// 当前实例的形态）。纯读零副作用；latest-* 别名/未装/找不到实体返回 nil
// （别名走在线解析下载流，绝不指根）。
+ (NSString *)ame353_versionRootForProfileName:(NSString *)profileName {
    if (profileName.length == 0) return nil;
    NSDictionary *ame353_p = self.current.profiles[profileName];
    if (![ame353_p isKindOfClass:[NSDictionary class]]) return nil;
    NSString *ame353_vid = ame353_p[@"lastVersionId"];
    if (![ame353_vid isKindOfClass:[NSString class]] || ame353_vid.length == 0) return nil;
    if ([ame353_vid hasPrefix:@"latest-"]) return nil;

    NSString *ame353_home = @(getenv("POJAV_HOME") ?: "");
    if (ame353_home.length == 0) return nil;

    // gameDir 展开（Task275 ame275 同口径：绝对原样；相对按
    // instances/<偏好目录>/ 拼接；缺失 = 当前实例根）
    NSString *ame353_start = nil;
    NSString *ame353_gd = ame353_p[@"gameDir"];
    if ([ame353_gd isKindOfClass:[NSString class]] && ame353_gd.length > 0) {
        if ([ame353_gd isAbsolutePath]) {
            ame353_start = ame353_gd;
        } else {
            NSString *ame353_pref = getPrefObject(@"general.game_directory");
            if (!ame353_pref.length) ame353_pref = @"default";
            ame353_start = [NSString stringWithFormat:@"%@/instances/%@/%@",
                ame353_home, ame353_pref, ame353_gd];
        }
    } else {
        ame353_start = @(getenv("POJAV_GAME_DIR") ?: "");
    }
    ame353_start = ame353_start.stringByStandardizingPath;
    if (ame353_start.length == 0) return nil;

    NSFileManager *ame353_fm = [NSFileManager defaultManager];
    NSString *(^ame353_jsonFor)(NSString *) = ^(NSString *root) {
        return [[[root stringByAppendingPathComponent:@"versions"]
            stringByAppendingPathComponent:ame353_vid]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame353_vid]];
    };
    // 祖先链探测（最多 6 级，到 POJAV_HOME 必停）
    NSString *ame353_cur = ame353_start;
    for (int ame353_depth = 0; ame353_depth < 6; ++ame353_depth) {
        BOOL ame353_isDir = NO;
        if ([ame353_fm fileExistsAtPath:ame353_jsonFor(ame353_cur) isDirectory:&ame353_isDir]
            && !ame353_isDir) {
            return ame353_cur;
        }
        if ([ame353_cur isEqualToString:ame353_home]) break;
        NSString *ame353_parent = [ame353_cur stringByDeletingLastPathComponent];
        if (ame353_parent.length == 0 || [ame353_parent isEqualToString:ame353_cur]) break;
        ame353_cur = ame353_parent;
    }
    // 锚点兜底：版本装在当前实例而 profile gameDir 在别处的形态
    NSString *ame353_envRoot = @(getenv("POJAV_GAME_DIR") ?: "");
    if (ame353_envRoot.length > 0) {
        BOOL ame353_isDir = NO;
        if ([ame353_fm fileExistsAtPath:ame353_jsonFor(ame353_envRoot) isDirectory:&ame353_isDir]
            && !ame353_isDir) {
            return ame353_envRoot;
        }
    }
    return nil;
}

#pragma mark - ★Task428→Task472：版本级隔离解析退役（共享根统一语义）

// Task472：原【隔离解析决策树全文】（A 层实例级 / B 层版本级+全局默认）
// 随四层机制一并退役。gameDir 统一 = 共享根（GAME_DIR 优先 HOME 兜底），
// ame428 命名仅保留中性路径 helper（scanRoot/versionDirForVid/注册表/清单解析）。

/// 版本级操作的共享根（= 扫描器/启动链同口径：GAME_DIR 优先 HOME 兜底）。
+ (NSString *)ame428_scanRoot {
    const char *ame428_gd = getenv("POJAV_GAME_DIR");
    if (ame428_gd && *ame428_gd) return [NSString stringWithUTF8String:ame428_gd];
    const char *ame428_h = getenv("POJAV_HOME");
    if (ame428_h && *ame428_h) return [NSString stringWithUTF8String:ame428_h];
    return @"";
}

/// versions/<vid>/ 实体目录（隔离态下的游戏数据根，与版本 jar/json 同层——
/// FCL/HMCL/PCL 混居通例，Task322 已定口径）。
+ (NSString *)ame428_versionDirForVid:(NSString *)vid {
    if (vid.length == 0) return nil;
    NSString *ame428_root = [self ame428_scanRoot];
    if (ame428_root.length == 0) return nil;
    return [[ame428_root stringByAppendingPathComponent:@"versions"]
        stringByAppendingPathComponent:vid];
}

/// 注册表里引用该 vid 的 profile 键集合。
+ (NSArray<NSString *> *)ame428_profileNamesReferencingVid:(NSString *)vid {
    if (vid.length == 0) return @[];
    NSMutableArray<NSString *> *ame428_out = [NSMutableArray array];
    NSDictionary *ame428_profiles = [PLProfiles current].profiles;
    for (NSString *ame428_key in ame428_profiles.allKeys) {
        NSDictionary *ame428_p = ame428_profiles[ame428_key];
        if (![ame428_p isKindOfClass:[NSDictionary class]]) continue;
        if ([ame428_p[@"lastVersionId"] isKindOfClass:[NSString class]] &&
            [ame428_p[@"lastVersionId"] isEqualToString:vid]) {
            [ame428_out addObject:ame428_key];
        }
    }
    return ame428_out;
}

/// 注册补登记（engage 时调用；1.3 第 2 条闭环点）：该 vid 无任何注册表
/// 条目时按 ame338 恢复流/整合包安装链同款落位登记（gameDir=versions/<vid>，
/// type=custom）。已有引用则原样返回（幂等只增）。返回可用 profile 键名。
+ (NSString *)ame428_registerProfileForVid:(NSString *)vid {
    if (vid.length == 0) return nil;
    NSArray<NSString *> *ame428_existing = [self ame428_profileNamesReferencingVid:vid];
    if (ame428_existing.count > 0) return ame428_existing.firstObject;
    NSMutableDictionary *ame428_profile = [NSMutableDictionary dictionary];
    ame428_profile[@"name"] = vid;
    ame428_profile[@"lastVersionId"] = vid;
    // ★Task472: 版本隔离退役——注册 profile 不再写 gameDir（恒共享根语义）
    ame428_profile[@"type"] = @"custom";
    ame428_profile[@"created"] = [NSDate date].description;
    [PLProfiles.current saveProfile:ame428_profile withName:vid];
    NSLog(@"[Ame428] registry engage: registered version '%@' (gameDir=versions/%@)", vid, vid);
    return vid;
}

+ (BOOL)ame428_isVersionInstalledPerScan:(NSString *)versionId profile:(NSDictionary *)profile {
    if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) return NO;
    if ([versionId isEqualToString:@"latest-release"] ||
        [versionId isEqualToString:@"latest-snapshot"] ||
        [versionId isEqualToString:@"latest"]) return YES;
    const char *ame428_gd = getenv("POJAV_GAME_DIR");
    const char *ame428_h = getenv("POJAV_HOME");
    NSString *ame428_root = nil;
    if (ame428_gd && *ame428_gd) ame428_root = [NSString stringWithUTF8String:ame428_gd];
    else if (ame428_h && *ame428_h) ame428_root = [NSString stringWithUTF8String:ame428_h];
    if (ame428_root.length == 0) return NO;
    NSString *ame428_pgd = [profile isKindOfClass:[NSDictionary class]] ? profile[@"gameDir"] : nil;
    if ([ame428_pgd isKindOfClass:[NSString class]] && ame428_pgd.length > 0 &&
        ![ame428_pgd isEqualToString:@"."] && ![ame428_pgd isEqualToString:@"./"]) {
        NSString *ame428_json = [NSString stringWithFormat:
            @"%@/versions/%@/%@.json", ame428_pgd, versionId, versionId];
        if ([self ame428_jsonManifestParsesAtPath:ame428_json]) return YES;
    }
    NSString *ame428_json3 = [NSString stringWithFormat:@"%@/versions/%@/%@.json",
        ame428_root, versionId, versionId];
    if ([self ame428_jsonManifestParsesAtPath:ame428_json3]) return YES;
    if (ame428_gd && ame428_h) {
        NSString *ame428_legacy = [NSString stringWithFormat:@"%s/versions/%@/%@.json",
            ame428_h, versionId, versionId];
        if ([self ame428_jsonManifestParsesAtPath:ame428_legacy]) return YES;
    }
    return NO;
}

#pragma mark - 服务器地址（FCL 风格：启动后自动加入服务器）

// 获取当前选中 profile 的服务器地址，留空返回 @""
- (NSString *)serverIpForCurrentProfile {
    return [self serverIpForProfile:self.selectedProfileName];
}

// 获取指定 profile 的服务器地址，缺失或为空均返回 @""
- (NSString *)serverIpForProfile:(NSString *)profileName {
    @synchronized (self) {
        NSString *ip = self.profiles[profileName][@"serverIp"];
        return ip ?: @"";
    }
}

// 设置指定 profile 的服务器地址，nil 转为 @""
- (void)setServerIp:(NSString *)serverIp forProfile:(NSString *)profileName {
    @synchronized (self) {
        NSMutableDictionary *profile = [self.profiles[profileName] mutableCopy];
        if (!profile) {
            profile = [NSMutableDictionary dictionary];
        }
        profile[@"serverIp"] = serverIp ?: @"";
        self.profiles[profileName] = profile;
        [self save];
    }
}

#pragma mark - ★Task450 ③ 隔离数据播种（15 期③「版本隔离文件夹没有文件」根修）

@end
