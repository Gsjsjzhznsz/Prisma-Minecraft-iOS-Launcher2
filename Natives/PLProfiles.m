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

#pragma mark - ★Task428（1.2/1.4/12.2）：版本级隔离解析（单一事实源）+ 数据下沉 + 迁移报告

// ============================================================================
// 章法（报告第一章 1.2 + 1.4 + 第十二章 12.2 落地）：
//   · 版本级隔离的“有效解析”全链只有一个实现 = ame428_effectiveCore……
//     消费方：JavaLauncher 启动链（cwd/gameDir 解析）、ZL2VersionPages 版本
//     详情页隔离行、ZL2SettingPages 全局档行（翻转计算）。
//   · 数据下沉（1.4）与迁移报告（12.2）都在本文件：页面层只做弹窗与提交。
// ============================================================================
//
// 【隔离解析决策树全文】（effectiveIsolationForVersion；返回约定：
//   -1 = 不参与版本级解析（实例自定义路径 / latest 别名 / 空 vid——
//        现有 gameDir 各层语义原样保留，版本级层零触碰）；
//    0 = 共享（不隔离，游戏数据/启动 cwd = 实例根）；
//    1 = 隔离（游戏数据/启动 cwd = versions/<vid>/）。）
//
// A 层【实例级隔离（ame217 三态，既有语义优先——存量用户零回归的锚点）】
//   读 profile[@"gameDir"]（ProfileSettingsViewController ame217_isolationState
//   同口径）：
//   A1. gameDir 缺失 / "." / "./"（state 0，实例隔离未开）：
//       → 进入 B 层（版本级 + 全局默认在此生效——这是全局档的主作用面）。
//         “实例隔离关闭时版本级不生效”的落地方式：本形态下版本级的自动档
//         （MODDED）证据【严格限定在 versions/<vid>/ 目录内部】（mods/ 或
//         config/ 非空；loader 标记仅在该目录已有数据时才成立）——与既有
//         Task225/ModService 嗅探同源。默认档（auto）下：共享根用户的版本
//         目录只有 jar/json → 全部判否 → 行为与现状逐位相同（零回归）；
//         纯 loader id + 空版本目录（如下载页装了 Fabric 从未开隔离）不
//         触发隔离，杜绝“启动后存档消失”式静默翻转。
//   A2. gameDir == "versions/<vid>" 或旧口径 "versions/<vid>/game"（state 1，
//       实例隔离已开）：现有行为 = 隔离；版本级覆盖可再细分：
//         · version.config isolation=2（禁用）→ 0（该版本退回共享根运行）；
//         · 其余（1=启用 / 0=跟随全局→无论 auto/always/never 解出什么）→ 1
//           （与现状逐位等价）。理由：A2 是用户显式选择（ame217 写入带
//           gameDirExplicit 标记，整合包安装链亦显式写键），显式实例选择的
//           优先级高于全局默认——全局 NEVER 不撤销显式实例隔离；只有
//           “每版本显式禁用”这一条能在 A2 内部再细分。
//   A3. gameDir = 其它任意值（state 2，自定义路径）：→ -1（自定义路径是
//       最高阶显式意图，版本级层永不触碰；最高优先级 = 现有行为优先）。
//
// B 层【版本级覆盖 + 全局默认】（仅 A1 全程 / A2 的禁用分支到达这里）
//   B1. versions/<vid>/version.config（plist）isolation 键：
//       1=启用 → 1；2=禁用 → 0；0/缺失/不可读（=跟随全局）→ B2。
//   B2. 全局默认 general.isolation_default（int，PLPreferences 已注册，默认 0）：
//       1=ALWAYS 始终 → 1；2=NEVER 从不 → 0；0=AUTO 自动（MODDED）→
//         versions/<vid>/mods/ 有非隐藏条目 → 1；
//         versions/<vid>/config/ 有非隐藏条目 → 1；
//         版本 id 为 loader 形（ModLoaderIconHelper detectLoaderFromVersionId
//         非空）且 versions/<vid>/ 除 <vid>.json/<vid>.jar 外还有其它条目
//         （数据已实际住进版本目录）→ 1；
//         否则 → 0。
//
// 【存量用户回归面】（详见任务报告）：默认档（auto）下 A1 用户判否（证据
//   限定在版本目录内）、A2 用户判 1（除显式禁用外逐位等价）、A3 用户 -1
//   （零触碰）——三类用户默认行为全部不变；只有用户显式改全局档/版本覆盖
//   才发生状态翻转，翻转处由页面层先问再动（确认框 + 快照 + 原子搬移）。
// ============================================================================

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

/// versions/<vid>/version.config（plist）路径。
+ (NSString *)ame428_versionConfigPathForVid:(NSString *)vid {
    NSString *ame428_dir = [self ame428_versionDirForVid:vid];
    if (!ame428_dir) return nil;
    return [ame428_dir stringByAppendingPathComponent:@"version.config"];
}

/// Prisma2 根（main.m init_setupPCLLayout 同款解析：POJAV_HOME/Prisma2）。
+ (NSString *)ame428_prisma2Root {
    const char *ame428_h = getenv("POJAV_HOME");
    if (!ame428_h || !*ame428_h) return nil;
    return [@([NSString stringWithUTF8String:ame428_h])
        stringByAppendingPathComponent:@"Prisma2"];
}

/// 迁移报告落点：Prisma2/migration_report.txt（12.2：人可读、追加式）。
+ (NSString *)ame428_migrationReportPath {
    NSString *ame428_p2 = [self ame428_prisma2Root];
    if (!ame428_p2) return nil;
    return [ame428_p2 stringByAppendingPathComponent:@"migration_report.txt"];
}

