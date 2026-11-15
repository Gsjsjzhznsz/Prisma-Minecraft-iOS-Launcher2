//
// AmeHCTPalette.m — ★Task429（PDF 第五版 §8.1）HCT 简化实现 + M3 角色表
//
// 角色表口径（M3 官方 tone 刻度，与 Compose dynamicLightColorScheme/
// dynamicDarkColorScheme 同构）：
//
//   角色                  浅色态           深色态
//   primary              主板 tone 40     主板 tone 80
//   onPrimary            100              20
//   primaryContainer     90               30
//   onPrimaryContainer   10               90
//   secondary 系         次板 40/100/90/10   次板 80/20/30/90
//   tertiary 系          三板 40/100/90/10   三板 80/20/30/90
//   surface              中性板 98        中性板 6
//   onSurface            10               90
//   onSurfaceVariant     变体板 30        变体板 80
//   surfaceVariant       变体板 90        变体板 30
//   surfaceContainer*    100/96/94/92/90  4/10/12/17/22
//   surfaceBright        98               24（ZL2 cardColor() 深态卡底）
//   outline              变体板 50        变体板 60
//   outlineVariant       变体板 80        变体板 30
//   error/errorContainer/success/warning  静态基线（M3 无动态 error 色板，
//                                          embermire 现值沿用 = 状态色不随板漂）
//

#import "AmeHCTPalette.h"

#import <math.h>

#pragma mark - 常量实名表（★Task429）

// PaletteStyle 三档色度缩放系数（自然/鲜活/柔和）
static const CGFloat Ame429ChromaScaleNatural = 1.00;
static const CGFloat Ame429ChromaScaleVivid   = 1.40;
static const CGFloat Ame429ChromaScaleSoft    = 0.60;

// 五条板色度定式（种子色度 → 板色度；区间为 M3 动态方案代理近似）
static const CGFloat Ame429PrimaryChromaFloor   = 48.0;   // 主板：种子色度过低时顶到 M3 观感下限
static const CGFloat Ame429PrimaryChromaCap     = 120.0;
static const CGFloat Ame429SecondaryChromaScale = 0.50;
static const CGFloat Ame429SecondaryChromaMin   = 12.0;
static const CGFloat Ame429SecondaryChromaMax   = 40.0;
static const CGFloat Ame429TertiaryChromaScale  = 0.55;
static const CGFloat Ame429TertiaryChromaMin    = 20.0;
static const CGFloat Ame429TertiaryChromaMax    = 64.0;
static const CGFloat Ame429TertiaryHueRotation  = 60.0;   // 三板色相 = 种子 + 60°（M3 同族角程近似）
static const CGFloat Ame429NeutralChromaBase    = 6.0;    // 中性板（surface 族）
static const CGFloat Ame429NeutralVariantChromaBase = 12.0; // 变体板（outline/variant 族）
static const CGFloat Ame429NeutralChromaFloor   = 2.0;

// HSB 亮度二分搜索（tone 呈现）迭代次数与亮阶饱和度收缩上限
static const NSInteger Ame429ToneBisectSteps = 40;
static const NSInteger Ame429SatShrinkMaxRetries = 24;

// 状态色静态基线（浅/深，与 ZL2Theme embermire 现值逐位一致）
static const int Ame429StaticErrorLight            = 0xBA1A1A;
static const int Ame429StaticErrorDark             = 0xFFB4AB;
static const int Ame429StaticErrorContainerLight   = 0xFFDAD6;
static const int Ame429StaticErrorContainerDark    = 0x93000A;
static const int Ame429StaticSuccessLight          = 0x146C2E;
static const int Ame429StaticSuccessDark           = 0x6DD58C;
static const int Ame429StaticWarningLight          = 0x8F4C38;
static const int Ame429StaticWarningDark           = 0xFFB693;

#pragma mark - HSB 单通道换算

