//
// ZL2M3Kit.h — Material Design 3 功能组件库（7.0-UI-12：实现 md3 的功能）
//
// 定位：ZL2 域的 M3 交互组件统一供给层。7.0-UI-8 落地了 M3 令牌层
//   （ZL2Theme）与壳骨架，7.0-UI-9~11 重写了四功能页，但页内交互件
//   （搜索框/chip/开关/弹窗/底部弹层）一直是各页手搓 UIControl——本轮
//   把它们抽成可复用组件并补齐 MD3 规格行为：
//
//   ① ZL2M3SearchBar     M3 胶囊搜索框（surfaceContainerHigh / radiusXL /
//                        高 44 / 前置放大镜 / 输入即回调）
//   ② ZL2M3FilterChip    M3 筛选 chip（未选 surfaceContainer + outlineVariant
//                        1pt 描边；选中 primaryContainer 无描边 + 前置对勾
//                        —— MD3 filter chip 规格的两态语义）
//   ③ ZL2M3Switch        MD3 开关（轨道 52×32 全圆角；未选 surfaceVariant 底
//                        + outline 2pt 描边 + 16pt 拇指；选中 primary 底无
//                        描边 + 24pt onPrimary 拇指；弹簧动画过渡）
//   ④ ZL2M3Dialog        M3 基础对话框（surfaceContainerHigh / radiusXL 28 /
//                        标题+正文+右对齐文本按钮；scrim 淡入淡出）
//   ⑤ ZL2M3BottomSheet   M3 底部弹层（surfaceContainerLow / 顶部 radiusXL /
//                        32×4 抓手 / scrim 点按关闭 / 上滑入场 0.28s）
//
// 通用红线（与 ZL2 域全部页面同一条）：
//   - 颜色/字体/圆角一律 ZL2Theme 类方法，零 AmeTheme、零硬编码 UIColor、
//     零手写 traitCollection 深浅分支（dynamicProvider 系统正统路径）；
//   - iOS 14.0 API 上限：禁 UISheetPresentationController（iOS15）、
//     button.configuration（iOS15）、UIMenu 挂按钮（域内判例禁用）；
//   - SF 符号全 SF1.0 级；
//   - 新建视图一律 translatesAutoresizingMaskIntoConstraints = NO。
//
// 消费面：ZL2GameDownloadViewController（7.0-UI-12 首批）；设置枢纽
//   M3 换装等后续轮次按需续接（Switch 已就位）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - ① M3 胶囊搜索框

@interface ZL2M3SearchBar : UIView

/// 文字变化（含清空）；return 键触发 onReturn（已含最终文本）
@property (nonatomic, copy, nullable) void (^onTextChanged)(NSString *text);
@property (nonatomic, copy, nullable) void (^onReturn)(NSString *text);

@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *placeholder;

- (void)setText:(NSString *)text;

@end

#pragma mark - ② M3 筛选 chip

@interface ZL2M3FilterChip : UIControl

/// 选中态 setter：刷新着色与对勾显隐（MD3 两态：描边↔容器底+对勾）
@property (nonatomic, assign, getter=isSelected) BOOL selected;

- (instancetype)initWithText:(NSString *)text;

/// chip 统一高度（32，MD3 chip 规格线）
+ (CGFloat)preferredHeight;

@end

#pragma mark - ③ MD3 开关

@interface ZL2M3Switch : UIControl

/// 开关态（程序赋值不动画；UI 点击自动翻转并发 ValueChanged）
@property (nonatomic, assign) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;

/// 开关固有尺寸 52×32（布局锚直接引用）
+ (CGFloat)switchWidth;
+ (CGFloat)switchHeight;

@end

#pragma mark - ④ M3 基础对话框

@interface ZL2M3Dialog : NSObject

/// 展示 M3 基础对话框（挂到 keyWindow 场景顶层；确认/取消二选一回调后自动收起）
/// destructive=YES 时确认按钮用 error 色（MD3 删除确认语义）
+ (void)showTitle:(NSString *)title
             body:(NSString *)body
     confirmTitle:(NSString *)confirmTitle
       destructive:(BOOL)destructive
        onConfirm:(nullable void (^)(void))onConfirm
         onCancel:(nullable void (^)(void))onCancel;

/// 收起当前（若在）；同页串发对话框时用于保证时序
+ (void)dismiss;

@end

#pragma mark - ⑤ M3 底部弹层

@interface ZL2M3BottomSheet : NSObject

/// 弹出内容视图（调用方自建自布局的 content，弹层按其 intrinsic 高度包底，
/// 左右缘贴屏、顶部 radiusXL + 抓手；scrim 点按关闭）。
/// content 需已 translatesAutoresizingMaskIntoConstraints = NO。
+ (void)presentWithContentView:(UIView *)content
                    onDismiss:(nullable void (^)(void))onDismiss;

/// 收起（若在展示中）；content 为 present 时传入的同一实例
+ (void)dismissWithContentView:(UIView *)content;

@end

NS_ASSUME_NONNULL_END
