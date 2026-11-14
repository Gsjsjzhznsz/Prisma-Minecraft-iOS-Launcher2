//
//  ZL2FestivalEffects.h
//  Amethyst
//
//  ★Task428（报告 8.2 节日彩蛋复活）：iOS 原生手段对齐 ZL2 上游 FestivalEffects。
//    上游口径：进主界面取当日节日 → window 顶层挂粒子层（雪/雨/烟花/萤火/
//    爱心/蝙蝠六类模拟器，烟花/蝙蝠/爱心支持点击爆发）→ 顶部问候。
//
//    本地化对齐：十五条节日问候文案实际落表为 i18n_str_324 ~ i18n_str_340
//    共 17 键（zh-Hans 表 1207-1223 行；报告行号漂移 ±50，以符号锚点为准），
//    全部零引用躺表——todayFestivalKey 逐键对号判定后原样返回这些既有键，
//    问候语零新增 i18n 键。
//
//  红线：iOS 14.0 API 上限；零 SF Symbols（粒子贴图 CoreGraphics 自绘）；
//    CAEmitterLayer 合法 emitterShape 仅 kCAEmitterLayerPoint/Line/Circle/
//    CircleOutline；颜色 ZL2Theme 令牌/深浅两态自适配。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// ★Task428：节日效果种类（六类模拟器，对齐 ZL2 FestivalEffects 预设族）
typedef NS_ENUM(NSInteger, ZL2FestivalEffectKind) {
    ZL2FestivalEffectSnow = 0,       // 雪：白色小圆缓落摆动（圣诞/平安夜）
    ZL2FestivalEffectRain = 1,       // 雨：细长条快速下落（清明/端午）
    ZL2FestivalEffectFireworks = 2,  // 烟花：底部升空周期爆开 + 点击爆发（新年/春节/国庆等庆典）
    ZL2FestivalEffectFirefly = 3,    // 萤火：黄绿小点闪烁漂浮（中秋/重阳）
    ZL2FestivalEffectHearts = 4,     // 爱心：红色心形上浮 + 点击爆发（七夕/六一/教师节）
    ZL2FestivalEffectBats = 5,       // 蝙蝠：深色剪影横向飘移 + 点击爆发（万圣预留——
                                     //   本地化表暂无万圣文案，判定表未映射任何节日）
};

@interface ZL2FestivalEffects : NSObject

/// ★Task428：今日节日对应的本地化键（i18n_str_324~340 族，直接复用既有问候键）。
///   公历节日用 NSCalendar（显式公历）月/日比对；农历节日（春节/元宵/端午/
///   七夕/中秋/重阳/除夕）用 NSCalendarIdentifierChinese 取月/日精确判定；
///   清明用 4/4~4/6 近似窗口（节气年际漂移 ±1 天）。非节日返回 nil。
+ (nullable NSString *)todayFestivalKey;

/// ★Task428：节日键 → 效果种类映射（ZL2 口径：圣诞/平安夜→雪、清明→雨、
///   新年/春节/国庆→烟花、中秋→萤火、七夕→爱心；表内其余节日按最接近
///   语义就近归档，映射注释见 .m）。非节日键返回 ZL2FestivalEffectSnow
///   且本方法不应被调用（调用方以 todayFestivalKey 非空为前提）。
+ (ZL2FestivalEffectKind)effectKindForFestivalKey:(NSString *)festivalKey;

/// ★Task428：挂到窗口顶层（insertSubview 于全部子视图之上；幂等——已挂载
///   且同一窗口则零动作）。非节日 / 偏好 general.festival_effects 关闭
///   （BOOL 默认 YES，键缺省视为开）时不挂载。
+ (void)attachToWindow:(nullable UIWindow *)window;

/// ★Task428：摘除粒子层与点击手势（幂等）。游戏换根（SurfaceViewController
///   接管 window）时壳层 viewDidDisappear 调用，避免粒子飘进游戏画面。
+ (void)detach;

/// ★Task428：当前是否已挂载（调试/自检用）
+ (BOOL)isAttached;

@end

NS_ASSUME_NONNULL_END
