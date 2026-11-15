//
// ZL2DynamicPalette.m — ★Task429（PDF 第五版 §8.1 + 第六版 §3.2.3）主题中枢实现
//
// 生效链接线点（汇报用）：
//   · 模式/种子/风格变化：ZL2SettingPages.m 外观组「主题色板」行 +
//     ZL2ThemeCustomSheet 确认钮 → 写三新键 → ame429_reloadAndApply；
//   · 壁纸更换：BackgroundManager set/clear 路径补播 Ame223WallpaperChanged
//     （★Task429 四处补播）→ 本中枢 ame429_wallpaperDidChange；
//   · 根重建杠杆：[ZL2Theme ame429_requestRootRebuild]（Task346/Task380
//     既有链——AppLanguageChanged → SceneDelegate applyLanguageChange 整壳
//     重建 + 400ms 冷却尾沿补排；不发明第二套广播）；
//   · 覆盖推送：[ZL2Theme ame429_setActivePaletteOverlay:]（ZL2Theme 覆盖点
//     查询先查覆盖 miss 回落 embermire——未初始化/模式 0 时逐位等价旧值）。
//

#import "ZL2DynamicPalette.h"

#import "ZL2Theme.h"                 // 覆盖推送 + 根重建杠杆（Task346 复用）
#import "AmeHCTPalette.h"            // HCT 色板生成
#import "AmeUIImageColors.h"         // 壁纸主色提取（后台线程）
#import "BackgroundManager.h"        // 壁纸管线（Task223 降采样直取 + 通知）
#import "LauncherPreferences.h"      // getPrefObject 只读 API + ACCENT_COLOR_DEFAULT_HEX（文件禁改）

#pragma mark - 常量实名表（★Task429）

// 预设色板种子（色值近似移植——仓内无 ZalithLauncher2 Color.kt 参考副本，
// 取 ZL2 视觉家族近似种子；HCT 重演后色相正确、深浅阶分明。顺序 = mode 2..7）
static const int Ame429PresetSeedEmbermireReplay = 0xA63A17; // embermire 主棕（动态重演近似）
static const int Ame429PresetSeedFrozenLake      = 0x2779B5; // 冻湖蓝：湖蓝
static const int Ame429PresetSeedForestGreen     = 0x2E7D51; // 森绿：森林绿
static const int Ame429PresetSeedDuskPurple      = 0x6E56A6; // 暮紫：暮霭紫
static const int Ame429PresetSeedCrimson         = 0xB4424C; // 绯红：绯红
static const int Ame429PresetSeedAmber           = 0xA97A2C; // 琥珀：琥珀

// 三新键（注册片段 scripts/task429_prefs_F.json；注册面归主控合流——
// 注册前写值被静默丢弃、读侧缺键回退默认，Task429 BC 站判例同口径）
static NSString * const Ame429KeyThemeMode       = @"general.theme_mode";
static NSString * const Ame429KeyCustomSeedColor = @"general.custom_seed_color";
static NSString * const Ame429KeyPaletteStyle    = @"general.custom_palette_style";

// 旧自定义三色 accent_color（断链修复只读回落源；LauncherPreferences 禁改）
static NSString * const Ame429LegacyAccentColorKey = @"general.accent_color";

@interface ZL2DynamicPalette ()
@property (nonatomic, readwrite, assign) NSInteger themeMode;
@property (nonatomic, readwrite, assign) NSInteger paletteStyle;
@property (nonatomic, assign) NSUInteger wallpaperChangeGeneration;
@end

@implementation ZL2DynamicPalette

// ★Task429：懒启动钩子注册（+load 期——真机目标 TU 在位即注册；预览/冒烟
// 目标本 TU 不编入，ZL2Theme 钩子恒 NULL = embermire 基线逐位不变）。
// ★ 防重入用普通哨兵而非 dispatch_once：trampoline 在 ZL2Theme 色查询链内
//   执行，若链上再入（假设链）dispatch_once 同线程会死锁；哨兵语义下
//   再入安全跳过、跨线程竞态重复触达由 shared 的 dispatch_once 幂等吸收。
static BOOL ame429_trampolineRan = NO;
static void Ame429PaletteBootstrapTrampoline(void) {
    if (ame429_trampolineRan) return;
    ame429_trampolineRan = YES;
    NSInteger ame429_mode = [[ZL2DynamicPalette shared] themeMode];
    NSLog(@"[Ame429] palette hub bootstrap via ZL2Theme hook (mode=%ld)",
          (long)ame429_mode);
}

+ (void)load {
    [ZL2Theme ame429_setPaletteBootstrapHook:&Ame429PaletteBootstrapTrampoline];
}

#pragma mark - 单例 + 启动期生效（首查询同步落板，避免换板闪变）

