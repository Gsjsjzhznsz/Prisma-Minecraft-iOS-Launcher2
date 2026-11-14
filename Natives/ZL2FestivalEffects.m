//
//  ZL2FestivalEffects.m
//  Amethyst
//
//  ★Task428（报告 8.2 节日彩蛋复活）：iOS 原生手段对齐 ZL2 上游 FestivalEffects。
//   ① todayFestivalKey：十五条问候文案实际落表 i18n_str_324~340（17 键，
//     报告口径「325~339」为行号漂移前的旧区间——以 zh-Hans 表 1207-1223 行
//     实际内容为准逐键对号：元旦/清明/劳动/六一/教师/国庆/平安夜/圣诞 +
//     春节初一~初三/元宵/端午/七夕/中秋/重阳/除夕，未编造表外节日）；
//   ② 粒子引擎：CAEmitterLayer 六类预设（雪/雨/烟花/萤火/爱心/蝙蝠），
//     全部贴图 CoreGraphics 自绘（零 SF Symbols）；emitterShape 只用
//     kCAEmitterLayerPoint / kCAEmitterLayerLine（Task426 CI 判例：Rect
//     常量不存在）；烟花 = CADisplayLink 周期调度「底部升空 → 顶点爆开」
//     两相位双链轮转；
//   ③ 挂载：window 顶层全屏覆盖；hitTest 全透传不拦截下方交互，点击爆发
//     经 window 级 UITapGestureRecognizer（cancelsTouchesInView=NO）；
//   ④ 开关门：general.festival_effects（BOOL 默认 YES，键缺省视为开）。
//
//  粒子量克制（雪≈140 / 雨≈50 / 萤火≈45 / 爱心≈35 / 蝙蝠≈25 / 烟花每发
//  ≈30 火花低频 1.6~3.2s 一发），深浅色两态配色自适配保证可见性。
//

#import "ZL2FestivalEffects.h"
#import "ZL2Theme.h"
#import "LauncherPreferences.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

// ★Task428：开关门偏好键（getPrefObject 缺键返回 nil → 视为默认开）
static NSString *const kAme428PrefFestivalEffects = @"general.festival_effects";

#pragma mark - 形状贴图（CoreGraphics 自绘白模，颜色经 cell.color 乘法着色）

/// 柔边圆点（雪/萤火/烟花火花）：中心实、边缘径向淡出
static UIImage *ZL2FestivalDotImage(CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGFloat cx = side / 2.0, cy = side / 2.0;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        // 白模（中心不透明 → 边缘透明），运行色由 CAEmitterCell.color 乘法叠加
        CGFloat comps[8] = {1.0, 1.0, 1.0, 0.98, 1.0, 1.0, 1.0, 0.0};
        CGFloat locs[2] = {0.0, 1.0};
        CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
        CGContextDrawRadialGradient(ctx, grad, CGPointMake(cx, cy), 0.5,
                                    CGPointMake(cx, cy), side / 2.0,
                                    kCGGradientDrawsBeforeStartLocation);
        CGGradientRelease(grad);
        CGColorSpaceRelease(cs);
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

/// 竖向雨丝：细长条、上下端淡出
static UIImage *ZL2FestivalStreakImage(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(3.0, 20.0), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.95].CGColor);
        CGContextFillRect(ctx, CGRectMake(1.0, 2.5, 1.0, 15.0));
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.40].CGColor);
        CGContextFillRect(ctx, CGRectMake(1.0, 0.5, 1.0, 2.0));
        CGContextFillRect(ctx, CGRectMake(1.0, 17.5, 1.0, 2.0));
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

/// 心形：双圆 + 三角拼合（粒子小尺寸下读作心形即可，不追求矢量完美）
static UIImage *ZL2FestivalHeartImage(void) {
    CGFloat s = 20.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:1.0].CGColor);
        // 双圆（左右心室）
        CGContextFillEllipseInRect(ctx, CGRectMake(1.0, 1.8, 10.4, 10.4));
        CGContextFillEllipseInRect(ctx, CGRectMake(8.6, 1.8, 10.4, 10.4));
        // 三角（下坠心尖）
        CGContextMoveToPoint(ctx, 1.9, 8.6);
        CGContextAddLineToPoint(ctx, 18.1, 8.6);
        CGContextAddLineToPoint(ctx, 10.0, 18.6);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