/// 读版本级覆盖（version.config isolation 键）：0=跟随全局（默认/缺失/
/// 不可读一律归 0）；1=启用；2=禁用。越界值钳回 0。
+ (NSInteger)ame428_overrideForVid:(NSString *)vid {
    NSString *ame428_path = [self ame428_versionConfigPathForVid:vid];
    if (ame428_path.length == 0) return 0;
    NSDictionary *ame428_cfg = [NSDictionary dictionaryWithContentsOfFile:ame428_path];
    if (![ame428_cfg isKindOfClass:[NSDictionary class]]) return 0;
    id ame428_raw = ame428_cfg[@"isolation"];
    NSInteger ame428_v = [ame428_raw isKindOfClass:[NSNumber class]] ? [ame428_raw integerValue] : 0;
    if (ame428_v < 0 || ame428_v > 2) ame428_v = 0;
    return ame428_v;
}

/// 写版本级覆盖（读-改-写：既有键保留；NSDictionary writeToFile = plist）。
+ (BOOL)ame428_writeOverride:(NSInteger)override vid:(NSString *)vid {
    NSString *ame428_path = [self ame428_versionConfigPathForVid:vid];
    if (ame428_path.length == 0) return NO;
    NSMutableDictionary *ame428_cfg = [NSMutableDictionary dictionary];
    NSDictionary *ame428_old = [NSDictionary dictionaryWithContentsOfFile:ame428_path];
    if ([ame428_old isKindOfClass:[NSDictionary class]]) {
        [ame428_cfg addEntriesFromDictionary:ame428_old];
    }
    ame428_cfg[@"isolation"] = @(override);
    NSString *ame428_dir = [ame428_path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:ame428_dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [ame428_cfg writeToFile:ame428_path atomically:YES];
}

/// 全局默认档（general.isolation_default；钳 0-2，默认 0=AUTO）。
+ (NSInteger)ame428_globalDefault {
    NSInteger ame428_g = getPrefInt(@"general.isolation_default");
    if (ame428_g < 0 || ame428_g > 2) ame428_g = 0;
    return ame428_g;
}

/// AUTO（MODDED）档证据：严格限定在 versions/<vid>/ 目录内部（决策树 B2）。
+ (BOOL)ame428_autoEvidenceForVid:(NSString *)vid {
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    NSString *ame428_dir = [self ame428_versionDirForVid:vid];
    if (ame428_dir.length == 0) return NO;
    // ① mods/ 或 config/ 有非隐藏条目（与 ame225 嗅探同源的第一判据）
    for (NSString *ame428_leaf in @[@"mods", @"config"]) {
        NSArray *ame428_entries = [ame428_fm contentsOfDirectoryAtPath:
            [ame428_dir stringByAppendingPathComponent:ame428_leaf] error:nil];
        for (NSString *ame428_e in ame428_entries) {
            if (![ame428_e hasPrefix:@"."]) return YES;
        }
    }
    // ② loader 形 id + 版本目录已有 jar/json 之外的实际数据
    if ([ModLoaderIconHelper detectLoaderFromVersionId:vid].length > 0) {
        NSString *ame428_json = [ame428_dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", vid]];
        NSString *ame428_jar = [ame428_dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.jar", vid]];
        for (NSString *ame428_e in [ame428_fm contentsOfDirectoryAtPath:ame428_dir error:nil] ?: @[]) {
            if ([ame428_e hasPrefix:@"."]) continue;
            if ([ame428_e isEqualToString:ame428_json.lastPathComponent]) continue;
            if ([ame428_e isEqualToString:ame428_jar.lastPathComponent]) continue;
            return YES;   // 版本目录里已经住着数据（用户数据或整合包落位）
        }
    }
    return NO;
}

/// 隔离解析核心（决策树 A/B 全文见本节块注释）。forcedOverride /
/// forcedGlobal 供翻转预演：传 0/1/2 按假想值解析，传 -1 读实值
///（version.config / general.isolation_default）。两页面层翻转确认与
/// JavaLauncher 启动链共用本核心——全链单一事实源。
+ (NSInteger)ame428_effectiveCore:(NSString *)vid
                          profile:(NSDictionary *)profile
                    forcedOverride:(NSInteger)forcedOverride
                     forcedGlobal:(NSInteger)forcedGlobal {
    if (![vid isKindOfClass:[NSString class]] || vid.length == 0) return -1;
    if ([vid hasPrefix:@"latest-"] || [vid isEqualToString:@"latest"]) return -1;

    // —— A 层：实例级（ame217 同口径）——
    NSString *ame428_gd = [profile isKindOfClass:[NSDictionary class]]
        ? profile[@"gameDir"] : nil;
    if (![ame428_gd isKindOfClass:[NSString class]]) ame428_gd = nil;
    BOOL ame428_a3 = (ame428_gd.length > 0
        && ![ame428_gd isEqualToString:@"."]
        && ![ame428_gd isEqualToString:@"./"]
        && ![ame428_gd isEqualToString:[NSString stringWithFormat:@"versions/%@", vid]]
        && ![ame428_gd isEqualToString:[NSString stringWithFormat:@"versions/%@/game", vid]]);
    if (ame428_a3) return -1;   // A3：自定义路径——版本级层零触碰

    BOOL ame428_a2 = [ame428_gd isEqualToString:[NSString stringWithFormat:@"versions/%@", vid]]
        || [ame428_gd isEqualToString:[NSString stringWithFormat:@"versions/%@/game", vid]];

    // —— B1：版本级覆盖 ——
    NSInteger ame428_ov = (forcedOverride >= 0 && forcedOverride <= 2)
        ? forcedOverride : [self ame428_overrideForVid:vid];

    if (ame428_a2) {
        // A2：实例隔离已开——版本级覆盖只保留“显式禁用”一条细分路径；
        // 跟随全局/启用一律 = 1（与现状逐位等价，见决策树注）。
        return (ame428_ov == 2) ? 0 : 1;
    }

    // A1：实例隔离未开——版本级 + 全局默认的主作用面
    if (ame428_ov == 1) return 1;
    if (ame428_ov == 2) return 0;
    NSInteger ame428_gl = (forcedGlobal >= 0 && forcedGlobal <= 2)
        ? forcedGlobal : [self ame428_globalDefault];
    switch (ame428_gl) {
        case 1: return 1;   // ALWAYS
        case 2: return 0;   // NEVER
        default: return [self ame428_autoEvidenceForVid:vid] ? 1 : 0;   // AUTO（MODDED）
    }
}

/// 有效隔离解析（对外单一入口；实读 version.config + 全局档实值）。
+ (NSInteger)ame428_effectiveIsolationForVid:(NSString *)vid profile:(NSDictionary *)profile {
    return [self ame428_effectiveCore:vid profile:profile forcedOverride:-1 forcedGlobal:-1];
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

/// 该 vid 的 A1 形 profile（gameDir 缺失/"."）里 lastPlayed 最新者——
/// 全局档翻转计算与下沉顺序的规范 profile（多 profile 引用同一版本时，
/// root 数据归最近游玩的那次上下文）。
+ (NSString *)ame428_latestSharedProfileNameForVid:(NSString *)vid {
    NSDictionary *ame428_profiles = [PLProfiles current].profiles;
    NSString *ame428_best = nil;
    NSTimeInterval ame428_bestTs = -1;
    for (NSString *ame428_key in [self ame428_profileNamesReferencingVid:vid]) {
        NSDictionary *ame428_p = ame428_profiles[ame428_key];
        if (![ame428_p isKindOfClass:[NSDictionary class]]) continue;
        id ame428_gd = ame428_p[@"gameDir"];
        BOOL ame428_shared = (![ame428_gd isKindOfClass:[NSString class]] ||
            ame428_gd.length == 0 ||
            [ame428_gd isEqualToString:@"."] || [ame428_gd isEqualToString:@"./"]);
        if (!ame428_shared) continue;
        id ame428_lp = ame428_p[@"lastPlayed"];
        NSTimeInterval ame428_ts = [ame428_lp isKindOfClass:[NSNumber class]] ? [ame428_lp doubleValue] : 0;
        if (ame428_ts > ame428_bestTs) { ame428_bestTs = ame428_ts; ame428_best = ame428_key; }
    }
    return ame428_best;
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
    // 整合包安装链/ame338 恢复流同款：显式写 gameDir=versions/<vid>
    //（= A2 隔离形态，与 PCL/HMCL 互导语义一致）
    ame428_profile[@"gameDir"] = [NSString stringWithFormat:@"versions/%@", vid];
    ame428_profile[@"type"] = @"custom";
    ame428_profile[@"created"] = [NSDate date].description;
    [PLProfiles.current saveProfile:ame428_profile withName:vid];
    NSLog(@"[Ame428] registry engage: registered version '%@' (gameDir=versions/%@)", vid, vid);
    return vid;
}

/// 下沉/回迁条目清单（1.4 任务书口径：saves/configs(MC 实名 config)/
/// resourcepacks/screenshots/logs/mods；两方向共用，对称）。
+ (NSArray<NSString *> *)ame428_moveItemNames {
    return @[@"saves", @"config", @"configs", @"resourcepacks", @"screenshots", @"logs", @"mods"];
}

/// 预检搬移候选：toIsolated=YES（实例根 → versions/<vid>/）方向源 = 共享根；
/// NO 方向源 = 版本目录。规则：源存在且目标不存在（绝不覆盖）。
+ (NSArray<NSString *> *)ame428_moveCandidatesForVid:(NSString *)vid toIsolated:(BOOL)toIsolated {
    NSMutableArray<NSString *> *ame428_out = [NSMutableArray array];
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    NSString *ame428_root = [self ame428_scanRoot];
    NSString *ame428_vdir = [self ame428_versionDirForVid:vid];
    if (ame428_root.length == 0 || ame428_vdir.length == 0) return @[];
    NSString *ame428_src = toIsolated ? ame428_root : ame428_vdir;
    NSString *ame428_dst = toIsolated ? ame428_vdir : ame428_root;
    for (NSString *ame428_item in [self ame428_moveItemNames]) {
        NSString *ame428_s = [ame428_src stringByAppendingPathComponent:ame428_item];
        NSString *ame428_d = [ame428_dst stringByAppendingPathComponent:ame428_item];
        if ([ame428_fm fileExistsAtPath:ame428_s] && ![ame428_fm fileExistsAtPath:ame428_d]) {
            [ame428_out addObject:ame428_item];
        }
    }
    return ame428_out;
}

/// 全局档翻转预演（设置页行 onSelect 调用；oldG/newG = 假想全局档）：
/// 枚举注册表 A1 profile 的唯一 vid 集，逐个算 from/to，收集真实翻转项，
/// 按 lastPlayed 降序（root 数据归最近游玩的版本——多版本同时翻转时
/// 第一顺位取得共享根数据，其余自然扑空跳过，报告留痕）。
+ (NSArray<NSDictionary *> *)ame428_computeGlobalFlipsFrom:(NSInteger)oldG to:(NSInteger)newG {
    if (oldG == newG) return @[];
    NSMutableArray<NSDictionary *> *ame428_out = [NSMutableArray array];
    NSMutableSet<NSString *> *ame428_seen = [NSMutableSet set];
    NSDictionary *ame428_profiles = [PLProfiles current].profiles;
    // 先枚举 (vid, A1 profile, lastPlayed)
    NSMutableArray<NSDictionary *> *ame428_pairs = [NSMutableArray array];
    for (NSString *ame428_key in ame428_profiles.allKeys) {
        NSDictionary *ame428_p = ame428_profiles[ame428_key];
        if (![ame428_p isKindOfClass:[NSDictionary class]]) continue;
        NSString *ame428_vid = [ame428_p[@"lastVersionId"] isKindOfClass:[NSString class]]
            ? ame428_p[@"lastVersionId"] : nil;
        if (ame428_vid.length == 0 || [ame428_vid hasPrefix:@"latest-"]) continue;
        id ame428_gd = ame428_p[@"gameDir"];
        BOOL ame428_shared = (![ame428_gd isKindOfClass:[NSString class]] ||
            ame428_gd.length == 0 ||
            [ame428_gd isEqualToString:@"."] || [ame428_gd isEqualToString:@"./"]);
        if (!ame428_shared) continue;   // A2/A3：全局档不影响（决策树）
        if ([ame428_seen containsObject:ame428_vid]) continue;
        [ame428_seen addObject:ame428_vid];
        NSTimeInterval ame428_ts = [ame428_p[@"lastPlayed"] isKindOfClass:[NSNumber class]]
            ? [ame428_p[@"lastPlayed"] doubleValue] : 0;
        [ame428_pairs addObject:@{@"vid": ame428_vid, @"profile": ame428_key, @"ts": @(ame428_ts)}];
    }
    [ame428_pairs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult ame428_r = [b[@"ts"] compare:a[@"ts"]];
        if (ame428_r != NSOrderedSame) return ame428_r;
        return [a[@"vid"] compare:b[@"vid"]];
    }];
    for (NSDictionary *ame428_pair in ame428_pairs) {
        NSString *ame428_vid = ame428_pair[@"vid"];
        NSDictionary *ame428_prof = ame428_profiles[ame428_pair[@"profile"]];
        NSInteger ame428_before = [self ame428_effectiveCore:ame428_vid profile:ame428_prof
            forcedOverride:-1 forcedGlobal:oldG];
        NSInteger ame428_after = [self ame428_effectiveCore:ame428_vid profile:ame428_prof
            forcedOverride:-1 forcedGlobal:newG];
        if (ame428_before == ame428_after) continue;
        [ame428_out addObject:@{
            @"vid": ame428_vid,
            @"profile": ame428_pair[@"profile"],
            @"from": @(ame428_before),
            @"to": @(ame428_after),
            @"items": [self ame428_moveCandidatesForVid:ame428_vid toIsolated:(ame428_after == 1)],
        }];
    }
    return ame428_out;
}

// ---------------------------------------------------------------------------
// ★Task428：迁移报告（12.2）——人可读、追加式；日期/动作/搬了什么/
// 跳过什么/失败什么；扫描清查（版本数/自愈数/剔除 inheritsFrom 数）
// 首次全量扫描记一份（报告内 marker 去重 = 真首次）。
// ---------------------------------------------------------------------------
+ (void)ame428_appendMigrationReport:(NSString *)line {
    NSString *ame428_path = [self ame428_migrationReportPath];
    if (ame428_path.length == 0 || line.length == 0) return;
    static NSDateFormatter *ame428_fmt = nil;
    static dispatch_once_t ame428_once;
    dispatch_once(&ame428_once, ^{
        ame428_fmt = [[NSDateFormatter alloc] init];
        ame428_fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        ame428_fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    NSString *ame428_stamp = [NSString stringWithFormat:@"==== %@  %@\n",
        [ame428_fmt stringFromDate:[NSDate date]], line];
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    [ame428_fm createDirectoryAtPath:[ame428_path stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:nil];
    NSFileHandle *ame428_h = nil;
    @try {
        if (![ame428_fm fileExistsAtPath:ame428_path]) {
            [ame428_fm createFileAtPath:ame428_path contents:nil attributes:nil];
        }
        ame428_h = [NSFileHandle fileHandleForWritingAtPath:ame428_path];
        [ame428_h seekToEndOfFile];
        [ame428_h writeData:[ame428_stamp dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (NSException *ame428_ex) {
        NSLog(@"[Ame428] migration report append failed: %@", ame428_ex);
    } @finally {
        [ame428_h closeFile];
        ame428_h = nil;
    }
}

/// 扫描清查（12.2：列表重构后的首次全量扫描结果记一份）。
/// stats：total / selfHealed（json 损坏但身份自愈于目录名）/ inheritsExcluded /
/// jsonMissingExcluded。报告内已有 scan-census 标记则跳过（真首次）。
+ (void)ame428_recordScanCensusOnce:(NSDictionary *)stats {
    if (![stats isKindOfClass:[NSDictionary class]]) return;
    NSString *ame428_path = [self ame428_migrationReportPath];
    if (ame428_path.length > 0) {
        NSString *ame428_old = [NSString stringWithContentsOfFile:ame428_path
            encoding:NSUTF8StringEncoding error:nil];
        if ([ame428_old containsString:@"action=scan-census"]) return;
    }
    [self ame428_appendMigrationReport:[NSString stringWithFormat:
        @"★Task428 action=scan-census versions=%ld selfHealed=%ld inheritsExcluded=%ld jsonMissingExcluded=%ld (首次全量扫描：版本总数 / json 损坏自愈数 / inheritsFrom 去重数 / json 缺失剔除数)",
        (long)[stats[@"total"] integerValue],
        (long)[stats[@"selfHealed"] integerValue],
        (long)[stats[@"inheritsExcluded"] integerValue],
        (long)[stats[@"jsonMissingExcluded"] integerValue]]];
}

// ---------------------------------------------------------------------------
// ★Task428：一次性下沉/回迁执行体（1.4）。
// 原子性纪律（任务书）：先全部 copy 再删源，中途失败恢复（删除本轮已
// copy 出来的目标副本，源从未被动过）；删源失败 = 双份数据（绝不丢失，
// 报告留痕）。搬移前先做 zip 快照（无轻量目录快照 API——DataTransferService
// 分区导出无法表达 logs/任意根，选自研 store 级 zip 写器，报告说明选择）；
// 快照失败则整轮中止（宁可不动数据）。
// ---------------------------------------------------------------------------
+ (NSDictionary *)ame428_executeIsolationDataMoveForVid:(NSString *)vid
                                            toIsolated:(BOOL)toIsolated
                                                 reason:(NSString *)reason {
    NSMutableArray<NSString *> *ame428_moved = [NSMutableArray array];
    NSMutableArray<NSString *> *ame428_skipped = [NSMutableArray array];
    NSMutableArray<NSString *> *ame428_failed = [NSMutableArray array];
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    NSString *ame428_root = [self ame428_scanRoot];
    NSString *ame428_vdir = [self ame428_versionDirForVid:vid];
    if (vid.length == 0 || ame428_root.length == 0 || ame428_vdir.length == 0) {
        return @{@"ok": @NO, @"error": @"env unset", @"moved": @[], @"skipped": @[], @"failed": @[]};
    }
    if (toIsolated) {
        [ame428_fm createDirectoryAtPath:ame428_vdir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *ame428_src = toIsolated ? ame428_root : ame428_vdir;
    NSString *ame428_dst = toIsolated ? ame428_vdir : ame428_root;

    // 候选（源存在且目标不存在；目标已存在 = 跳过并记录，绝不覆盖）
    NSMutableArray<NSDictionary *> *ame428_plan = [NSMutableArray array];
    for (NSString *ame428_item in [self ame428_moveItemNames]) {
        NSString *ame428_s = [ame428_src stringByAppendingPathComponent:ame428_item];
        NSString *ame428_d = [ame428_dst stringByAppendingPathComponent:ame428_item];
        BOOL ame428_sDir = NO, ame428_dExists = NO;
        if (![ame428_fm fileExistsAtPath:ame428_s isDirectory:&ame428_sDir] || !ame428_sDir) continue;
        if ([ame428_fm fileExistsAtPath:ame428_d]) {
            [ame428_skipped addObject:[NSString stringWithFormat:@"%@（目标已存在，跳过不覆盖）", ame428_item]];
            continue;
        }
        [ame428_plan addObject:@{@"item": ame428_item, @"src": ame428_s, @"dst": ame428_d}];
    }
    if (ame428_plan.count == 0) {
        [self ame428_appendMigrationReport:[NSString stringWithFormat:
            @"★Task428 action=isolation-move vid=%@ dir=%@ result=noop（无候选条目） reason=%@",
            vid, toIsolated ? @"in" : @"out", reason ?: @""]];
        return @{@"ok": @YES, @"moved": @[], @"skipped": ame428_skipped, @"failed": ame428_failed,
                 @"snapshot": @"", @"error": @""};
    }

    // —— 快照（仅对本轮真正要搬的候选；失败中止）——
    NSDictionary *ame428_snap = [self ame428_writePreIsolationSnapshotForVid:vid
        srcRoot:ame428_src items:[ame428_plan valueForKeyPath:@"item"]];
    if (![ame428_snap[@"ok"] boolValue]) {
        [ame428_failed addObject:[NSString stringWithFormat:@"snapshot（%@）", ame428_snap[@"error"] ?: @"?"]];
        [self ame428_appendMigrationReport:[NSString stringWithFormat:
            @"★Task428 action=isolation-move vid=%@ dir=%@ result=ABORT（快照失败，数据未动）error=%@ reason=%@",
            vid, toIsolated ? @"in" : @"out", ame428_snap[@"error"] ?: @"?", reason ?: @""]];
        return @{@"ok": @NO, @"moved": @[], @"skipped": ame428_skipped, @"failed": ame428_failed,
                 @"snapshot": @"", @"error": [NSString stringWithFormat:@"snapshot: %@", ame428_snap[@"error"] ?: @"?"]};
    }

    // —— copy 阶段（先全部 copy；中途失败 → 删除本轮已 copy 副本 = 恢复）——
    NSMutableArray<NSString *> *ame428_copied = [NSMutableArray array];
    BOOL ame428_copyFailed = NO;
    for (NSDictionary *ame428_step in ame428_plan) {
        NSError *ame428_err = nil;
        if ([ame428_fm copyItemAtPath:ame428_step[@"src"] toPath:ame428_step[@"dst"] error:&ame428_err]) {
            [ame428_copied addObject:ame428_step[@"dst"]];
            [ame428_moved addObject:ame428_step[@"item"]];
        } else {
            [ame428_failed addObject:[NSString stringWithFormat:@"%@（copy: %@）",
                ame428_step[@"item"], ame428_err.localizedDescription ?: @"?"]];
            ame428_copyFailed = YES;
            break;
        }
    }
    if (ame428_copyFailed) {
        for (NSString *ame428_c in ame428_copied) [ame428_fm removeItemAtPath:ame428_c error:nil];
        [self ame428_appendMigrationReport:[NSString stringWithFormat:
            @"★Task428 action=isolation-move vid=%@ dir=%@ result=ROLLED-BACK（copy 中途失败，已恢复，源未动）失败=%@ moved-aborted=%ld reason=%@",
            vid, toIsolated ? @"in" : @"out", [ame428_failed componentsJoinedByString:@"; "],
            (long)ame428_copied.count, reason ?: @""]];
        return @{@"ok": @NO, @"moved": @[], @"skipped": ame428_skipped, @"failed": ame428_failed,
                 @"snapshot": ame428_snap[@"path"] ?: @"", @"error": @"copy failed (rolled back)"};
    }

    // —— delete 阶段（全部 copy 成功后才删源；删失败 = 双份数据，绝不丢失）——
    for (NSDictionary *ame428_step in ame428_plan) {
        if (![ame428_fm removeItemAtPath:ame428_step[@"src"] error:nil]) {
            [ame428_failed addObject:[NSString stringWithFormat:@"%@（删源失败，两份数据并存）", ame428_step[@"item"]]];
        }
    }

    [self ame428_appendMigrationReport:[NSString stringWithFormat:
        @"★Task428 action=isolation-move vid=%@ dir=%@ moved=%@ skipped=%@ failed=%@ snapshot=%@ reason=%@",
        vid, toIsolated ? @"in" : @"out",
        [ame428_moved componentsJoinedByString:@","] ?: @"-",
        ame428_skipped.count > 0 ? [ame428_skipped componentsJoinedByString:@"; "] : @"-",
        ame428_failed.count > 0 ? [ame428_failed componentsJoinedByString:@"; "] : @"-",
        ame428_snap[@"path"] ?: @"", reason ?: @""]];
    BOOL ame428_ok = (ame428_failed.count == 0);
    return @{@"ok": @(ame428_ok), @"moved": ame428_moved, @"skipped": ame428_skipped,
             @"failed": ame428_failed, @"snapshot": ame428_snap[@"path"] ?: @"",
             @"error": ame428_ok ? @"" : [ame428_failed componentsJoinedByString:@"; "]};
}

// ---------------------------------------------------------------------------
// ★Task428：pre-isolation zip 快照（自研 store 级 zip 写器）。
// 落点 Prisma2/backups/pre-isolation-<vid>-<ts>.zip。选 store（不压缩）：
// CPU 零开销、纯磁盘顺序写；条目名 = <item>/<相对路径>；CRC32 自研表实现
// （零链接期依赖——DataTransferService 的 zlib 走 dlsym，此处更简）。
// 容量护栏：单文件/总大小/条目数触及 32bit zip 上限即判失败（中止搬移）。
// ---------------------------------------------------------------------------
+ (NSDictionary *)ame428_writePreIsolationSnapshotForVid:(NSString *)vid
                                                 srcRoot:(NSString *)srcRoot
                                                   items:(NSArray<NSString *> *)itemNames {
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    NSString *ame428_p2 = [self ame428_prisma2Root];
    if (ame428_p2.length == 0) return @{@"ok": @NO, @"error": @"POJAV_HOME unset"};
    NSString *ame428_bdir = [ame428_p2 stringByAppendingPathComponent:@"backups"];
    [ame428_fm createDirectoryAtPath:ame428_bdir withIntermediateDirectories:YES attributes:nil error:nil];
    static NSDateFormatter *ame428_fmt = nil;
    static dispatch_once_t ame428_once;
    dispatch_once(&ame428_once, ^{
        ame428_fmt = [[NSDateFormatter alloc] init];
        ame428_fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        ame428_fmt.dateFormat = @"yyyyMMdd-HHmmss";
    });
    NSString *ame428_zip = [ame428_bdir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"pre-isolation-%@-%@.zip", vid, [ame428_fmt stringFromDate:[NSDate date]]]];

    // 收集（rel → 目录/文件 + 尺寸 + mtime）
    NSMutableArray<NSDictionary *> *ame428_entries = [NSMutableArray array];
    NSMutableArray<NSString *> *ame428_roots = [NSMutableArray array];
    for (NSString *ame428_item in itemNames) {
        NSString *ame428_s = [srcRoot stringByAppendingPathComponent:ame428_item];
        BOOL ame428_isDir = NO;
        if (![ame428_fm fileExistsAtPath:ame428_s isDirectory:&ame428_isDir] || !ame428_isDir) continue;
        [ame428_roots addObject:ame428_item];
        [ame428_entries addObject:@{@"rel": ame428_item, @"src": ame428_s, @"dir": @YES, @"size": @(0), @"mtime": [NSDate date]}];
        [self ame428_collectTree:ame428_s rel:ame428_item into:ame428_entries];
    }
    if (ame428_entries.count == 0) return @{@"ok": @NO, @"error": @"nothing to snapshot"};

    unsigned long long ame428_total = 0;
    NSUInteger ame428_files = 0;
    for (NSDictionary *ame428_e in ame428_entries) {
        if (![ame428_e[@"dir"] boolValue]) {
            ame428_total += [ame428_e[@"size"] unsignedLongLongValue];
            ame428_files++;
        }
    }
    if (ame428_files >= 0xFFFF || ame428_total >= 0xFFFFFFFFULL || ame428_entries.count >= 0xFFFF) {
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"too large (%llu bytes, %lu files)",
            ame428_total, (unsigned long)ame428_files]};
    }
    if (![ame428_fm createFileAtPath:ame428_zip contents:nil attributes:nil]) {
        return @{@"ok": @NO, @"error": @"create failed"};
    }
    NSFileHandle *ame428_out = [NSFileHandle fileHandleForWritingAtPath:ame428_zip];
    if (!ame428_out) return @{@"ok": @NO, @"error": @"open failed"};

    // 本地头（30 字节：flag 0x0808 = bit3 数据后置描述符 + bit11 UTF-8 名；
    // store 方法 crc/csize/usize 置 0 由 16 字节描述符后置）→ 数据 → 描述符
    NSMutableArray<NSDictionary *> *ame428_cd = [NSMutableArray array];
    unsigned long long ame428_offset = 0;
    static const NSUInteger ame428_chunk = 1 << 20;
    BOOL ame428_ioErr = NO;
    for (NSDictionary *ame428_e in ame428_entries) {
        if (ame428_ioErr) break;
        NSString *ame428_name = ame428_e[@"rel"];
        NSData *ame428_nameData = [ame428_name dataUsingEncoding:NSUTF8StringEncoding];
        if (!ame428_nameData) { ame428_ioErr = YES; break; }
        BOOL ame428_isDir = [ame428_e[@"dir"] boolValue];
        NSDate *ame428_mt = [ame428_e[@"mtime"] isKindOfClass:[NSDate class]] ? ame428_e[@"mtime"] : [NSDate date];
        uint16_t ame428_dTime = 0, ame428_dDate = 0;
        ame428_dosDateTime(ame428_mt, &ame428_dTime, &ame428_dDate);
        uint32_t ame428_crc = 0;
        unsigned long long ame428_size = [ame428_e[@"size"] unsignedLongLongValue];
        unsigned long long ame428_wrote = 0;

        NSMutableData *ame428_hdr = [NSMutableData dataWithCapacity:30 + ame428_nameData.length];
        uint8_t ame428_lfh[30];
        memset(ame428_lfh, 0, sizeof(ame428_lfh));
        ame428_put32(ame428_lfh + 0, 0x04034b50);      // 签名
        ame428_put16(ame428_lfh + 4, 20);              // version needed
        ame428_put16(ame428_lfh + 6, 0x0808);          // flags
        ame428_put16(ame428_lfh + 8, 0);               // method = store
        ame428_put16(ame428_lfh + 10, ame428_dTime);
        ame428_put16(ame428_lfh + 12, ame428_dDate);
        ame428_put16(ame428_lfh + 28, (uint16_t)ame428_nameData.length);
        [ame428_hdr appendBytes:ame428_lfh length:sizeof(ame428_lfh)];
        [ame428_hdr appendData:ame428_nameData];
        [ame428_out writeData:ame428_hdr];

        if (!ame428_isDir) {
            NSFileHandle *ame428_in = [NSFileHandle fileHandleForReadingAtPath:ame428_e[@"src"]];
            if (!ame428_in) { ame428_ioErr = YES; break; }
            @try {
                for (;;) {
                    NSData *ame428_blk = [ame428_in readDataOfLength:ame428_chunk];
                    if (ame428_blk.length == 0) break;
                    ame428_crc = ame428_crc32(ame428_crc, ame428_blk.bytes, (unsigned)ame428_blk.length);
                    [ame428_out writeData:ame428_blk];
                    ame428_wrote += ame428_blk.length;
                }
            } @catch (NSException *) { ame428_ioErr = YES; }
            [ame428_in closeFile];
            if (ame428_ioErr) break;
            if (ame428_wrote != ame428_size) { ame428_ioErr = YES; break; }
            uint8_t ame428_dd[16];
            ame428_put32(ame428_dd + 0, 0x08074b50);
            ame428_put32(ame428_dd + 4, ame428_crc);
            ame428_put32(ame428_dd + 8, (uint32_t)ame428_wrote);
            ame428_put32(ame428_dd + 12, (uint32_t)ame428_wrote);
            [ame428_out writeData:[NSData dataWithBytes:ame428_dd length:16]];
        }
        [ame428_cd addObject:@{
            @"name": ame428_nameData, @"crc": @(ame428_crc), @"size": @(ame428_wrote),
            @"time": @(ame428_dTime), @"date": @(ame428_dDate), @"off": @(ame428_offset),
        }];
        ame428_offset += ame428_hdr.length + (ame428_isDir ? 0 : (ame428_wrote + 16));
    }
    if (ame428_ioErr) {
        [ame428_out closeFile];
        [ame428_fm removeItemAtPath:ame428_zip error:nil];
        return @{@"ok": @NO, @"error": @"io error"};
    }

    // 中央目录（46 字节/条目）+ EOCD（22 字节）
    unsigned long long ame428_cdStart = ame428_offset;
    NSMutableData *ame428_cdData = [NSMutableData data];
    for (NSDictionary *ame428_c in ame428_cd) {
        NSData *ame428_nameData = ame428_c[@"name"];
        uint8_t ame428_cdh[46];
        memset(ame428_cdh, 0, sizeof(ame428_cdh));
        ame428_put32(ame428_cdh + 0, 0x02014b50);
        ame428_put16(ame428_cdh + 4, 20);                        // version made by (3.0 低 16 位)
        ame428_put16(ame428_cdh + 6, 20);                        // version needed
        ame428_put16(ame428_cdh + 8, 0x0808);                    // flags
        ame428_put16(ame428_cdh + 10, 0);                        // method = store
        ame428_put16(ame428_cdh + 12, [ame428_c[@"time"] unsignedShortValue]);
        ame428_put16(ame428_cdh + 14, [ame428_c[@"date"] unsignedShortValue]);
        ame428_put32(ame428_cdh + 16, [ame428_c[@"crc"] unsignedIntValue]);
        ame428_put32(ame428_cdh + 20, [ame428_c[@"size"] unsignedIntValue]);
        ame428_put32(ame428_cdh + 24, [ame428_c[@"size"] unsignedIntValue]);
        ame428_put16(ame428_cdh + 28, (uint16_t)ame428_nameData.length);
        ame428_put32(ame428_cdh + 42, [ame428_c[@"off"] unsignedIntValue]);
        [ame428_cdData appendBytes:ame428_cdh length:sizeof(ame428_cdh)];
        [ame428_cdData appendData:ame428_nameData];
    }
    uint8_t ame428_eocd[22];
    memset(ame428_eocd, 0, sizeof(ame428_eocd));
    ame428_put32(ame428_eocd + 0, 0x06054b50);
    ame428_put16(ame428_eocd + 8, (uint16_t)ame428_cd.count);
    ame428_put16(ame428_eocd + 10, (uint16_t)ame428_cd.count);
    ame428_put32(ame428_eocd + 12, (uint32_t)ame428_cdData.length);
    ame428_put32(ame428_eocd + 16, (uint32_t)ame428_cdStart);
    [ame428_out writeData:ame428_cdData];
    [ame428_out writeData:[NSData dataWithBytes:ame428_eocd length:22]];
    [ame428_out closeFile];
    return @{@"ok": @YES, @"path": ame428_zip,
             @"bytes": @(ame428_total), @"files": @(ame428_files),
             @"roots": ame428_roots};
}

/// 递归收集快照条目（rel 以 '/' 分隔；目录条目也入列——恢复保真）。
/// 属性取值一律下标（NSFileSize/NSFileModificationDate；main.m CI 判例：
/// 属性点语法族在部分编译单元不可见）。
+ (void)ame428_collectTree:(NSString *)dir rel:(NSString *)rel into:(NSMutableArray<NSDictionary *> *)out {
    NSFileManager *ame428_fm = [NSFileManager defaultManager];
    for (NSString *ame428_name in [ame428_fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
        if ([ame428_name hasPrefix:@"."]) continue;
        NSString *ame428_childRel = [rel stringByAppendingPathComponent:ame428_name];
        NSString *ame428_child = [dir stringByAppendingPathComponent:ame428_name];
        BOOL ame428_isDir = NO;
        if (![ame428_fm fileExistsAtPath:ame428_child isDirectory:&ame428_isDir]) continue;
        if (ame428_isDir) {
            [out addObject:@{@"rel": ame428_childRel, @"src": ame428_child, @"dir": @YES, @"size": @(0), @"mtime": [NSDate date]}];
            [self ame428_collectTree:ame428_child rel:ame428_childRel into:out];
        } else {
            NSDictionary *ame428_attr = [ame428_fm attributesOfItemAtPath:ame428_child error:nil];
            id ame428_sz = [ame428_attr isKindOfClass:[NSDictionary class]] ? ame428_attr[NSFileSize] : nil;
            id ame428_mt = [ame428_attr isKindOfClass:[NSDictionary class]] ? ame428_attr[NSFileModificationDate] : nil;
            [out addObject:@{
                @"rel": ame428_childRel, @"src": ame428_child, @"dir": @NO,
                @"size": @([ame428_sz isKindOfClass:[NSNumber class]] ? [ame428_sz unsignedLongLongValue] : 0),
                @"mtime": [ame428_mt isKindOfClass:[NSDate class]] ? ame428_mt : [NSDate date],
            }];
        }
    }
}

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

// ---------------------------------------------------------------------------
// ★Task428（1.4）：翻转确认 + 一次性下沉/回迁的共享呈现流。
// 宿主 = 本模型类（版本列表 engage / 版本详情页隔离行 / 设置页全局档
// 共用一实现防三处漂移；页面间零直连纪律见上）。无候选条目时直接
// onCommit（不弹不搬不留报告噪音）。先问再动（PCL VER-ISOLATE 哲学）：
// 取消不落任何状态；确认后 进度弹窗 → 后台执行（快照→copy 全→删源，
// 中途失败自动恢复）→ 成功才 onCommit。
// ---------------------------------------------------------------------------
+ (void)ame428_presentIsolationMoveFlowFrom:(UIViewController *)presenter
                                        vid:(NSString *)vid
                                 toIsolated:(BOOL)toIsolated
                                     reason:(NSString *)reason
                                  onCommit:(void (^)(void))onCommit {
    if (![vid isKindOfClass:[NSString class]] || vid.length == 0 || !presenter) return;
    NSArray<NSString *> *ame428_items = [self ame428_moveCandidatesForVid:vid toIsolated:toIsolated];
    if (ame428_items.count == 0) {
        if (onCommit) onCommit();
        return;
    }
    NSString *ame428_dirText = toIsolated
        ? localize(@"ame428.iso.confirm.into", @"把实例根目录下的游戏数据移入该版本的独立目录（versions/%@/）")
        : localize(@"ame428.iso.confirm.outof", @"把该版本独立目录（versions/%@/）里的游戏数据移回实例根目录");
    NSString *ame428_msg = [NSString stringWithFormat:
        @"%@\n\n%@\n%@\n%@",
        [NSString stringWithFormat:ame428_dirText, vid],
        [NSString stringWithFormat:localize(@"ame428.iso.confirm.items", @"将搬移：%@"),
            [ame428_items componentsJoinedByString:@", "]],
        localize(@"ame428.iso.confirm.snapshot",
            @"搬移前会先做完整备份（Prisma2/backups/pre-isolation-<版本>-<时间>.zip），中途失败自动恢复，数据不会丢失。"),
        localize(@"ame428.iso.confirm.cancel_note", @"取消则不作任何更改。")];
    UIAlertController *ame428_alert = [UIAlertController
        alertControllerWithTitle:localize(@"ame428.iso.confirm.title", @"确认数据迁移")
                         message:ame428_msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [ame428_alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                                     style:UIAlertActionStyleCancel handler:nil]];
    [ame428_alert addAction:[UIAlertAction
        actionWithTitle:localize(@"ame428.iso.confirm.go", @"开始迁移")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *a) {
        UIAlertController *ame428_prog = [UIAlertController
            alertControllerWithTitle:localize(@"ame428.iso.confirm.title", @"确认数据迁移")
                             message:localize(@"ame428.iso.progress", @"正在迁移游戏数据…")
                      preferredStyle:UIAlertControllerStyleAlert];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [presenter presentViewController:ame428_prog animated:NO completion:nil];
        });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *ame428_result = [self ame428_executeIsolationDataMoveForVid:vid
                toIsolated:toIsolated reason:reason];
            dispatch_async(dispatch_get_main_queue(), ^{
                [ame428_prog dismissViewControllerAnimated:NO completion:^{
                    if ([ame428_result[@"ok"] boolValue]) {
                        if (onCommit) onCommit();
                    } else {
                        UIAlertController *ame428_fail = [UIAlertController
                            alertControllerWithTitle:localize(@"i18n_str_388", nil)
                                             message:[NSString stringWithFormat:
                                                 localize(@"ame428.iso.result.failed_fmt",
                                                     @"迁移未完成，数据已恢复原状：%@"),
                                                 ame428_result[@"error"] ?: @"?"]
                                      preferredStyle:UIAlertControllerStyleAlert];
                        [ame428_fail addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                                                         style:UIAlertActionStyleDefault handler:nil]];
                        [presenter presentViewController:ame428_fail animated:YES completion:nil];
                    }
                }];
            });
        });
    }]];
    [presenter presentViewController:ame428_alert animated:YES completion:nil];
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

@end
