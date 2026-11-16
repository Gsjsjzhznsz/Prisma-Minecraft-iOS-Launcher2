//
// ZL2ThemeCustomSheet.h — ★Task429（PDF 第五版 §8.1）CUSTOM 取色弹层
//
// 「主题色板」模式选择列表的自定义档弹层：★Task436 取色自由化——
// 12 快选色圆点 + 色相条（HSL 换相渐变自绘拖条）+ Hex 输入框
// （#RRGGBB 校验+解析）+ 三档调色风格 segmented + 实时预览三色块。
// 确认后写三新键（general.custom_seed_color /
// general.custom_palette_style / general.theme_mode=8）并触发生效链
// （ZL2DynamicPalette ame429_reloadAndApply → HCT 色板 → 根重建）。
// 种子格式仍为 "#RRGGBB"（下游管线零改动）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2ThemeCustomSheet : UIViewController

// 便捷呈现（formSheet 口径，调用方无需管 presentation 样式）
- (void)ame429_presentFromViewController:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
