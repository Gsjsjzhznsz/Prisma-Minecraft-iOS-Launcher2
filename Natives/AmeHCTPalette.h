//
// AmeHCTPalette.h — ★Task429（PDF 第五版 §8.1）HCT 色域整套 M3 色板生成
//
// 种子色 → ZL2Theme 全部色值角色的深浅两态 token 映射（28 枚角色 × 浅/深）。
//
// 【简化说明】完整 HCT（CAM16 色度 + CIELAB 色调/明度）依赖 CAM16-XYZ 双向
// 矩阵链；本实现为「poor man's HCT」——
//   · 色相 H：直接取种子 HSB 色相（HCT 色相在常规色域内与 HSB 色相单调
//     对应，色相正确 = 视觉主基调正确）；
//   · 色度 C：以 HSB 饱和度 × 亮度感知系数 × 100 为代理
//     （sat×(0.55+0.45×bright)——HCT 色度随明度近白端衰减的近似；校准
//     样本 embermire 主棕 0xA63A17 → 代理 ≈72 vs 实测 HCT 色度 ≈70）；
//   · 色调 T（tone）：严格 CIE L*（Rec.709 线性化相对亮度 → L*），tonal
//     阶的明暗节奏与 M3 官方刻度逐档对齐（M3 角色表即按 tone 取色）。
//   每档 tone 的呈现：固定色相/饱和度下对 HSB 亮度二分搜索命中目标 L*
//   （亮度单调 → 二分稳定收敛；亮阶处可承载色度不足时收缩饱和度重试）。
//   视觉验收口径：色相正确 + 深浅阶分明 + 角色对比度可用（任务书裁定线）。
//
// PaletteStyle 三档（调色风格）：自然/鲜活/柔和 = 全板色度缩放系数
// （1.0 / 1.4 / 0.6），与 M3 DynamicScheme 的 chroma 调节同构。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 调色风格三档（色度缩放系数见 .m 常量实名表）
typedef NS_ENUM(NSInteger, AmeHCTPaletteStyle) {
    AmeHCTPaletteStyleNatural = 0,   // 自然（默认，色度 1.0x）
    AmeHCTPaletteStyleVivid   = 1,   // 鲜活（色度 1.4x）
    AmeHCTPaletteStyleSoft    = 2,   // 柔和（色度 0.6x）
};

#pragma mark - 单条 Tonal Palette（固定色相 + 色度，按 tone 取色）

@interface AmeHCTTonalPalette : NSObject

@property (nonatomic, readonly, assign) CGFloat hue;     // 色相（度，0...360）
@property (nonatomic, readonly, assign) CGFloat chroma;  // 色度代理（0...120）

+ (instancetype)ame429_paletteWithHue:(CGFloat)hue chroma:(CGFloat)chroma;

// tone = CIE L*（0...100）。同色相/色度下命中该明度的颜色。
- (UIColor *)ame429_colorAtTone:(CGFloat)tone;

@end

#pragma mark - 整套 M3 色板（种子 → 28 角色 × 浅/深）

@interface AmeHCTPalette : NSObject

// 由种子色与调色风格生成整套色板（纯 CPU 数学，毫秒级，任意线程可调）。
+ (instancetype)ame429_paletteWithSeed:(UIColor *)seed
                                 style:(AmeHCTPaletteStyle)style;

// ZL2Theme 全部色值角色的深浅两态映射：
//   token 名（@"primary"/@"onPrimary"/... 同 ZL2Theme.m 白名单）
//   → @[浅色态 hexInt, 深色态 hexInt]（NSNumber）。
// 消费方 ZL2DynamicPalette 原样推送进 ZL2Theme 活动覆盖层。
- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)ame429_tokenMap;

// 预览三色（浅色态 UIColor）：主 tone40 / 主容器 tone90 / 三色容器 tone90
// ——ZL2ThemeCustomSheet 实时预览三色块消费。
- (NSArray<UIColor *> *)ame429_previewLightColors;

// 种子色访问（预览/日志用）
@property (nonatomic, readonly, strong) UIColor *seed;

@end

NS_ASSUME_NONNULL_END