/// 蝙蝠剪影：椭圆身 + 双侧翼弧 + 双耳（横向飘移小图标）
static UIImage *ZL2FestivalBatImage(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22.0, 16.0), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:1.0].CGColor);
        // 身体（椭圆）
        CGContextFillEllipseInRect(ctx, CGRectMake(8.6, 4.0, 4.8, 8.4));
        // 双耳
        CGContextFillEllipseInRect(ctx, CGRectMake(9.1, 2.6, 1.7, 3.0));
        CGContextFillEllipseInRect(ctx, CGRectMake(11.2, 2.6, 1.7, 3.0));
        // 左翼（两段弧线勾出膜翼轮廓）
        CGContextMoveToPoint(ctx, 9.4, 7.2);
        CGContextAddQuadCurveToPoint(ctx, 5.6, 6.2, 1.8, 3.4);   // 翼上缘（翼尖）
        CGContextAddQuadCurveToPoint(ctx, 5.0, 8.4, 8.8, 11.2);  // 翼下缘（膜弧）
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
        // 右翼（镜像）
        CGContextMoveToPoint(ctx, 12.6, 7.2);
        CGContextAddQuadCurveToPoint(ctx, 16.4, 6.2, 20.2, 3.4);
        CGContextAddQuadCurveToPoint(ctx, 17.0, 8.4, 13.2, 11.2);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

#pragma mark - 烟花链（火箭升空 → 顶点爆开两相位；双链轮转）

// ★Task428：火箭运动参数（与 eme428_tick 顶点解算严格同源）：
//   v0 = 520、a = -640 → 顶点时刻 t = 520/640 ≈ 0.81s，
//   上升距离 dy = 520t - 320t²（t=0.81 ≈ 211pt），飞行全程近似减速至顶点爆开。
static const CGFloat kAme428RocketVelocity = 520.0;
static const CGFloat kAme428RocketDecel = 640.0;
static const CGFloat kAme428RocketFlight = 0.81;
/// 爆开窗（秒）：仅此窗口内发射火花，随后 cells 置 nil，存量粒子继续飞完寿命
static const CFTimeInterval kAme428BurstWindow = 0.12;

@interface ZL2FestivalFireworkChain : NSObject
@property(nonatomic, strong) CAEmitterLayer *eme428_layer;
@property(nonatomic, strong) NSArray<CAEmitterCell *> *eme428_burstCells;
@property(nonatomic, assign) NSInteger eme428_phase;        // 0 空闲 / 1 火箭 / 2 爆开
@property(nonatomic, assign) CFTimeInterval eme428_phaseUntil;
@property(nonatomic, assign) CGFloat eme428_x;
@property(nonatomic, assign) CGFloat eme428_launchY;
- (void)eme428_launchAtX:(CGFloat)x launchY:(CGFloat)y color:(UIColor *)color now:(CFTimeInterval)now;
- (void)eme428_tick:(CFTimeInterval)now;
- (void)eme428_tearDown;
@end

@implementation ZL2FestivalFireworkChain

- (instancetype)init {
    self = [super init];
    if (self) {
        _eme428_layer = [CAEmitterLayer layer];
        _eme428_layer.emitterShape = kCAEmitterLayerPoint;   // 点位发射（合法 shape 常量）
        _eme428_phase = 0;
    }
    return self;
}

// 点火：火箭相位（birthRate=1 单弹 + 严格寿命 = 顶点时刻确定）
- (void)eme428_launchAtX:(CGFloat)x launchY:(CGFloat)y color:(UIColor *)color now:(CFTimeInterval)now {
    self.eme428_x = x;
    self.eme428_launchY = y;
    self.eme428_layer.emitterPosition = CGPointMake(x, y);

    CAEmitterCell *rocket = [CAEmitterCell emitterCell];
    rocket.contents = (id)ZL2FestivalDotImage(10.0).CGImage;
    rocket.birthRate = 1.0;                       // 单发火箭
    rocket.lifetime = kAme428RocketFlight;        // 寿命即飞行时长（顶点引爆）
    rocket.velocity = kAme428RocketVelocity;
    rocket.velocityRange = 0.0;                   // 零散布 = 顶点解算严格成立
    rocket.emissionLongitude = -M_PI / 2.0;       // 垂直向上
    rocket.yAcceleration = -kAme428RocketDecel;   // 持续减速 → 顶点近似静止
    rocket.scale = 0.42;
    rocket.scaleRange = 0.08;
    rocket.color = [UIColor colorWithRed:1.0 green:0.86 blue:0.58 alpha:0.95].CGColor;

    // 爆开 cell 组（顶点全向火花 + 近心亮核）
    CAEmitterCell *spark = [CAEmitterCell emitterCell];
    spark.contents = (id)ZL2FestivalDotImage(9.0).CGImage;
    spark.birthRate = 240.0;                      // 0.12s 窗口 ≈ 29 粒/发
    spark.lifetime = 1.35;
    spark.lifetimeRange = 0.45;
    spark.velocity = 140.0;
    spark.velocityRange = 110.0;
    spark.emissionRange = M_PI * 2.0;             // 全向爆开
    spark.yAcceleration = 95.0;                   // 重力下坠
    spark.scale = 0.55;
    spark.scaleRange = 0.30;
    spark.scaleSpeed = -0.28;                     // 火花渐小渐熄
    spark.alphaSpeed = -0.62;
    spark.color = color.CGColor;

    CAEmitterCell *core = [CAEmitterCell emitterCell];
    core.contents = (id)ZL2FestivalDotImage(9.0).CGImage;
    core.birthRate = 60.0;
    core.lifetime = 0.35;
    core.velocity = 26.0;
    core.velocityRange = 18.0;
    core.emissionRange = M_PI * 2.0;
    core.scale = 1.15;
    core.alphaSpeed = -1.8;                       // 亮核急熄
    core.color = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;

    self.eme428_burstCells = @[spark, core];
    self.eme428_layer.emitterCells = @[rocket];
    self.eme428_phase = 1;
    self.eme428_phaseUntil = now + kAme428RocketFlight;
}

