//
// ZL2RailView.m — Material 3 NavigationRail 组件实现（7.0-UI-8）
//
// 视觉规格（M3 NavigationRail 静态移植）：
//   · 项：56pt 高 UIControl，内部 32×32 图标胶囊（cornerRadius 16）+ 4pt
//     间距 + 14pt 标签（fontLabelLarge 12pt 档），整体居中于 rail 宽。
//   · active：胶囊 primaryContainer 底 + 图标 onPrimaryContainer + 标签
//     primary；inactive：胶囊透明 + 图标/标签 onSurfaceVariant。
//   · rail 自身 surface 底 + 右缘 1pt outlineVariant 分隔（由壳决定是否
//     显示——本组件内置右缘线，预览/壳视觉一致）。
// 纪律：SF Symbols 全 SF1.0 级 + fallback（iOS 14 红线）；动态色跟随
//   ZL2Theme（禁手写 traitCollection 分支）；无 tag 身份查找（数组直持）。
//

#import "ZL2RailView.h"
#import "ZL2Theme.h"

#pragma mark - 私有项视图

@interface ZL2RailItem : UIControl
@property(nonatomic, strong) UIView *iconBg;      // 32×32 胶囊
@property(nonatomic, strong) UIImageView *icon;   // 24×24 模板
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, assign) NSInteger pageIndex;
- (void)ame_setSelected:(BOOL)selected;
@end

@implementation ZL2RailItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    _iconBg = [[UIView alloc] init];
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBg.layer.cornerRadius = 16.0; // 32/2 = M3 full pill
    [self addSubview:_iconBg];

    _icon = [[UIImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _icon.userInteractionEnabled = NO;
    [_iconBg addSubview:_icon];

    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_iconBg.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconBg.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
        [_iconBg.widthAnchor constraintEqualToConstant:32.0],
        [_iconBg.heightAnchor constraintEqualToConstant:32.0],

        [_icon.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:24.0],
        [_icon.heightAnchor constraintEqualToConstant:24.0],

        [_label.topAnchor constraintEqualToAnchor:_iconBg.bottomAnchor constant:2.0],
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2.0],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2.0],
        [_label.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-2.0],
    ]];
    return self;
}

- (void)ame_setSelected:(BOOL)selected {
    UIColor *bg = selected ? [ZL2Theme primaryContainer] : [UIColor clearColor];
    UIColor *iconTint = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    UIColor *labelTint = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    // 深浅切换下 dynamicProvider 已跟随；此处仅按选中态重涂
    self.iconBg.backgroundColor = bg;
    self.icon.tintColor = iconTint;
    self.label.textColor = labelTint;
    self.accessibilityTraits = selected ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
}

@end

#pragma mark - Rail 主体

@interface ZL2RailView ()
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) NSMutableArray<ZL2RailItem *> *items;
@property(nonatomic, strong) UIView *divider;
@end

@implementation ZL2RailView

+ (CGFloat)widthForIdiom:(UIUserInterfaceIdiom)idiom {
    return (idiom == UIUserInterfaceIdiomPad) ? 104.0 : 88.0;
}

+ (CGFloat)itemHeight {
    return 56.0;
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items
                      symbols:(NSArray<NSString *> *)symbols {
    self = [super initWithFrame:CGRectZero];
    if (!self) return self;
    NSParameterAssert(items.count == symbols.count && items.count > 0);

    _items = [NSMutableArray array];
    self.backgroundColor = [ZL2Theme surface];

    // 右缘 1pt 分隔线（outlineVariant，随深浅动态）
    _divider = [[UIView alloc] init];
    _divider.translatesAutoresizingMaskIntoConstraints = NO;
    _divider.backgroundColor = [ZL2Theme outlineVariant];
    _divider.userInteractionEnabled = NO;
    [self addSubview:_divider];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.alignment = UIStackViewAlignmentCenter;
    _stack.spacing = 2.0;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stack];

    CGFloat w = [ZL2RailView widthForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    w -= 12.0;

    [items enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        ZL2RailItem *item = [[ZL2RailItem alloc] initWithFrame:CGRectZero];
        item.pageIndex = (NSInteger)idx;
        item.label.text = title;
        // SF1.0 级符号名直取；systemImageNamed 返回 nil 时走 fallback（iOS 14 红线）
        UIImage *img = [UIImage systemImageNamed:symbols[idx]];
        if (!img) img = [UIImage systemImageNamed:@"circle"];
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        item.icon.image = img;
        item.isAccessibilityElement = YES;
        item.accessibilityLabel = title;
        item.accessibilityTraits = UIAccessibilityTraitButton;
        [item addTarget:self action:@selector(ame_itemTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [item.widthAnchor constraintEqualToConstant:w].active = YES;
        [item.heightAnchor constraintEqualToConstant:[ZL2RailView itemHeight]].active = YES;
        [_stack addArrangedSubview:item];
        [_items addObject:item];
    }];

    [NSLayoutConstraint activateConstraints:@[
        [_divider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_divider.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_divider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_divider.widthAnchor constraintEqualToConstant:1.0],

        [_stack.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:8.0],
        [_stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:4.0],
        [_stack.trailingAnchor constraintLessThanOrEqualToAnchor:_divider.leadingAnchor constant:-4.0],
    ]];

    _selectedIndex = -1;
    return self;
}

- (void)ame_itemTapped:(ZL2RailItem *)sender {
    if (sender.pageIndex == self.selectedIndex) return;
    if ([self.delegate respondsToSelector:@selector(railView:didSelectIndex:)]) {
        [self.delegate railView:self didSelectIndex:sender.pageIndex];
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    NSInteger clamped = selectedIndex;
    if (clamped < 0) clamped = 0;
    if (clamped >= (NSInteger)_items.count) clamped = (NSInteger)_items.count - 1;
    _selectedIndex = clamped;
    [self ame_refreshSelection];
}

- (void)ame_refreshSelection {
    [self.items enumerateObjectsUsingBlock:^(ZL2RailItem *item, NSUInteger idx, BOOL *stop) {
        [item ame_setSelected:((NSInteger)idx == self.selectedIndex)];
    }];
}

@end