// HSB → 单通道（hueDeg 度、s/v 0...1、channel 0=r 1=g 2=b）
static CGFloat Ame429HueChannel(CGFloat hueDeg, CGFloat s, CGFloat v, NSInteger channel) {
    CGFloat hh = hueDeg / 60.0;
    NSInteger sector = (NSInteger)floor(hh);
    CGFloat frac = hh - (CGFloat)sector;
    CGFloat p = v * (1.0 - s);
    CGFloat q = v * (1.0 - s * frac);
    CGFloat t = v * (1.0 - s * (1.0 - frac));
    CGFloat r = v, g = v, b = v;
    switch (((sector % 6) + 6) % 6) {
        case 0: r = v; g = t; b = p; break;
        case 1: r = q; g = v; b = p; break;
        case 2: r = p; g = v; b = t; break;
        case 3: r = p; g = q; b = v; break;
        case 4: r = t; g = p; b = v; break;
        default: r = v; g = p; b = q; break;
    }
    if (channel == 0) return r;
    if (channel == 1) return g;
    return b;
}

#pragma mark - 色度数学（sRGB 线性化 ↔ CIE L*）

// sRGB 传递函数（IEC 61966-2-1 EOTF）
static CGFloat Ame429LinearFromSRGB(CGFloat c) {
    if (c <= 0.04045) return c / 12.92;
    return pow((c + 0.055) / 1.055, 2.4);
}

// Rec.709 相对亮度 Y（0...1）
static CGFloat Ame429RelativeLuminance(CGFloat r, CGFloat g, CGFloat b) {
    return 0.2126 * Ame429LinearFromSRGB(r)
         + 0.7152 * Ame429LinearFromSRGB(g)
         + 0.0722 * Ame429LinearFromSRGB(b);
}

// CIE L*（tone）→ 相对亮度 Y
static CGFloat Ame429YFromTone(CGFloat tone) {
    CGFloat t = MAX(0.0, MIN(100.0, tone));
    if (t <= 8.0) return t / 903.3;
    return pow((t + 16.0) / 116.0, 3.0);
}

// 固定色相/饱和度下命中目标亮度的 HSB 亮度（二分；Y(v) 单调递增）。
// 无解（目标 Y 超过该色相/饱和度可达上限）返回 -1。
// ★ 传参口径：Ame429HueChannel 产出的是 sRGB 原值（0...1），线性化由
//   Ame429RelativeLuminance 内部承担——勿在调用侧预线性化（双重 EOTF
//   会把暗阶整体推亮一个量级，Python 自评时曾中此雷）。
static CGFloat Ame429BrightnessForTargetY(CGFloat hueDeg, CGFloat sat, CGFloat targetY) {
    CGFloat yMax = Ame429RelativeLuminance(Ame429HueChannel(hueDeg, sat, 1.0, 0),
                                           Ame429HueChannel(hueDeg, sat, 1.0, 1),
                                           Ame429HueChannel(hueDeg, sat, 1.0, 2));
    if (targetY > yMax) return -1.0;
    CGFloat lo = 0.0, hi = 1.0;
    for (NSInteger i = 0; i < Ame429ToneBisectSteps; i++) {
        CGFloat mid = (lo + hi) * 0.5;
        CGFloat yMid = Ame429RelativeLuminance(Ame429HueChannel(hueDeg, sat, mid, 0),
                                               Ame429HueChannel(hueDeg, sat, mid, 1),
                                               Ame429HueChannel(hueDeg, sat, mid, 2));
        if (yMid < targetY) lo = mid; else hi = mid;
    }
    return (lo + hi) * 0.5;
}