- (void)eme428_tick:(CFTimeInterval)now {
    if (self.eme428_phase == 0 || now < self.eme428_phaseUntil) return;
    if (self.eme428_phase == 1) {
        // 火箭到位 → 顶点爆开（运动学与点火参数同源解算）
        CGFloat t = kAme428RocketFlight;
        CGFloat dy = kAme428RocketVelocity * t - 0.5 * kAme428RocketDecel * t * t;
        CGFloat apexY = self.eme428_launchY - dy;
        self.eme428_layer.emitterPosition = CGPointMake(self.eme428_x, apexY);
        self.eme428_layer.emitterCells = self.eme428_burstCells;
        self.eme428_phase = 2;
        self.eme428_phaseUntil = now + kAme428BurstWindow;
    } else {
        // 爆开窗结束 → 停发（存量火花继续飞完寿命）
        self.eme428_layer.emitterCells = nil;
        self.eme428_phase = 0;
    }
}

- (void)eme428_tearDown {
    self.eme428_layer.emitterCells = nil;
    [self.eme428_layer removeFromSuperlayer];
}

@end

#pragma mark - 粒子视图（窗口顶层全屏覆盖；hitTest 全透传）

@interface ZL2FestivalEffectsView : UIView
- (instancetype)eme428_initWithKind:(ZL2FestivalEffectKind)kind;
- (void)eme428_burstAtPoint:(CGPoint)point;   // 点击爆发（烟花/爱心/蝙蝠）
- (void)eme428_tap:(UITapGestureRecognizer *)gesture;
- (void)eme428_tearDown;
@end

@interface ZL2FestivalEffectsView ()
@property(nonatomic, assign) ZL2FestivalEffectKind eme428_kind;
@property(nonatomic, strong, nullable) CAEmitterLayer *eme428_ambientLayer;          // 常态层（雪/雨/萤火/爱心/蝙蝠）
@property(nonatomic, strong) NSArray<ZL2FestivalFireworkChain *> *eme428_chains;     // 烟花双链（轮转）
@property(nonatomic, strong, nullable) CAEmitterLayer *eme428_tapLayer;              // 点击爆发层（懒建）
@property(nonatomic, strong, nullable) CADisplayLink *eme428_displayLink;            // 烟花周期调度
@property(nonatomic, assign) CFTimeInterval eme428_nextLaunchAt;
@end

@implementation ZL2FestivalEffectsView

- (instancetype)eme428_initWithKind:(ZL2FestivalEffectKind)kind {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _eme428_kind = kind;
        self.backgroundColor = UIColor.clearColor;
        // 整体 YES：视图保持可交互语义；实际命中经 hitTest 全透传（见下），
        // 点击爆发由挂窗 UITapGestureRecognizer 接收（不拦截下方任何控件）。
        self.userInteractionEnabled = YES;

        if (kind == ZL2FestivalEffectFireworks) {
            ZL2FestivalFireworkChain *chainA = [[ZL2FestivalFireworkChain alloc] init];
            ZL2FestivalFireworkChain *chainB = [[ZL2FestivalFireworkChain alloc] init];
            _eme428_chains = @[chainA, chainB];
            [self.layer addSublayer:chainA.eme428_layer];
            [self.layer addSublayer:chainB.eme428_layer];
            // CADisplayLink 辅助调度：周期点火 + 两相位转换（NSRunLoopCommonModes
            // 保证滚动/交互期间烟花节拍不冻结）
            _eme428_displayLink = [CADisplayLink displayLinkWithTarget:self
                                                              selector:@selector(eme428_displayTick:)];
            [_eme428_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                                      forMode:NSRunLoopCommonModes];
            _eme428_nextLaunchAt = 0.0;   // 首发立即
        }
        [self eme428_applyPreset];
    }
    return self;
}

// ★Task428：全透传——本视图自身永不成为命中目标，下方按钮/滚动手势零影响；
// 点击爆发经 window 级 tap 手势（透明接收 = 手势挂在 window 上，与控件
// 触控并存，cancelsTouchesInView=NO 不吞事件）。
- (nullable UIView *)hitTest:(CGPoint)point withEvent:(nullable UIEvent *)event {
    return nil;
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection) return;
    if (self.traitCollection.userInterfaceStyle == previousTraitCollection.userInterfaceStyle) return;
    [self eme428_applyPreset];   // 深浅色翻转 → 粒子配色重建（两态都可见）
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (b.size.width < 8.0 || b.size.height < 8.0) return;
    if (self.eme428_ambientLayer) {
        self.eme428_ambientLayer.frame = b;
        [self eme428_layoutAmbientEmitter];
    }
    if (self.eme428_tapLayer) self.eme428_tapLayer.frame = b;
    for (ZL2FestivalFireworkChain *chain in self.eme428_chains) chain.eme428_layer.frame = b;
}

