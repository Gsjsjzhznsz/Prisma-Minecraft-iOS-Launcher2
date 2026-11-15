//
// ZL2ThemeCustomSheet.h — ★Task429（PDF 第五版 §8.1）CUSTOM 取色弹层
//
// 「主题色板」模式选择列表的自定义档弹层：12 主色圆点 + 三档调色风格
// segmented + 实时预览三色块。确认后写三新键（general.custom_seed_color /
// general.custom_palette_style / general.theme_mode=8）并触发生效链
// （ZL2DynamicPalette ame429_reloadAndApply → HCT 色板 → 根重建）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2ThemeCustomSheet : UIViewController

// 便捷呈现（formSheet 口径，调用方无需管 presentation 样式）
- (void)ame429_presentFromViewController:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