// 固定色相/色度代理下命中 tone 的颜色（亮阶可承载色度不足时收缩饱和度重试）
static UIColor *Ame429ColorForTone(CGFloat hueDeg, CGFloat chroma, CGFloat tone) {
    CGFloat targetY = Ame429YFromTone(tone);
    CGFloat sat = MAX(0.0, MIN(1.0, chroma / 100.0));
    CGFloat v = -1.0;
    NSInteger retries = 0;
    while (retries < Ame429SatShrinkMaxRetries) {
        v = Ame429BrightnessForTargetY(hueDeg, sat, targetY);
        if (v >= 0.0) break;
        sat *= 0.9;   // 亮/暗阶可达色度收缩（HCT 色度衰减代理）
        if (sat < 0.004) { sat = 0.0; break; }
        retries++;
    }
    if (v < 0.0) {
        // sat=0（灰阶）时全亮度域可达——按目标 Y 反推 gamma 亮度兜底
        v = MAX(0.0, MIN(1.0, pow(targetY, 1.0 / 2.2)));
    }
    if (sat <= 0.0) {
        return [UIColor colorWithWhite:v alpha:1.0];
    }
    return [UIColor colorWithRed:Ame429HueChannel(hueDeg, sat, v, 0)
                           green:Ame429HueChannel(hueDeg, sat, v, 1)
                            blue:Ame429HueChannel(hueDeg, sat, v, 2)
                           alpha:1.0];
}

#pragma mark - AmeHCTTonalPalette

@implementation AmeHCTTonalPalette

+ (instancetype)ame429_paletteWithHue:(CGFloat)hue chroma:(CGFloat)chroma {
    return [[self alloc] ame429_initWithHue:hue chroma:chroma];
}

- (instancetype)ame429_initWithHue:(CGFloat)hue chroma:(CGFloat)chroma {
    self = [super init];
    if (self) {
        // 色相归一 0...360（fmod 负数修正）；色度 clamp 0...120
        _hue = fmod(fmod(hue, 360.0) + 360.0, 360.0);
        _chroma = MAX(0.0, MIN(120.0, chroma));
    }
    return self;
}

- (UIColor *)ame429_colorAtTone:(CGFloat)tone {
    return Ame429ColorForTone(self.hue, self.chroma, tone);
}

@end

#pragma mark - AmeHCTPalette

@interface AmeHCTPalette ()
@property (nonatomic, readwrite, strong) UIColor *seed;
@property (nonatomic, strong) AmeHCTTonalPalette *primaryPalette;
@property (nonatomic, strong) AmeHCTTonalPalette *secondaryPalette;
@property (nonatomic, strong) AmeHCTTonalPalette *tertiaryPalette;
@property (nonatomic, strong) AmeHCTTonalPalette *neutralPalette;
@property (nonatomic, strong) AmeHCTTonalPalette *neutralVariantPalette;
@end

@implementation AmeHCTPalette

+ (instancetype)ame429_paletteWithSeed:(UIColor *)seed
                                 style:(AmeHCTPaletteStyle)style {
    return [[self alloc] ame429_initWithSeed:seed style:style];
}