// 常态层发射几何（按种类：顶部横线 / 底部横线 / 左缘竖线 / 中部漂浮带）
- (void)eme428_layoutAmbientEmitter {
    CAEmitterLayer *layer = self.eme428_ambientLayer;
    if (!layer) return;
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    switch (self.eme428_kind) {
        case ZL2FestivalEffectSnow:
        case ZL2FestivalEffectRain:
            layer.emitterPosition = CGPointMake(w / 2.0, -14.0);
            layer.emitterSize = CGSizeMake(w * 0.96, 0.0);
            break;
        case ZL2FestivalEffectFirefly:
            layer.emitterPosition = CGPointMake(w / 2.0, h * 0.45);
            layer.emitterSize = CGSizeMake(w * 0.9, 0.0);
            break;
        case ZL2FestivalEffectHearts:
            layer.emitterPosition = CGPointMake(w / 2.0, h + 16.0);
            layer.emitterSize = CGSizeMake(w * 0.96, 0.0);
            break;
        case ZL2FestivalEffectBats:
            layer.emitterPosition = CGPointMake(-14.0, h * 0.38);
            layer.emitterSize = CGSizeMake(0.0, h * 0.6);
            break;
        default:
            break;
    }
}

- (BOOL)eme428_isDarkStyle {
    return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

// 预设装配（深浅两态配色；雪/雨/萤火/爱心/蝙蝠建常态层，烟花只走双链）
- (void)eme428_applyPreset {
    if (self.eme428_ambientLayer) {
        [self.eme428_ambientLayer removeFromSuperlayer];
        self.eme428_ambientLayer = nil;
    }
    if (self.eme428_kind == ZL2FestivalEffectFireworks) return;

    BOOL dark = [self eme428_isDarkStyle];
    NSMutableArray<CAEmitterCell *> *cells = [NSMutableArray array];
    switch (self.eme428_kind) {
        case ZL2FestivalEffectSnow: {
            // 雪：白色小圆缓落摆动（双 cell 反向横加速度 = 摆动感）
            UIColor *color = dark
                ? [UIColor colorWithWhite:1.0 alpha:0.95]
                : [UIColor colorWithRed:0.58 green:0.68 blue:0.82 alpha:0.95];
            for (NSNumber *xAcc in @[@18.0, @-18.0]) {
                CAEmitterCell *c = [CAEmitterCell emitterCell];
                c.contents = (id)ZL2FestivalDotImage(12.0).CGImage;
                c.birthRate = 7.0;                       // 双 cell 合计 ≈14/s
                c.lifetime = 9.0;                        // ≈8s 跨屏，存亡接近同周期
                c.lifetimeRange = 2.0;                   // 存量 ≈110（数百级内克制）
                c.velocity = 55.0;
                c.velocityRange = 28.0;
                c.emissionLongitude = M_PI / 2.0;        // 向下
                c.emissionLatitude = -0.35;              // 轻微内聚（ZL2SkinPreview 同款手法）
                c.emissionRange = 0.24;
                c.yAcceleration = 14.0;
                c.xAcceleration = xAcc.doubleValue;
                c.spinRange = 0.6;
                c.scale = 0.62;
                c.scaleRange = 0.45;
                c.alphaSpeed = -0.012;                   // 缓慢淡出收尾
                c.color = color.CGColor;
                [cells addObject:c];
            }
            break;
        }
        case ZL2FestivalEffectRain: {
            // 雨：细长条快速下落（微风斜雨）
            UIColor *color = dark
                ? [UIColor colorWithRed:0.70 green:0.80 blue:0.95 alpha:0.72]
                : [UIColor colorWithRed:0.40 green:0.50 blue:0.66 alpha:0.78];
            CAEmitterCell *c = [CAEmitterCell emitterCell];
            c.contents = (id)ZL2FestivalStreakImage().CGImage;
            c.birthRate = 34.0;                          // 存量 ≈40
            c.lifetime = 1.2;
            c.lifetimeRange = 0.2;
            c.velocity = 900.0;
            c.velocityRange = 120.0;
            c.emissionLongitude = M_PI / 2.0;
            c.emissionRange = 0.035;                     // 近乎垂直
            c.yAcceleration = 260.0;
            c.xAcceleration = -12.0;                     // 微风斜雨
            c.scale = 1.0;
            c.scaleRange = 0.3;
            c.color = color.CGColor;
            [cells addObject:c];
            break;
        }
        case ZL2FestivalEffectFirefly: {
            // 萤火：黄绿小点闪烁漂浮（alphaRange 起相随机 + alphaSpeed 渐熄 = 闪烁）
            UIColor *color = dark
                ? [UIColor colorWithRed:0.84 green:1.0 blue:0.48 alpha:1.0]
                : [UIColor colorWithRed:0.62 green:0.86 blue:0.25 alpha:1.0];
            for (NSNumber *yAcc in @[@7.0, @-7.0]) {
                CAEmitterCell *c = [CAEmitterCell emitterCell];
                c.contents = (id)ZL2FestivalDotImage(9.0).CGImage;
                c.birthRate = 3.0;                       // 双 cell 存量 ≈45
                c.lifetime = 6.5;
                c.lifetimeRange = 1.8;
                c.velocity = 16.0;
                c.velocityRange = 14.0;
                c.emissionRange = M_PI * 2.0;            // 全向漂浮
                c.yAcceleration = yAcc.doubleValue;      // 上浮/下沉两族
                c.xAcceleration = (yAcc.doubleValue > 0) ? 10.0 : -10.0;
                c.scale = 0.55;
                c.scaleRange = 0.40;
                c.alphaRange = 0.55;                     // 起相随机
                c.alphaSpeed = -0.26;                    // 渐熄闪烁
                c.color = color.CGColor;
                [cells addObject:c];
            }
            break;
        }
        case ZL2FestivalEffectHearts: {
            // 爱心：红色小心形上浮（底部横线发射 + 双 cell 摆动）
            UIColor *color = dark
                ? [UIColor colorWithRed:1.0 green:0.40 blue:0.48 alpha:0.95]
                : [UIColor colorWithRed:0.93 green:0.25 blue:0.38 alpha:0.95];
            for (NSNumber *xAcc in @[@14.0, @-14.0]) {
                CAEmitterCell *c = [CAEmitterCell emitterCell];
                c.contents = (id)ZL2FestivalHeartImage().CGImage;
                c.birthRate = 1.5;                       // 双 cell 存量 ≈33
                c.lifetime = 11.0;
                c.lifetimeRange = 2.0;
                c.velocity = 70.0;
                c.velocityRange = 24.0;
                c.emissionLongitude = -M_PI / 2.0;       // 向上缓升
                c.emissionRange = 0.22;
                c.yAcceleration = -5.0;                  // 微弱升力（≈470pt 升程）
                c.xAcceleration = xAcc.doubleValue;      // 摆动
                c.spinRange = 0.8;
                c.scale = 0.60;
                c.scaleRange = 0.28;
                c.alphaSpeed = -0.06;                    // 升到高处渐隐
                c.color = color.CGColor;
                [cells addObject:c];
            }
            break;
        }
        case ZL2FestivalEffectBats: {
            // 蝙蝠：深色小图标横向飘移（左缘竖线发射，spinRange = 扑翼翻滚感）
            UIColor *color = dark
                ? [UIColor colorWithRed:0.82 green:0.82 blue:0.88 alpha:0.95]   // 深色态浅灰可见
                : [UIColor colorWithRed:0.14 green:0.14 blue:0.20 alpha:0.95];  // 浅色态近黑剪影
            for (NSNumber *yAcc in @[@12.0, @-12.0]) {
                CAEmitterCell *c = [CAEmitterCell emitterCell];
                c.contents = (id)ZL2FestivalBatImage().CGImage;
                c.birthRate = 0.8;                       // 双 cell 存量 ≈16
                c.lifetime = 11.0;
                c.lifetimeRange = 2.0;
                c.velocity = 62.0;
                c.velocityRange = 18.0;
                c.emissionLongitude = 0.0;               // 向右横漂
                c.emissionRange = 0.10;
                c.xAcceleration = 6.0;
                c.yAcceleration = yAcc.doubleValue;      // 上下摆动漂移
                c.spinRange = 1.5;
                c.scale = 0.60;
                c.scaleRange = 0.25;
                c.alphaSpeed = -0.03;                    // 漂远渐隐
                c.color = color.CGColor;
                [cells addObject:c];
            }
            break;
        }
        default:
            break;
    }
    if (cells.count > 0) {
        CAEmitterLayer *layer = [CAEmitterLayer layer];
        layer.emitterShape = kCAEmitterLayerLine;        // 合法 shape（Task426 判例同款）
        layer.frame = self.bounds;
        layer.emitterCells = cells;
        [self.layer addSublayer:layer];
        self.eme428_ambientLayer = layer;
        [self eme428_layoutAmbientEmitter];
    }
}

#pragma mark - 烟花周期调度（CADisplayLink）

- (void)eme428_displayTick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w > 80.0 && h > 200.0 && now >= self.eme428_nextLaunchAt) {
        // 挑链：优先空闲链，否则最早结束者
        ZL2FestivalFireworkChain *pick = nil;
        for (ZL2FestivalFireworkChain *chain in self.eme428_chains) {
            if (chain.eme428_phase == 0) { pick = chain; break; }
        }
        if (!pick) {
            pick = self.eme428_chains.firstObject;
            for (ZL2FestivalFireworkChain *chain in self.eme428_chains) {
                if (chain.eme428_phaseUntil < pick.eme428_phaseUntil) pick = chain;
            }
        }
        CGFloat x = 30.0 + (CGFloat)(arc4random_uniform((uint32_t)MAX(w - 60.0, 1.0)));
        [pick eme428_launchAtX:x launchY:h - 6.0
                         color:[self eme428_paletteColor] now:now];
        // 低频克制：1.6~3.2s 一发
        self.eme428_nextLaunchAt = now + 1.6 + (double)arc4random_uniform(1600) / 1000.0;
    }
    for (ZL2FestivalFireworkChain *chain in self.eme428_chains) {
        [chain eme428_tick:now];
    }
}

