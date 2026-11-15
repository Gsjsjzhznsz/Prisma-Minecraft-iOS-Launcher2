//
// AmeUIImageColors.h — ★Task429（PDF 第五版 §8.1）UIImage 主色提取
//
// 经典 UIImageColors（jathu/UIImageColors，MIT）的纯 ObjC 移植：输入一张
// （已降采样的）UIImage，输出 背景/主/次/细节 四色 + 深色底判定 +
// 可行性布尔。iOS 无 Monet/Material You，「跟随背景」动态主题的取色源
// ——上游算法语义逐段对齐原实现（亮度/饱和度分桶 → 计数聚类 → 桶序
// 取色 + 对比度兜底），仅做三处工程化调整（见 .m 顶部移植注记）。
//
// 消费方：ZL2DynamicPalette（§8.1 取色 → AmeHCTPalette 色板生成）。
// 线程约定：同步入口在调用线程执行（纯 CPU 数学，无 UIKit 主线程依赖），
// 异步入口固定派发到后台 utility 队列、结果回主线程——ZL2DynamicPalette
// 统一走异步入口（后台取色契约）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 取色结果（四色 + 可行性 + 深色底判定）
typedef void (^AmeUIImageColorsResultBlock)(UIColor * _Nullable background,
                                            UIColor * _Nullable primary,
                                            UIColor * _Nullable secondary,
                                            UIColor * _Nullable detail,
                                            BOOL feasible,
                                            BOOL isDarkBackground);

@interface AmeUIImageColors : NSObject

// 提取产物（未执行/不可行时为 nil）
@property (nonatomic, readonly, nullable) UIColor *background;   // 背景主色（最暗显著桶）
@property (nonatomic, readonly, nullable) UIColor *primary;      // 主色（最高计数桶）
@property (nonatomic, readonly, nullable) UIColor *secondary;    // 次色（色相/亮度距主色足够远）
@property (nonatomic, readonly, nullable) UIColor *detail;       // 细节色（距主/次色足够远）
@property (nonatomic, readonly, assign) BOOL isDarkBackground;   // 背景是否深色（亮度判定）
@property (nonatomic, readonly, assign) BOOL feasible;           // 是否取到有效四色

// 同步提取（调用线程执行；image 内部先降采样到 maxPixel 上限再聚类）。
// maxPixel <= 0 时取默认 128（聚类输入语义分辨率，与原算法 25% 缩放同族）。
- (BOOL)ame429_extractFromImage:(UIImage *)image maxPixel:(NSInteger)maxPixel;

// 异步提取（后台 utility 队列执行，结果块回主线程）。
+ (void)ame429_extractFromImage:(UIImage *)image
                       maxPixel:(NSInteger)maxPixel
                     completion:(AmeUIImageColorsResultBlock)completion;

@end

NS_ASSUME_NONNULL_END
