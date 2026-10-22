//
// ZL2SettingCards.h — ZL2 风格设置卡片组件（7.0-UI-13-S）
//
// 对标：ZalithLauncher2 SettingsScreen.kt 的 SettingsCard 家族——「连体拼接
// 组卡」是 ZL2 全 UI 的核心识别元素：一个分组内若干行卡上下连体（零间距），
// 组顶/组底外圆角 28（M3 extraLarge）、中间卡片内圆角 4（M3 extraSmall），
// 行卡内边距 16、底色 surfaceContainer、行高 ≥ 56；组与组之间 2pt 间距。
//
// 组件清单：
//   ZL2SettingCardGroup   连体组卡容器（按行位置自动拼圆角）
//   ZL2SettingRowBase     行卡基类（标题 + 13pt 副文本，fontTitleMedium 标题）
//   ZL2SettingRowSwitch   标题 + 副文本 + 右侧 ZL2M3Switch
//   ZL2SettingRowSlider   标题 + ZL2Slider(系统 UISlider 样式化) + primary 数值徽章
//   ZL2SettingRowList     标题 + 当前值 + 展开箭头；展开单选列表收起，选中即存
//   ZL2SettingRowInput    标题 + UITextField 输入行
//   ZL2SettingRowAction   标题 + 副文本 + 点击事件 + 可选 error 红色态
//                         （onTap 为 nil 时退化为只读展示行，可挂 detailText）
//   ZL2SettingRowEnum     标题 + FlowRow 平铺 RadioButton 单选（EnumSettingsCard）
//
// 红线（与 ZL2 域全部页面同一条）：
//   - 颜色/字体/圆角一律 ZL2Theme 类方法（M3 令牌），零硬编码 UIColor；
//   - iOS 14.0 API 上限；SF 符号带旧名 fallback；
//   - 新建视图一律 translatesAutoresizingMaskIntoConstraints = NO；
//   - 程序赋值入口（ame_set*/ame_reload*）不触发回调块——回调只在用户
//     交互时发生，页面刷新路径（ame_refreshState）可安全回写显示值。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 连体组卡容器

@interface ZL2SettingCardGroup : UIView

/// 追加一行行卡（自动按位置重拼整组圆角）
- (void)ame_addRow:(UIView *)row;

/// 依次追加多行行卡
- (void)ame_addRows:(NSArray<UIView *> *)rows;

/// 当前行数
@property (nonatomic, readonly) NSUInteger rowCount;

/// 组间距（消费方 stack 的 spacing 用值）：2pt
+ (CGFloat)preferredGroupSpacing;

/// 清空全部行（页面重建内容用；重建后圆角自动复位）
- (void)ame_removeAllRows;

@end

#pragma mark - 行卡基类

@interface ZL2SettingRowBase : UIControl

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(nullable NSString *)subtitle;

/// 标题（fontTitleMedium / onSurface）
@property (nonatomic, copy) NSString *title;

/// 副文本（13pt / onSurfaceVariant；nil 或空串时隐藏）
@property (nonatomic, copy, nullable) NSString *subtitle;

/// 行卡最小高度（56pt，spec 下限）
+ (CGFloat)minRowHeight;

/// 标题(+副文本)竖排栈——子类布局引用（基类已建好但未 pin，子类自行约束）
@property (nonatomic, strong, readonly) UIStackView *ame_textStack;

/// 标题行右侧的辅助锚（子类 accessory 与标题的最小间距）
+ (CGFloat)titleAccessoryGap;

@end

#pragma mark - 开关行

@interface ZL2SettingRowSwitch : ZL2SettingRowBase

/// 用户拨动回调（程序赋值不触发）
@property (nonatomic, copy, nullable) void (^onToggle)(BOOL on);

/// 程序赋值（不触发 onToggle）
- (void)ame_setOn:(BOOL)on;

/// 当前开关态
- (BOOL)ame_isOn;

@end

#pragma mark - 滑条行

@interface ZL2SettingRowSlider : ZL2SettingRowBase

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(nullable NSString *)subtitle
                    minimum:(NSInteger)minimum
                    maximum:(NSInteger)maximum
                     suffix:(nullable NSString *)suffix;

/// 数值徽章文本定制（缺省 = "值%suffix"）；返回 nil 时回退缺省格式
@property (nonatomic, copy, nullable) NSString *(^valueTextBlock)(NSInteger value);

/// 拖动/点击回调（每 tick 触发；程序赋值不触发）
@property (nonatomic, copy, nullable) void (^onValueChanged)(NSInteger value);

/// 程序赋值（不触发 onValueChanged）
- (void)ame_setValue:(NSInteger)value;

/// 当前值（整数口径）
- (NSInteger)ame_value;

@end

#pragma mark - 单选展开列表行

@interface ZL2SettingRowList : ZL2SettingRowBase

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(nullable NSString *)subtitle
                      options:(NSArray<NSString *> *)labels
                   optionKeys:(nullable NSArray<NSString *> *)keys;

/// 选中回调（选中即收起；程序赋值不触发）
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);

/// 程序赋值选中项（刷新当前值显示 + 各选项勾选态，不触发 onSelect）
- (void)ame_reloadSelectedIndex:(NSInteger)index;

/// 当前选中项（无选中 = NSNotFound）
- (NSUInteger)ame_selectedIndex;

/// 收起展开列表（页面切走时调用，避免跨页残留展开态）
- (void)ame_collapse;

@end

#pragma mark - 输入行

@interface ZL2SettingRowInput : ZL2SettingRowBase

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(nullable NSString *)subtitle
                  placeholder:(nullable NSString *)placeholder
                         text:(nullable NSString *)text;

/// 文本变化回调（编辑中每 tick + 结束编辑；程序赋值不触发）
@property (nonatomic, copy, nullable) void (^onTextChanged)(NSString *text);

/// 程序赋值（不触发 onTextChanged）
- (void)ame_setText:(NSString *)text;

/// 当前文本
- (NSString *)ame_text;

@end

#pragma mark - 动作行（含只读展示形态）

@interface ZL2SettingRowAction : ZL2SettingRowBase

/// 点击回调；为 nil 时整行退化为只读展示（不响应点击、无 chevron）
@property (nonatomic, copy, nullable) void (^onTap)(void);

/// 错误态：标题/副文本染 error 红（不可用/异常语义）
@property (nonatomic, assign) BOOL errorState;

/// 尾部值文本（onSurfaceVariant 14pt，右对齐；只读展示行用它显示版本号等）
@property (nonatomic, copy, nullable) NSString *detailText;

@end

#pragma mark - 平铺单选行（FlowRow / EnumSettingsCard）

@interface ZL2SettingRowEnum : ZL2SettingRowBase

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(nullable NSString *)subtitle
                      options:(NSArray<NSString *> *)labels;

/// 选中回调（程序赋值不触发）
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);

/// 程序赋值选中项（不触发 onSelect）
- (void)ame_reloadSelectedIndex:(NSInteger)index;

/// 当前选中项（无选中 = NSNotFound）
- (NSUInteger)ame_selectedIndex;

@end

NS_ASSUME_NONNULL_END