+ (instancetype)shared {
    static ZL2DynamicPalette *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 读三键（LauncherPreferences 只读 API getPrefInt/getPrefObject——偏好
        // 实体为 PLPreferences plist，非 NSUserDefaults，勿直读 defaults；
        // 越界回落；缺键 = 默认 embermire 零覆盖）
        NSInteger rawMode = getPrefInt(Ame429KeyThemeMode);
        if (rawMode < 0 || rawMode > 8) rawMode = 0;
        _themeMode = rawMode;
        NSInteger rawStyle = getPrefInt(Ame429KeyPaletteStyle);
        if (rawStyle < 0 || rawStyle > 2) rawStyle = 0;
        _paletteStyle = rawStyle;

        // 壁纸更换链（Task223 通知；set/clear 补播见 BackgroundManager ★Task429）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ame429_onWallpaperChanged)
                                                     name:Ame223WallpaperChangedNotification
                                                   object:nil];

        // 启动期同步落板（首个 ZL2Theme 色查询经懒加载触达本 init——早于
        // ZL2Shell 首建；非跟随模式 HCT 纯数学毫秒级，主线程可承受；
        // 跟随背景模式此处先落 embermire 保底 + 后台取色补推）。
        // ★ 启动期静默语义：只推覆盖不触发根重建——首建即新板，重建是
        //   纯浪费且会跟 viewDidLoad 竞态（ame346 冷却链无需介入）。
        NSDictionary *bootOverlay = [self ame429_overlayForMode:_themeMode];
        [ZL2Theme ame429_setActivePaletteOverlay:bootOverlay];
        if (_themeMode == Ame429ThemeModeFollowWall) {
            [self ame429_extractFromWallpaperAsync];   // 后台取色，完成后带重建补推
        }
        NSLog(@"[Ame429] dynamic palette bootstrapped mode=%ld style=%ld",
              (long)_themeMode, (long)_paletteStyle);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 对外入口

- (void)ame429_reloadAndApply {
    // 模式/风格键重读（越界回落；设置行/CustomSheet 写键后统一走此入口）
    NSInteger rawMode = getPrefInt(Ame429KeyThemeMode);
    if (rawMode < 0 || rawMode > 8) rawMode = 0;
    NSInteger rawStyle = getPrefInt(Ame429KeyPaletteStyle);
    if (rawStyle < 0 || rawStyle > 2) rawStyle = 0;
    self.themeMode = rawMode;
    self.paletteStyle = rawStyle;
    NSDictionary *overlay = [self ame429_overlayForMode:self.themeMode];
    [self ame429_pushOverlay:overlay];   // 带根重建（Task346 杠杆）
    if (self.themeMode == Ame429ThemeModeFollowWall) {
        [self ame429_extractFromWallpaperAsync];   // 后台取色完成后再补推一次
    }
}

- (void)ame429_wallpaperDidChange {
    // 仅跟随背景模式有语义（其余模式与壁纸无关联，零操作）
    if (self.themeMode != Ame429ThemeModeFollowWall) return;
    // 壁纸滑条会连续广播：保留现有色板，尾沿 180ms 只取最后一帧，避免每 tick
    // 主线程解码以及先撤覆盖造成的 embermire 闪回。
    NSUInteger generation = ++self.wallpaperChangeGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.wallpaperChangeGeneration ||
            self.themeMode != Ame429ThemeModeFollowWall) return;
        [self ame429_extractFromWallpaperAsync];
    });
}

#pragma mark - 通知回调

- (void)ame429_onWallpaperChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame429_wallpaperDidChange];
    });
}

#pragma mark - 模式应用（生效链主体）

// 模式 → 覆盖映射（静默/重建共用；跟随背景模式返回 nil 保底 + 异步补推）
- (nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)ame429_overlayForMode:(NSInteger)mode {
    switch (mode) {
        case Ame429ThemeModeEmbermire: {
            // 模式 0：零覆盖（ZL2Theme 覆盖点 miss 逐位回落 embermire 静态值）
            return nil;
        }
        case Ame429ThemeModeFollowWall: {
            // 跟随背景：先落 embermire 保底（取色在途期界面不裸奔），
            // 再后台取色（输入吃 Task223 降采样管线 = 第六版捆绑项）。
            // 异步补推由调用方分流（bootstrap 静默 / reloadAndApply 带重建）。
            return nil;
        }
        case Ame429ThemeModeCustom: {
            // CUSTOM：用户种子 → 断链修复回落旧 accent_color → 默认蓝
            return [self ame429_tokenMapWithSeed:[self ame429_customSeedColor]];
        }
        default: {
            // 预设 2..7：编译期种子表（近似移植，见文件头）
            NSInteger presetIndex = mode - (NSInteger)Ame429ThemeModeEmbermireReplay;
            NSArray<NSNumber *> *presetSeeds = @[
                @(Ame429PresetSeedEmbermireReplay),
                @(Ame429PresetSeedFrozenLake),
                @(Ame429PresetSeedForestGreen),
                @(Ame429PresetSeedDuskPurple),
                @(Ame429PresetSeedCrimson),
                @(Ame429PresetSeedAmber),
            ];
            if (presetIndex < 0 || (NSUInteger)presetIndex >= presetSeeds.count) {
                return nil;
            }
            int seedHex = presetSeeds[presetIndex].intValue;
            return [self ame429_tokenMapWithSeed:[self ame429_colorFromHexInt:seedHex]];
        }
    }
}