// 烟花色板（深浅两态同为高亮发光色，均可见）
- (UIColor *)eme428_paletteColor {
    NSArray<UIColor *> *palette = @[
        [UIColor colorWithRed:1.00 green:0.83 blue:0.42 alpha:1.0],   // 金
        [UIColor colorWithRed:1.00 green:0.38 blue:0.34 alpha:1.0],   // 绯红
        [UIColor colorWithRed:0.78 green:0.52 blue:1.00 alpha:1.0],   // 紫
        [UIColor colorWithRed:0.45 green:0.86 blue:1.00 alpha:1.0],   // 青
        [UIColor colorWithRed:1.00 green:0.97 blue:0.90 alpha:1.0],   // 月白
    ];
    return palette[arc4random_uniform((uint32_t)palette.count)];
}

#pragma mark - 点击爆发（烟花/爱心/蝙蝠）

- (void)eme428_tap:(UITapGestureRecognizer *)gesture {
    [self eme428_burstAtPoint:[gesture locationInView:self]];
}

- (void)eme428_burstAtPoint:(CGPoint)point {
    NSMutableArray<CAEmitterCell *> *cells = [NSMutableArray array];
    switch (self.eme428_kind) {
        case ZL2FestivalEffectFireworks: {
            // 点按即原地爆开一朵
            CAEmitterCell *spark = [CAEmitterCell emitterCell];
            spark.contents = (id)ZL2FestivalDotImage(9.0).CGImage;
            spark.birthRate = 300.0;
            spark.lifetime = 1.3;
            spark.lifetimeRange = 0.4;
            spark.velocity = 150.0;
            spark.velocityRange = 110.0;
            spark.emissionRange = M_PI * 2.0;
            spark.yAcceleration = 95.0;
            spark.scale = 0.55;
            spark.scaleRange = 0.3;
            spark.scaleSpeed = -0.28;
            spark.alphaSpeed = -0.62;
            spark.color = [self eme428_paletteColor].CGColor;
            [cells addObject:spark];
            break;
        }
        case ZL2FestivalEffectHearts: {
            // 点按爱心四散
            UIColor *color = [self eme428_isDarkStyle]
                ? [UIColor colorWithRed:1.0 green:0.40 blue:0.48 alpha:0.95]
                : [UIColor colorWithRed:0.93 green:0.25 blue:0.38 alpha:0.95];
            CAEmitterCell *c = [CAEmitterCell emitterCell];
            c.contents = (id)ZL2FestivalHeartImage().CGImage;
            c.birthRate = 90.0;
            c.lifetime = 1.4;
            c.lifetimeRange = 0.4;
            c.velocity = 130.0;
            c.velocityRange = 70.0;
            c.emissionRange = M_PI * 2.0;
            c.yAcceleration = 55.0;                      // 四散后微坠
            c.spinRange = 1.2;
            c.scale = 0.6;
            c.scaleRange = 0.3;
            c.alphaSpeed = -0.7;
            c.color = color.CGColor;
            [cells addObject:c];
            break;
        }
        case ZL2FestivalEffectBats: {
            // 点按蝙蝠惊飞
            UIColor *color = [self eme428_isDarkStyle]
                ? [UIColor colorWithRed:0.82 green:0.82 blue:0.88 alpha:0.95]
                : [UIColor colorWithRed:0.14 green:0.14 blue:0.20 alpha:0.95];
            CAEmitterCell *c = [CAEmitterCell emitterCell];
            c.contents = (id)ZL2FestivalBatImage().CGImage;
            c.birthRate = 26.0;
            c.lifetime = 1.5;
            c.lifetimeRange = 0.4;
            c.velocity = 150.0;
            c.velocityRange = 80.0;
            c.emissionRange = M_PI * 2.0;
            c.yAcceleration = 40.0;
            c.spinRange = 1.6;
            c.scale = 0.6;
            c.scaleRange = 0.25;
            c.alphaSpeed = -0.55;
            c.color = color.CGColor;
            [cells addObject:c];
            break;
        }
        default:
            return;   // 雪/雨/萤火无点击爆发
    }
    if (!self.eme428_tapLayer) {
        self.eme428_tapLayer = [CAEmitterLayer layer];
        self.eme428_tapLayer.emitterShape = kCAEmitterLayerPoint;
        self.eme428_tapLayer.frame = self.bounds;
        [self.layer addSublayer:self.eme428_tapLayer];
    }
    self.eme428_tapLayer.emitterPosition = point;
    self.eme428_tapLayer.emitterCells = cells;
    // 爆开窗后停发（存量粒子继续飞完寿命）
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAme428BurstWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.eme428_tapLayer) strongSelf.eme428_tapLayer.emitterCells = nil;
    });
}