- (instancetype)ame429_initWithSeed:(UIColor *)seed style:(AmeHCTPaletteStyle)style {
    self = [super init];
    if (self) {
        UIColor *safeSeed = seed ?: [UIColor colorWithRed:0.43 green:0.23 blue:0.09 alpha:1.0]; // embermire 主棕兜底
        _seed = safeSeed;
        CGFloat hue = 0.0, sat = 0.0, bright = 0.0, alpha = 0.0;
        if (![safeSeed getHue:&hue saturation:&sat brightness:&bright alpha:&alpha]) {
            hue = 0.0; sat = 0.0;
        }
        CGFloat seedHue = hue * 360.0;
        // 色度代理（HSB 饱和度 × 亮度感知系数 × 100，见 .h 简化说明）：
        // 纯 sat×100 在高亮种子上系统性偏高（HCT 色度随明度近白端衰减），
        // 乘 (0.55 + 0.45×bright) 后与种子真实 HCT 色度显著对齐
        //（校准样本：embermire 主棕 0xA63A17 → 代理 ≈72，实测 HCT 色度 ≈70）
        CGFloat seedChroma = sat * (0.55 + 0.45 * bright) * 100.0;

        // 风格色度缩放（常量实名表）
        CGFloat scale = Ame429ChromaScaleNatural;
        if (style == AmeHCTPaletteStyleVivid) scale = Ame429ChromaScaleVivid;
        if (style == AmeHCTPaletteStyleSoft)  scale = Ame429ChromaScaleSoft;

        _primaryPalette = [AmeHCTTonalPalette
            ame429_paletteWithHue:seedHue
                          chroma:MIN(MAX(MAX(seedChroma, Ame429PrimaryChromaFloor) * scale, 4.0),
                                     Ame429PrimaryChromaCap)];
        _secondaryPalette = [AmeHCTTonalPalette
            ame429_paletteWithHue:seedHue
                          chroma:MIN(MAX(seedChroma * Ame429SecondaryChromaScale * scale,
                                         Ame429SecondaryChromaMin),
                                     Ame429SecondaryChromaMax)];
        _tertiaryPalette = [AmeHCTTonalPalette
            ame429_paletteWithHue:seedHue + Ame429TertiaryHueRotation
                          chroma:MIN(MAX(seedChroma * Ame429TertiaryChromaScale * scale,
                                         Ame429TertiaryChromaMin),
                                     Ame429TertiaryChromaMax)];
        _neutralPalette = [AmeHCTTonalPalette
            ame429_paletteWithHue:seedHue
                          chroma:MAX(Ame429NeutralChromaBase * scale, Ame429NeutralChromaFloor)];
        _neutralVariantPalette = [AmeHCTTonalPalette
            ame429_paletteWithHue:seedHue
                          chroma:MAX(Ame429NeutralVariantChromaBase * scale, Ame429NeutralChromaFloor)];
    }
    return self;
}

// 单条板 → @[浅 hexInt, 深 hexInt]
+ (NSArray<NSNumber *> *)ame429_pair:(AmeHCTTonalPalette *)palette
                          lightTone:(CGFloat)lightTone
                           darkTone:(CGFloat)darkTone {
    UIColor *lightColor = [palette ame429_colorAtTone:lightTone];
    UIColor *darkColor  = [palette ame429_colorAtTone:darkTone];
    CGFloat lr = 0, lg = 0, lb = 0, la = 0;
    CGFloat dr = 0, dg = 0, db = 0, da = 0;
    [lightColor getRed:&lr green:&lg blue:&lb alpha:&la];
    [darkColor  getRed:&dr green:&dg blue:&db alpha:&da];
    int lightHex = (int)(round(lr * 255.0) * 65536 + round(lg * 255.0) * 256 + round(lb * 255.0));
    int darkHex  = (int)(round(dr * 255.0) * 65536 + round(dg * 255.0) * 256 + round(db * 255.0));
    return @[@(lightHex), @(darkHex)];
}

// 静态基线状态色 → @[浅 hexInt, 深 hexInt]
+ (NSArray<NSNumber *> *)ame429_staticPairLight:(int)light dark:(int)dark {
    return @[@(light), @(dark)];
}

- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)ame429_tokenMap {
    AmeHCTTonalPalette *P  = self.primaryPalette;
    AmeHCTTonalPalette *S  = self.secondaryPalette;
    AmeHCTTonalPalette *T  = self.tertiaryPalette;
    AmeHCTTonalPalette *N  = self.neutralPalette;
    AmeHCTTonalPalette *NV = self.neutralVariantPalette;

    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *map =
        [NSMutableDictionary dictionary];

    // 主色系
    map[@"primary"]            = [AmeHCTPalette ame429_pair:P lightTone:40 darkTone:80];
    map[@"onPrimary"]          = [AmeHCTPalette ame429_pair:P lightTone:100 darkTone:20];
    map[@"primaryContainer"]   = [AmeHCTPalette ame429_pair:P lightTone:90 darkTone:30];
    map[@"onPrimaryContainer"] = [AmeHCTPalette ame429_pair:P lightTone:10 darkTone:90];

    // 次色系
    map[@"secondary"]              = [AmeHCTPalette ame429_pair:S lightTone:40 darkTone:80];
    map[@"onSecondary"]            = [AmeHCTPalette ame429_pair:S lightTone:100 darkTone:20];
    map[@"secondaryContainer"]     = [AmeHCTPalette ame429_pair:S lightTone:90 darkTone:30];
    map[@"onSecondaryContainer"]   = [AmeHCTPalette ame429_pair:S lightTone:10 darkTone:90];

    // 三色系
    map[@"tertiary"]              = [AmeHCTPalette ame429_pair:T lightTone:40 darkTone:80];
    map[@"onTertiary"]            = [AmeHCTPalette ame429_pair:T lightTone:100 darkTone:20];
    map[@"tertiaryContainer"]     = [AmeHCTPalette ame429_pair:T lightTone:90 darkTone:30];
    map[@"onTertiaryContainer"]   = [AmeHCTPalette ame429_pair:T lightTone:10 darkTone:90];

    // 表面系（中性板 / 变体板；surfaceBright 深 = ZL2 cardColor() 卡底）
    map[@"surface"]                   = [AmeHCTPalette ame429_pair:N lightTone:98 darkTone:6];
    map[@"onSurface"]                 = [AmeHCTPalette ame429_pair:N lightTone:10 darkTone:90];
    map[@"onSurfaceVariant"]          = [AmeHCTPalette ame429_pair:NV lightTone:30 darkTone:80];
    map[@"surfaceVariant"]            = [AmeHCTPalette ame429_pair:NV lightTone:90 darkTone:30];
    map[@"surfaceContainerLowest"]    = [AmeHCTPalette ame429_pair:N lightTone:100 darkTone:4];
    map[@"surfaceContainerLow"]       = [AmeHCTPalette ame429_pair:N lightTone:96 darkTone:10];
    map[@"surfaceContainer"]          = [AmeHCTPalette ame429_pair:N lightTone:94 darkTone:12];
    map[@"surfaceContainerHigh"]      = [AmeHCTPalette ame429_pair:N lightTone:92 darkTone:17];
    map[@"surfaceContainerHighest"]   = [AmeHCTPalette ame429_pair:N lightTone:90 darkTone:22];
    map[@"surfaceBright"]             = [AmeHCTPalette ame429_pair:N lightTone:98 darkTone:24];

    // 描边系
    map[@"outline"]          = [AmeHCTPalette ame429_pair:NV lightTone:50 darkTone:60];
    map[@"outlineVariant"]   = [AmeHCTPalette ame429_pair:NV lightTone:80 darkTone:30];

    // 状态系（静态基线：M3 无动态 error 色板，embermire 现值沿用）
    map[@"error"]           = [AmeHCTPalette ame429_staticPairLight:Ame429StaticErrorLight dark:Ame429StaticErrorDark];
    map[@"errorContainer"]  = [AmeHCTPalette ame429_staticPairLight:Ame429StaticErrorContainerLight dark:Ame429StaticErrorContainerDark];
    map[@"success"]         = [AmeHCTPalette ame429_staticPairLight:Ame429StaticSuccessLight dark:Ame429StaticSuccessDark];
    map[@"warning"]         = [AmeHCTPalette ame429_staticPairLight:Ame429StaticWarningLight dark:Ame429StaticWarningDark];

    return [map copy];
}

// 预览三色（浅色态）：主 tone40 / 主容器 tone90 / 三色容器 tone90
- (NSArray<UIColor *> *)ame429_previewLightColors {
    UIColor *primary40   = [self.primaryPalette ame429_colorAtTone:40];
    UIColor *container90 = [self.primaryPalette ame429_colorAtTone:90];
    UIColor *tertiary90  = [self.tertiaryPalette ame429_colorAtTone:90];
    return @[primary40, container90, tertiary90];
}

@end