// HCT 生成（纯数学同步路径，任意线程安全）
- (nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)ame429_tokenMapWithSeed:(nullable UIColor *)seed {
    if (seed == nil) return nil;
    AmeHCTPaletteStyle style = AmeHCTPaletteStyleNatural;
    if (self.paletteStyle == 1) style = AmeHCTPaletteStyleVivid;
    if (self.paletteStyle == 2) style = AmeHCTPaletteStyleSoft;
    AmeHCTPalette *palette = [AmeHCTPalette ame429_paletteWithSeed:seed style:style];
    return [palette ame429_tokenMap];
}

// 覆盖推送 + 根重建（主线程收敛；覆盖点见 ZL2Theme.m ★Task429 注记）
- (void)ame429_pushOverlay:(nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)overlay {
    void (^apply)(void) = ^{
        [ZL2Theme ame429_setActivePaletteOverlay:overlay];
        [ZL2Theme ame429_requestRootRebuild];
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

#pragma mark - 跟随背景：后台取色（降采样管线输入）

- (void)ame429_extractFromWallpaperAsync {
    // 输入 = Task223 降采样直取壁纸（CGImageSourceCreateThumbnailAtIndex，
    // 屏幕级分辨率——「先降采样再提色」，第六版 v2-7.2 捆绑项同链清账）
    UIImage *wallpaper = [[BackgroundManager sharedManager] ame223_currentWallpaperImage];
    if (wallpaper == nil) {
        // 壁纸缺席（清除/纯色/视频）：跟随背景无源 → 回落 embermire
        [self ame429_pushOverlay:nil];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [AmeUIImageColors ame429_extractFromImage:wallpaper
                                     maxPixel:0   // 0 = 类内默认 128（聚类语义分辨率）
                                   completion:^(UIColor *background, UIColor *primary,
                                                UIColor *secondary, UIColor *detail,
                                                BOOL feasible, BOOL isDarkBackground) {
        // 回主线程（AmeUIImageColors 契约）；主色优先，不可行回落背景色
        UIColor *seed = primary ?: background;
        NSLog(@"[Ame429] wallpaper extract feasible=%d dark=%d",
              (int)feasible, (int)isDarkBackground);
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || !feasible || seed == nil) {
            [strongSelf ame429_pushOverlay:nil];
            return;
        }
        [strongSelf ame429_pushOverlay:[strongSelf ame429_tokenMapWithSeed:seed]];
    }];
}

#pragma mark - CUSTOM 种子解析（含 accent_color 断链修复）

// CUSTOM 种子链：general.custom_seed_color → 旧 general.accent_color
//（断链修复：旧自定义三色 accent_color 只被旧页消费、ZL2Theme 不读；
// CUSTOM 模式未选新种子时经本回落贯通 ZL2 全页面）→ 默认蓝字面量。
- (nullable UIColor *)ame429_customSeedColor {
    NSString *hex = [self ame429_nonEmptyString:getPrefObject(Ame429KeyCustomSeedColor)];
    if (hex == nil) {
        // 断链修复：读旧偏好（LauncherPreferences 只读 API getPrefObject，文件禁改）
        hex = [self ame429_nonEmptyString:getPrefObject(Ame429LegacyAccentColorKey)];
    }
    if (hex == nil) {
        hex = ACCENT_COLOR_DEFAULT_HEX;   // LauncherPreferences.h 判例默认蓝 #429CF5
    }
    return [self ame429_colorFromHexString:hex];
}

- (nullable NSString *)ame429_nonEmptyString:(id)value {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    return (s.length > 0) ? s : nil;
}

// "#RRGGBB"/"RRGGBB" hex 串解析（非法回落 nil；与 ZL2Theme AmePluginParseHex 同族）
- (nullable UIColor *)ame429_colorFromHexString:(NSString *)hex {
    if (hex == nil) return nil;
    NSString *s = hex;
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return nil;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < s.length; i++) {
        if (![ok characterIsMember:[s characterAtIndex:i]]) return nil;
    }
    unsigned long long v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    [sc scanHexLongLong:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:1.0];
}

// 预设种子 int → UIColor
- (nullable UIColor *)ame429_colorFromHexInt:(int)hex {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

@end