- (void)eme428_tearDown {
    [self.eme428_displayLink invalidate];
    self.eme428_displayLink = nil;
    [self.eme428_ambientLayer removeFromSuperlayer];
    self.eme428_ambientLayer = nil;
    [self.eme428_tapLayer removeFromSuperlayer];
    self.eme428_tapLayer = nil;
    for (ZL2FestivalFireworkChain *chain in self.eme428_chains) [chain eme428_tearDown];
    self.eme428_chains = nil;
}

// CADisplayLink 会保留 target：正常路径 detach→tearDown 已断链；dealloc 兜底
// 防止窗口意外拆层时 mainRunLoop 持链泄漏（target 即本视图）。
- (void)dealloc {
    [self.eme428_displayLink invalidate];
}

@end

#pragma mark - 公开门面（挂载/摘除/节日判定）

static ZL2FestivalEffectsView *_Nullable sAme428AttachedView = nil;
static UITapGestureRecognizer *_Nullable sAme428TapGesture = nil;

@implementation ZL2FestivalEffects

// ★Task428：显式公历（避免系统日历非公历环境误判月/日）
static NSCalendar *_Nullable ZL2FestivalSolarCalendar(void) {
    static NSCalendar *cal = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        if (cal) cal.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return cal;
}

// ★Task428：农历（NSCalendarIdentifierChinese 取月/日；闰月歧义十年一遇且
// 最坏形态 = 多弹一天问候，彩蛋容错足够，不引入查表复杂度）
static NSCalendar *_Nullable ZL2FestivalLunarCalendar(void) {
    static NSCalendar *cal = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    });
    return cal;
}

