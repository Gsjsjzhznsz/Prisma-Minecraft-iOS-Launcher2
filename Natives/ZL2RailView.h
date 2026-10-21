//
// ZL2RailView.h — Material 3 NavigationRail 组件（7.0-UI-8：对标 ZalithLauncher 2）
//
// M3 NavigationRail 规格（静态移植）：每项 = 32pt 图标胶囊（active 时
// primaryContainer 底，inactive 透明）+ 12pt 间距标签；active 胶囊内图标
// onPrimaryContainer，inactive 图标/标签 onSurfaceVariant。
// 独立组件：壳（ZL2ShellViewController）与预览 harness（无需拖入功能 VC
// 依赖链即可 1:1 预览壳视觉）共用。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ZL2RailView;

@protocol ZL2RailViewDelegate <NSObject>
- (void)railView:(ZL2RailView *)rail didSelectIndex:(NSInteger)index;
@end

@interface ZL2RailView : UIView

// 选中页序（0...items.count-1，越界自动收敛）；赋值后立即刷新视觉
@property(nonatomic, assign) NSInteger selectedIndex;

@property(nonatomic, weak) id<ZL2RailViewDelegate> delegate;

// items = 标签文案；symbols = SF Symbols 名（与 items 同序同数）
- (instancetype)initWithItems:(NSArray<NSString *> *)items
                      symbols:(NSArray<NSString *> *)symbols;

// M3 rail 宽度：iPhone 88pt / iPad 104pt
+ (CGFloat)widthForIdiom:(UIUserInterfaceIdiom)idiom;

// 单项高度（56pt：32 胶囊 + 4 间距 + 14 标签 + 6 内边距，供测试断言）
+ (CGFloat)itemHeight;

@end

NS_ASSUME_NONNULL_END
