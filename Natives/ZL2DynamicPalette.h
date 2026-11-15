//
// ZL2DynamicPalette.h — ★Task429（PDF 第五版 §8.1 + 第六版 §3.2.3）主题动态取色中枢
//
// 三新键（注册片段 scripts/task429_prefs_F.json，注册面归主控合流）：
//   general.theme_mode            int 0=embermire(默认)/1=跟随背景/2..7=预设/8=CUSTOM
//   general.custom_seed_color     hex 串（CUSTOM 模式种子色，空 = 断链修复回落旧 accent_color）
//   general.custom_palette_style  int 0=自然/1=鲜活/2=柔和（色度缩放，见 AmeHCTPalette.h）
//
// 预设色板 6 套（色值近似移植——仓内无 ZalithLauncher2 Color.kt 参考副本，
// 种子取 ZL2 视觉家族近似值并逐套注释）：
//   mode 2 = embermire 动态重演（种子 = embermire 主棕 0xA63A17，HCT 重演
//            静态板的近似；mode 0 才是 1:1 静态板——覆盖层不推送）
//   mode 3 = 冻湖蓝（种子 0x2779B5 湖蓝）
//   mode 4 = 森绿（种子 0x2E7D51 森林绿）
//   mode 5 = 暮紫（种子 0x6E56A6 暮霭紫）
//   mode 6 = 绯红（种子 0xB4424C 绯红）
//   mode 7 = 琥珀（种子 0xA97A2C 琥珀）
//
// 生效链（复用壳层既有外观重应用机制，勿发明第二套广播）：
//   模式/种子/风格变化（设置行/CustomSheet 写键 → ame429_reloadAndApply）
//     → 非跟随模式：HCT 纯数学同步生成（毫秒级）→ 推 ZL2Theme 活动覆盖层
//       → [ZL2Theme ame429_requestRootRebuild]（Task346 根重建杠杆，
//       AppLanguageChanged → SceneDelegate 整壳重建，Task380 冷却防环）
//     → 跟随背景模式：先落 embermire 保底 → 后台取色（AmeUIImageColors，
//       输入吃 BackgroundManager ame223_currentWallpaperImage 降采样管线
//       ——「先降采样再提色」第六版捆绑项）→ 主线程推覆盖层 + 根重建。
//   壁纸更换：BackgroundManager Ame223WallpaperChangedNotification（本中枢
//     观察 + BackgroundManager set/clear 路径补播）→ 跟随背景模式重取色。
//
// accent_color 断链修复：旧自定义三色 accent_color（general.accent_color）
// 只被旧页消费、ZL2Theme 完全不读 = 断链。CUSTOM 模式（mode 8）下用户未
// 选新种子（general.custom_seed_color 空）时回落读旧偏好 accent_color
// （LauncherPreferences 只读 API，文件禁改）作种子——旧自定义色经由动态
// 色板重新贯通 ZL2 全页面。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 主题模式枚举（general.theme_mode 值域；与文件头预设表一一对应）
typedef NS_ENUM(NSInteger, Ame429ThemeMode) {
    Ame429ThemeModeEmbermire       = 0,   // embermire 静态板（编译期默认，零覆盖）
    Ame429ThemeModeFollowWall      = 1,   // 跟随背景（壁纸取色 → HCT）
    Ame429ThemeModeEmbermireReplay = 2,   // 预设[0]：embermire 动态重演（UI 不直达，mode 0 才是 1:1 静态板）
    Ame429ThemeModeFrozenLake      = 3,   // 预设[1]：冻湖蓝
    Ame429ThemeModeForestGreen     = 4,   // 预设[2]：森绿
    Ame429ThemeModeDuskPurple      = 5,   // 预设[3]：暮紫
    Ame429ThemeModeCrimson         = 6,   // 预设[4]：绯红
    Ame429ThemeModeAmber           = 7,   // 预设[5]：琥珀
    Ame429ThemeModeCustom          = 8,   // CUSTOM（用户种子 + 调色风格）
};

// 预设档显示名索引口径（UI 列表用；与 Ame429ThemeMode 值解耦——见枚举注释）
//   UI 直达模式 = 0 embermire / 1 跟随背景 / 3 冻湖蓝 / 4 森绿 / 5 暮紫 /
//                 6 绯红 / 7 琥珀 / 8 自定义

@interface ZL2DynamicPalette : NSObject

+ (instancetype)shared;

// 当前生效模式（general.theme_mode，值域见 Ame429ThemeMode；越界回落 0）
@property (nonatomic, readonly, assign) NSInteger themeMode;
// 当前调色风格（general.custom_palette_style，0/1/2）
@property (nonatomic, readonly, assign) NSInteger paletteStyle;

// 模式/种子/风格变化统一入口（设置行 / CustomSheet 确认后调用；主线程）。
// 非跟随模式同步生成推送；跟随背景模式先落 embermire 再后台取色。
- (void)ame429_reloadAndApply;

// 壁纸变化入口（本中枢已挂 Ame223WallpaperChangedNotification；跟随背景
// 模式重取色，其余模式零操作）。
- (void)ame429_wallpaperDidChange;

@end

NS_ASSUME_NONNULL_END