+ (nullable NSString *)todayFestivalKey {
    NSDate *now = [NSDate date];
    NSCalendar *solar = ZL2FestivalSolarCalendar();
    if (solar) {
        NSDateComponents *g = [solar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
        NSString *solarKey = [NSString stringWithFormat:@"%ld-%ld", (long)g.month, (long)g.day];
        // 公历节日对号（表内实有：元旦/劳动/六一/教师/国庆/平安夜/圣诞）
        NSDictionary<NSString *, NSString *> *solarMap = @{
            @"1-1":   @"i18n_str_324",   // 元旦
            @"5-1":   @"i18n_str_326",   // 劳动节
            @"6-1":   @"i18n_str_327",   // 六一儿童节
            @"9-10":  @"i18n_str_328",   // 教师节
            @"10-1":  @"i18n_str_329",   // 国庆节
            @"12-24": @"i18n_str_330",   // 平安夜
            @"12-25": @"i18n_str_331",   // 圣诞节
        };
        NSString *hit = solarMap[solarKey];
        // 清明：节气年际漂移 ±1 天，用 4/4~4/6 近似窗口（任务口径）
        if (!hit && g.month == 4 && g.day >= 4 && g.day <= 6) hit = @"i18n_str_325";
        if (hit.length > 0) return hit;
    }

    NSCalendar *lunar = ZL2FestivalLunarCalendar();
    if (lunar) {
        NSDateComponents *l = [lunar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
        NSString *lunarKey = [NSString stringWithFormat:@"%ld-%ld", (long)l.month, (long)l.day];
        // 农历节日对号（表内实有：春节初一~初三/元宵/端午/七夕/中秋/重阳）
        NSDictionary<NSString *, NSString *> *lunarMap = @{
            @"1-1":  @"i18n_str_332",    // 春节（初一）
            @"1-2":  @"i18n_str_333",    // 新春（初二）
            @"1-3":  @"i18n_str_334",    // 新春（初三）
            @"1-15": @"i18n_str_335",    // 元宵节
            @"5-5":  @"i18n_str_336",    // 端午节
            @"7-7":  @"i18n_str_337",    // 七夕节
            @"8-15": @"i18n_str_338",    // 中秋节
            @"9-9":  @"i18n_str_339",    // 重阳节
        };
        NSString *hit = lunarMap[lunarKey];
        if (hit.length > 0) return hit;

        // 除夕：明日为农历正月初一（规避腊月大小月/闰腊月判定的稳健口径）
        NSCalendar *solarForTomorrow = ZL2FestivalSolarCalendar();
        if (solarForTomorrow) {
            NSDate *tomorrow = [solarForTomorrow dateByAddingUnit:NSCalendarUnitDay
                                                            value:1
                                                           toDate:now
                                                          options:0];
            NSDateComponents *tl = [lunar components:NSCalendarUnitMonth | NSCalendarUnitDay
                                             fromDate:tomorrow];
            if (tl.month == 1 && tl.day == 1) return @"i18n_str_340";
        }
    }
    return nil;
}

+ (ZL2FestivalEffectKind)effectKindForFestivalKey:(NSString *)festivalKey {
    // ★Task428 节日→效果映射（ZL2 口径 + 表内其余节日就近归档）：
    //   ZL2 原口径：圣诞/平安夜→雪、清明→雨、新年/春节/国庆→烟花、
    //   中秋→萤火、万圣→蝙蝠、情人节/七夕→爱心。
    //   表内就近归档：劳动节/元宵/除夕→烟花（庆典系）；端午→雨（华南端午
    //   「龙舟水」时令雨最贴语义）；重阳→萤火（秋夜登高赏菊、萤光点点）；
    //   六一→爱心（童趣暖意）、教师节→爱心（献礼玫瑰 🌹 语义）。
    //   万圣/情人节文案本地化表未覆盖 → 蝙蝠预设保留引擎侧待后续文案入表。
    if ([festivalKey isEqualToString:@"i18n_str_330"] ||
        [festivalKey isEqualToString:@"i18n_str_331"]) {
        return ZL2FestivalEffectSnow;        // 平安夜/圣诞节
    }
    if ([festivalKey isEqualToString:@"i18n_str_325"] ||
        [festivalKey isEqualToString:@"i18n_str_336"]) {
        return ZL2FestivalEffectRain;        // 清明 / 端午（龙舟水）
    }
    if ([festivalKey isEqualToString:@"i18n_str_338"] ||
        [festivalKey isEqualToString:@"i18n_str_339"]) {
        return ZL2FestivalEffectFirefly;     // 中秋 / 重阳
    }
    if ([festivalKey isEqualToString:@"i18n_str_327"] ||
        [festivalKey isEqualToString:@"i18n_str_328"] ||
        [festivalKey isEqualToString:@"i18n_str_337"]) {
        return ZL2FestivalEffectHearts;      // 六一 / 教师节 / 七夕
    }
    // 元旦/劳动节/国庆/春节初一~初三/元宵/除夕 → 烟花（庆典系）
    return ZL2FestivalEffectFireworks;
}

+ (void)attachToWindow:(nullable UIWindow *)window {
    if (!window) return;
    NSString *festivalKey = [self todayFestivalKey];
    if (festivalKey.length == 0) return;                 // 非节日零成本退出
    // 开关门：general.festival_effects（BOOL 默认 YES；键缺省 = 开）。
    //   若会话中途被关闭（备份导入等），顺手摘除已挂层（防残留）。
    id prefValue = getPrefObject(kAme428PrefFestivalEffects);
    BOOL enabled = (prefValue == nil) ? YES : [prefValue boolValue];
    if (!enabled) {
        if (sAme428AttachedView.superview != nil) [self detach];
        NSLog(@"[Task428] festival effects disabled by preference (%@)", kAme428PrefFestivalEffects);
        return;
    }
    if (sAme428AttachedView.superview == window) return; // 幂等：已挂同窗零动作
    [self detach];

    ZL2FestivalEffectKind kind = [self effectKindForFestivalKey:festivalKey];
    ZL2FestivalEffectsView *view = [[ZL2FestivalEffectsView alloc] eme428_initWithKind:kind];
    view.frame = window.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:view];                            // addSubview = 置顶（window 顶层）
    sAme428AttachedView = view;

    // 点击爆发（烟花/爱心/蝙蝠）：透明接收 = window 级 tap 手势；
    // cancelsTouchesInView=NO + 零延迟 → 与下方控件触控完全并存。
    if (kind == ZL2FestivalEffectFireworks || kind == ZL2FestivalEffectHearts ||
        kind == ZL2FestivalEffectBats) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:view action:@selector(eme428_tap:)];
        tap.cancelsTouchesInView = NO;
        tap.delaysTouchesBegan = NO;
        tap.delaysTouchesEnded = NO;
        [window addGestureRecognizer:tap];
        sAme428TapGesture = tap;
    }
    NSLog(@"[Task428] festival effects attached (key=%@, kind=%ld)", festivalKey, (long)kind);
}

+ (void)detach {
    if (sAme428TapGesture) {
        [sAme428TapGesture.view removeGestureRecognizer:sAme428TapGesture];
        sAme428TapGesture = nil;
    }
    [sAme428AttachedView eme428_tearDown];
    [sAme428AttachedView removeFromSuperview];
    sAme428AttachedView = nil;
}

+ (BOOL)isAttached {
    return (sAme428AttachedView.superview != nil);
}

@end
