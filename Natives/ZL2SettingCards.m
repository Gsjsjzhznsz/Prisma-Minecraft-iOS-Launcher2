//
// ZL2SettingCards.m — ZL2 风格设置卡片组件实现（7.0-UI-13-S）
//
// 设计规格出处（对标 ZalithLauncher2 SettingsScreen.kt 的 SettingsCard 家族）：
//   · 组卡 = 若干行卡竖排连体（零间距），行底色 surfaceContainer；
//   · 拼圆角：Single/组顶 = 28（radiusXL，M3 extraLarge），中间卡片 = 4
//     （radiusXS，M3 extraSmall），组底 = 28；
//     中间卡片的 4pt 内圆角以 maskedCorners=0 落值——Compose 的内圆角在
//     同色连体下不可见，iOS 单层单半径若真去切会露出透明缺口（页面底色
//     穿缝），故令牌值保留、可见性归零；
//   · 行内 padding 16，行高 ≥ 56；标题 fontTitleMedium / onSurface，
//     副文本 13pt / onSurfaceVariant；
//   · 交互件：开关 = ZL2M3Kit 的 ZL2M3Switch；滑条 = 系统 UISlider
//     （tint = primary）+ primary 数值徽章；单选圆钮 = 20pt 圆环
//     （未选 onSurfaceVariant 描边，选中 primary 描边 + primary 圆点）。
//
// 红线：iOS 14.0 API 上限（UIView.animate / maskedCorners / setCustomSpacing
//   均为 iOS 11 前后既有的公开 API）；颜色/字体/圆角一律 ZL2Theme 类方法；
//   全部新建视图 translatesAutoresizingMaskIntoConstraints = NO；
//   程序赋值入口不触发回调块（刷新路径安全回写）。
//

#import "ZL2SettingCards.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"

#pragma mark - 私有小件

/// M3 RadioButton 圆钮（20pt 圆环：未选 onSurfaceVariant 描边空心，
/// 选中 primary 描边 + 10pt primary 圆点）——List 行与 Enum 行共用
@interface ame_SettingRadioDot : UIView
- (void)ame_setSelected:(BOOL)selected;
@end

@implementation ame_SettingRadioDot

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = 10.0;
    self.layer.borderWidth = 2.0;
    [self ame_setSelected:NO];

    // 选中圆点（primary 10pt，居中；默认隐藏）
    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.layer.cornerRadius = 5.0;
    dot.backgroundColor = [ZL2Theme primary];
    dot.tag = 0x5244;   // 私有载荷（仅自身查找，不进 viewWithTag 全局域）
    [self addSubview:dot];
    [NSLayoutConstraint activateConstraints:@[
        [dot.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:10.0],
        [dot.heightAnchor constraintEqualToConstant:10.0],
    ]];
    return self;
}

- (void)ame_setSelected:(BOOL)selected {
    UIColor *ring = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    self.layer.borderColor = ring.CGColor;
    UIView *dot = [self viewWithTag:0x5244];
    dot.hidden = !selected;
}

@end

#pragma mark - 连体组卡容器

@interface ZL2SettingCardGroup ()
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation ZL2SettingCardGroup

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.alignment = UIStackViewAlignmentFill;
    _stack.spacing = 0.0;   // 连体：行间零缝
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
    return self;
}

+ (CGFloat)preferredGroupSpacing {
    return 2.0;   // spec：组间距 2pt
}

- (void)ame_addRow:(UIView *)row {
    [self.stack addArrangedSubview:row];
    [self ame_reapplyCorners];
}

- (void)ame_addRows:(NSArray<UIView *> *)rows {
    for (UIView *row in rows) [self.stack addArrangedSubview:row];
    [self ame_reapplyCorners];
}

- (void)ame_removeAllRows {
    for (UIView *row in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
}

- (NSUInteger)rowCount {
    return self.stack.arrangedSubviews.count;
}

// 按位置拼圆角（见文件头规格注）：
//   Single = 28 四角；Top = 28 上角（下角方）；Bottom = 28 下角；
//   Middle = 4 令牌落值、maskedCorners 空（同色连体内圆角不可见，真切露缝）
- (void)ame_reapplyCorners {
    NSArray<UIView *> *rows = self.stack.arrangedSubviews;
    NSUInteger count = rows.count;
    CGFloat outer = [ZL2Theme radiusXL];
    CGFloat inner = [ZL2Theme radiusXS];
    [rows enumerateObjectsUsingBlock:^(UIView *row, NSUInteger idx, BOOL *stop) {
        row.backgroundColor = [ZL2Theme surfaceContainer];
        CALayer *layer = row.layer;
        if (count == 1) {
            layer.cornerRadius = outer;
            layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner
                                | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        } else if (idx == 0) {
            layer.cornerRadius = outer;
            layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        } else if (idx == count - 1) {
            layer.cornerRadius = outer;
            layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        } else {
            layer.cornerRadius = inner;
            layer.maskedCorners = 0;
        }
        row.layer.masksToBounds = YES;
    }];
}

@end

#pragma mark - 行卡基类

@interface ZL2SettingRowBase ()
@property (nonatomic, strong, readwrite) UIStackView *ame_textStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation ZL2SettingRowBase

+ (CGFloat)minRowHeight {
    return 56.0;
}

+ (CGFloat)titleAccessoryGap {
    return 12.0;
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (!self) return self;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.font = [UIFont systemFontOfSize:13.0];   // spec：副文本 13pt
    _subtitleLabel.textColor = [ZL2Theme onSurfaceVariant];
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ame_textStack = [[UIStackView alloc] init];
    _ame_textStack.axis = UILayoutConstraintAxisVertical;
    _ame_textStack.alignment = UIStackViewAlignmentFill;
    _ame_textStack.spacing = 2.0;
    _ame_textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame_textStack addArrangedSubview:_titleLabel];
    [_ame_textStack addArrangedSubview:_subtitleLabel];
    _subtitleLabel.hidden = (subtitle.length == 0);

    _title = [title copy];
    _subtitle = [subtitle copy];

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.titleLabel.text = _title;
    self.accessibilityLabel = _title;
}

- (void)setSubtitle:(NSString *)subtitle {
    _subtitle = [subtitle copy];
    self.subtitleLabel.text = _subtitle;
    self.subtitleLabel.hidden = (_subtitle.length == 0);
}

- (void)ame_applyErrorTint:(BOOL)error {
    UIColor *titleColor = error ? [ZL2Theme error] : [ZL2Theme onSurface];
    UIColor *subColor = error ? [ZL2Theme error] : [ZL2Theme onSurfaceVariant];
    self.titleLabel.textColor = titleColor;
    self.subtitleLabel.textColor = subColor;
}

@end

#pragma mark - 开关行

@interface ZL2SettingRowSwitch ()
@property (nonatomic, strong) ZL2M3Switch *m3Switch;
@end

@implementation ZL2SettingRowSwitch

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;

    _m3Switch = [[ZL2M3Switch alloc] init];
    _m3Switch.userInteractionEnabled = YES;
    [self addSubview:_m3Switch];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.ame_textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14],
        [self.ame_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_m3Switch.leadingAnchor
                                                                   constant:-[ZL2SettingRowBase titleAccessoryGap]],

        [_m3Switch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_m3Switch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];

    [_m3Switch addTarget:self action:@selector(ame_switchChanged:)
       forControlEvents:UIControlEventValueChanged];
    return self;
}

// M3 Switch 用户拨动时自动翻转发 ValueChanged——此路径 = 用户交互
- (void)ame_switchChanged:(ZL2M3Switch *)sender {
    if (self.onToggle) self.onToggle(sender.on);
}

- (void)ame_setOn:(BOOL)on {
    // 程序赋值：setOn: 系列不发回调（ZL2M3Kit 契约：程序赋值不动画不发事件）
    [self.m3Switch setOn:on animated:NO];
}

- (BOOL)ame_isOn {
    return self.m3Switch.on;
}

@end

#pragma mark - 滑条行

@interface ZL2SettingRowSlider ()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, copy) NSString *suffix;
@end

@implementation ZL2SettingRowSlider

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                    minimum:(NSInteger)minimum
                    maximum:(NSInteger)maximum
                     suffix:(NSString *)suffix {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;
    _suffix = [suffix copy];

    _slider = [[UISlider alloc] init];
    _slider.minimumValue = (float)minimum;
    _slider.maximumValue = (float)maximum;
    _slider.tintColor = [ZL2Theme primary];   // ZL2 Slider 系统控件样式化（tint=primary）
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    [_slider addTarget:self action:@selector(ame_sliderChanged:)
      forControlEvents:UIControlEventValueChanged];

    _badgeLabel = [[UILabel alloc] init];
    _badgeLabel.font = [ZL2Theme fontLabelLarge];
    _badgeLabel.textColor = [ZL2Theme primary];
    _badgeLabel.textAlignment = NSTextAlignmentRight;
    _badgeLabel.numberOfLines = 1;
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *body = [[UIStackView alloc] init];
    body.axis = UILayoutConstraintAxisHorizontal;
    body.alignment = UIStackViewAlignmentCenter;
    body.spacing = 12.0;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [body addArrangedSubview:_slider];
    [body addArrangedSubview:_badgeLabel];
    [self addSubview:body];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [body.topAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:10],
        [body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],

        [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [_badgeLabel.heightAnchor constraintGreaterThanOrEqualToConstant:20],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];

    [self ame_setValue:(NSInteger)minimum];   // 初始徽章
    return self;
}

// 用户拖动（每 tick）→ 回调；程序赋值走 ame_setValue: 不经此
- (void)ame_sliderChanged:(UISlider *)sender {
    NSInteger value = (NSInteger)round(sender.value);
    [self ame_refreshBadge:value];
    if (self.onValueChanged) self.onValueChanged(value);
}

- (void)ame_refreshBadge:(NSInteger)value {
    NSString *text = nil;
    if (self.valueTextBlock) text = self.valueTextBlock(value);
    if (text.length == 0) {
        text = [NSString stringWithFormat:@"%ld%@", (long)value, self.suffix ?: @""];
    }
    self.badgeLabel.text = text;
}

- (void)ame_setValue:(NSInteger)value {
    value = MAX((NSInteger)self.slider.minimumValue, MIN((NSInteger)self.slider.maximumValue, value));
    [self.slider setValue:(float)value animated:NO];
    [self ame_refreshBadge:value];
}

- (NSInteger)ame_value {
    return (NSInteger)round(self.slider.value);
}

@end

#pragma mark - 单选展开列表行

@interface ZL2SettingRowList ()
@property (nonatomic, strong) UILabel *currentValueLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIStackView *optionsStack;
@property (nonatomic, strong) NSMutableArray<UIControl *> *optionControls;
@property (nonatomic, strong) NSArray<NSString *> *labels;
@property (nonatomic, strong) NSArray<NSString *> *keys;
@property (nonatomic, strong) NSLayoutConstraint *collapsedBottom;
@property (nonatomic, strong) NSLayoutConstraint *expandedBottom;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) NSUInteger selectedIndex;
@end

@implementation ZL2SettingRowList

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                      options:(NSArray<NSString *> *)labels
                   optionKeys:(NSArray<NSString *> *)keys {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;
    _labels = [labels copy];
    _keys = [keys copy];
    _selectedIndex = NSNotFound;
    _expanded = NO;
    _optionControls = [NSMutableArray array];

    UIImage *chevron = [UIImage systemImageNamed:@"chevron.right"];
    if (!chevron) chevron = [UIImage systemImageNamed:@"chevron.forward"];
    _chevronView = [[UIImageView alloc] initWithImage:
        [chevron imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _chevronView.tintColor = [ZL2Theme onSurfaceVariant];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;

    _currentValueLabel = [[UILabel alloc] init];
    _currentValueLabel.font = [ZL2Theme fontBodyMedium];
    _currentValueLabel.textColor = [ZL2Theme onSurfaceVariant];
    _currentValueLabel.textAlignment = NSTextAlignmentRight;
    _currentValueLabel.numberOfLines = 1;
    _currentValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // 展开列表：竖排选项（每项 40pt 单选行），hidden 折叠
    _optionsStack = [[UIStackView alloc] init];
    _optionsStack.axis = UILayoutConstraintAxisVertical;
    _optionsStack.alignment = UIStackViewAlignmentFill;
    _optionsStack.spacing = 0.0;
    _optionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _optionsStack.hidden = YES;
    for (NSUInteger i = 0; i < labels.count; i++) {
        UIControl *option = [self ame_optionControlAtIndex:i];
        [_optionControls addObject:option];
        [_optionsStack addArrangedSubview:option];
    }

    [self addSubview:_optionsStack];
    [self addSubview:_currentValueLabel];
    [self addSubview:_chevronView];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_currentValueLabel.centerYAnchor constraintEqualToAnchor:self.ame_textStack.centerYAnchor],
        [_currentValueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.ame_textStack.trailingAnchor
                                                                      constant:12],
        [_currentValueLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8],

        [_chevronView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_chevronView.centerYAnchor constraintEqualToAnchor:self.ame_textStack.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:14],
        [_chevronView.heightAnchor constraintEqualToConstant:14],

        [_optionsStack.topAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:12],
        [_optionsStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_optionsStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
    ]];

    // 折叠/展开双底部约束互斥切换（折叠 = 标题区钉底；展开 = 选项列表钉底）
    _collapsedBottom = [self.bottomAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:14];
    _expandedBottom = [self.bottomAnchor constraintEqualToAnchor:_optionsStack.bottomAnchor constant:14];
    _collapsedBottom.active = YES;
    _expandedBottom.active = NO;

    [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]].active = YES;

    // 整行点按 = 展开/收起；选项自身是子 UIControl（命中最深控件，不冒泡）
    [self addTarget:self action:@selector(ame_toggleExpanded) forControlEvents:UIControlEventTouchUpInside];
    [self ame_refreshCurrentValue];
    return self;
}

// 单选项 = 40pt UIControl：圆钮 20 + 标签 fontBodyLarge
- (UIControl *)ame_optionControlAtIndex:(NSUInteger)index {
    UIControl *option = [[UIControl alloc] init];
    option.translatesAutoresizingMaskIntoConstraints = NO;
    option.isAccessibilityElement = YES;
    option.accessibilityTraits = UIAccessibilityTraitButton;
    option.accessibilityLabel = self.labels[index];

    ame_SettingRadioDot *radio = [[ame_SettingRadioDot alloc] initWithFrame:CGRectZero];
    UILabel *label = [[UILabel alloc] init];
    label.text = self.labels[index];
    label.font = [ZL2Theme fontBodyLarge];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [option addSubview:radio];
    [option addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [option.heightAnchor constraintEqualToConstant:40.0],
        [radio.leadingAnchor constraintEqualToAnchor:option.leadingAnchor constant:8],
        [radio.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
        [radio.widthAnchor constraintEqualToConstant:20],
        [radio.heightAnchor constraintEqualToConstant:20],
        [label.leadingAnchor constraintEqualToAnchor:radio.trailingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:option.trailingAnchor constant:-8],
    ]];
    option.tag = (NSInteger)index;   // 下标载荷（不经 viewWithTag: 查找身份）
    [option addTarget:self action:@selector(ame_optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    return option;
}

- (void)ame_toggleExpanded {
    [self ame_setExpanded:!self.expanded animated:(self.superview != nil)];
}

- (void)ame_setExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (self.expanded == expanded) return;
    self.expanded = expanded;
    void (^apply)(void) = ^{
        self.optionsStack.hidden = !expanded;
        self.collapsedBottom.active = !expanded;
        self.expandedBottom.active = expanded;
        self.chevronView.transform = expanded ? CGAffineTransformMakeRotation(M_PI_2)
                                              : CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:^{
            apply();
            [self.superview layoutIfNeeded];
        }];
    } else {
        apply();
    }
}

- (void)ame_collapse {
    [self ame_setExpanded:NO animated:NO];
}

// 点选项：更新勾选 + 回调 + 收起（选中即存语义在页面侧 onSelect 落键）
- (void)ame_optionTapped:(UIControl *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= self.labels.count) return;
    self.selectedIndex = index;
    [self ame_refreshRadioStates];
    [self ame_refreshCurrentValue];
    [self ame_setExpanded:NO animated:YES];
    if (self.onSelect) self.onSelect(index);
}

- (void)ame_reloadSelectedIndex:(NSInteger)index {
    self.selectedIndex = (index >= 0 && (NSUInteger)index < self.labels.count)
        ? (NSUInteger)index : NSNotFound;
    [self ame_refreshRadioStates];
    [self ame_refreshCurrentValue];
}

- (NSUInteger)ame_selectedIndex {
    return self.selectedIndex;
}

- (void)ame_refreshRadioStates {
    [self.optionControls enumerateObjectsUsingBlock:^(UIControl *option, NSUInteger idx, BOOL *stop) {
        ame_SettingRadioDot *radio = nil;
        for (UIView *sub in option.subviews) {
            if ([sub isKindOfClass:[ame_SettingRadioDot class]]) { radio = (ame_SettingRadioDot *)sub; break; }
        }
        [radio ame_setSelected:(idx == self.selectedIndex)];
    }];
}

- (void)ame_refreshCurrentValue {
    NSString *text = nil;
    if (self.selectedIndex != NSNotFound && self.selectedIndex < self.labels.count) {
        text = self.labels[self.selectedIndex];
    }
    self.currentValueLabel.text = text ?: @"—";
}

@end

#pragma mark - 输入行

@interface ZL2SettingRowInput () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *textField;
@end

@implementation ZL2SettingRowInput

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                  placeholder:(NSString *)placeholder
                         text:(NSString *)text {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;

    _textField = [[UITextField alloc] init];
    _textField.font = [ZL2Theme fontBodyLarge];
    _textField.textColor = [ZL2Theme onSurface];
    _textField.backgroundColor = [ZL2Theme surfaceVariant];
    _textField.placeholder = placeholder;
    _textField.text = text;
    _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _textField.returnKeyType = UIReturnKeyDone;
    _textField.autocorrectionType = UITextAutocorrectionTypeNo;
    _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textField.delegate = self;
    _textField.layer.cornerRadius = [ZL2Theme radiusS];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;

    // 左内边距 12（系统 textField 无 padding，用 leftView 撑）
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _textField.leftView = pad;
    _textField.leftViewMode = UITextFieldViewModeAlways;

    [self addSubview:_textField];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [_textField.topAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:10],
        [_textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_textField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
        [_textField.heightAnchor constraintGreaterThanOrEqualToConstant:40],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];

    [_textField addTarget:self action:@selector(ame_textFieldChanged:)
         forControlEvents:UIControlEventEditingChanged];
    return self;
}

// 用户编辑（编辑中每 tick + 粘贴）；ame_setText: 程序赋值不经此
- (void)ame_textFieldChanged:(UITextField *)sender {
    if (self.onTextChanged) self.onTextChanged(sender.text ?: @"");
}

- (void)ame_setText:(NSString *)text {
    self.textField.text = text;
}

- (NSString *)ame_text {
    return self.textField.text ?: @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

#pragma mark - 动作行（含只读展示形态）

@interface ZL2SettingRowAction ()
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation ZL2SettingRowAction

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font = [ZL2Theme fontBodyMedium];
    _detailLabel.textColor = [ZL2Theme onSurfaceVariant];
    _detailLabel.textAlignment = NSTextAlignmentRight;
    _detailLabel.numberOfLines = 1;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.hidden = YES;

    UIImage *chevron = [UIImage systemImageNamed:@"chevron.right"];
    if (!chevron) chevron = [UIImage systemImageNamed:@"chevron.forward"];
    _chevronView = [[UIImageView alloc] initWithImage:
        [chevron imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _chevronView.tintColor = [ZL2Theme onSurfaceVariant];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.hidden = YES;

    [self addSubview:_detailLabel];
    [self addSubview:_chevronView];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.ame_textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14],
        [self.ame_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_detailLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.ame_textStack.trailingAnchor
                                                                constant:12],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8],

        [_chevronView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_chevronView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:14],
        [_chevronView.heightAnchor constraintEqualToConstant:14],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];

    [self addTarget:self action:@selector(ame_tapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)setOnTap:(void (^)(void))onTap {
    _onTap = [onTap copy];
    // onTap 为 nil = 只读展示行（关于屏版本号等）：不响应点击、无 chevron
    BOOL interactive = (_onTap != nil);
    self.chevronView.hidden = !interactive;
    self.userInteractionEnabled = interactive;
}

- (void)setErrorState:(BOOL)errorState {
    _errorState = errorState;
    [self ame_applyErrorTint:errorState];
}

- (void)setDetailText:(NSString *)detailText {
    _detailText = [detailText copy];
    self.detailLabel.text = _detailText;
    self.detailLabel.hidden = (_detailText.length == 0);
}

- (void)ame_tapped {
    if (self.onTap) self.onTap();
}

@end

#pragma mark - 平铺单选行（FlowRow / EnumSettingsCard）

@interface ZL2SettingRowEnum ()
@property (nonatomic, strong) UIStackView *gridStack;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<UIControl *> *> *optionRows;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, copy) NSArray<NSString *> *optionLabels;   // 7.0-UI-13-r1：选项标签存储（ame_enumOptionAtIndex 取用）
@end

@implementation ZL2SettingRowEnum

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                      options:(NSArray<NSString *> *)labels {
    self = [super initWithTitle:title subtitle:subtitle];
    if (!self) return self;
    _selectedIndex = NSNotFound;
    _optionRows = [NSMutableArray array];
    _optionLabels = [labels copy];   // 7.0-UI-13-r1：入参存档（类扩展属性取用）

    // FlowRow：平铺 RadioButton 单选——iOS 侧以「每行最多 3 个」的栅格化
    // 横栈实现折行（iOS 14 无 Compose FlowRow 等价物，栅格折行是既有判例）
    _gridStack = [[UIStackView alloc] init];
    _gridStack.axis = UILayoutConstraintAxisVertical;
    _gridStack.alignment = UIStackViewAlignmentFill;
    _gridStack.spacing = 8.0;
    _gridStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSInteger count = (NSInteger)labels.count;
    NSInteger perRow = 3;
    if (count == 2) perRow = 2;   // 两选项平分一行（FlowRow 自然铺满语义）
    for (NSInteger start = 0; start < count; start += perRow) {
        NSInteger end = MIN(start + perRow, count);
        NSMutableArray<UIControl *> *rowOptions = [NSMutableArray array];
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFill;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 8.0;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSInteger i = start; i < end; i++) {
            UIControl *option = [self ame_enumOptionAtIndex:(NSUInteger)i];
            [rowOptions addObject:option];
            [row addArrangedSubview:option];
        }
        [self.optionRows addObject:rowOptions];
        [_gridStack addArrangedSubview:row];
    }

    [self addSubview:_gridStack];
    [self addSubview:self.ame_textStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [_gridStack.topAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:12],
        [_gridStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_gridStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_gridStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];
    return self;
}

// 单选项 = 36pt UIControl：圆钮 18 + 标签 fontBodyMedium（居中组合）
- (UIControl *)ame_enumOptionAtIndex:(NSUInteger)index {
    UIControl *option = [[UIControl alloc] init];
    option.translatesAutoresizingMaskIntoConstraints = NO;
    option.isAccessibilityElement = YES;
    option.accessibilityTraits = UIAccessibilityTraitButton;
    option.accessibilityLabel = self.optionLabels[index];
    option.tag = (NSInteger)index;   // 下标载荷（不经 viewWithTag: 查找身份）

    ame_SettingRadioDot *radio = [[ame_SettingRadioDot alloc] initWithFrame:CGRectZero];
    UILabel *label = [[UILabel alloc] init];
    label.text = self.optionLabels[index];
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [option addSubview:radio];
    [option addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [option.heightAnchor constraintEqualToConstant:36.0],
        [radio.leadingAnchor constraintEqualToAnchor:option.leadingAnchor constant:8],
        [radio.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
        [radio.widthAnchor constraintEqualToConstant:18],
        [radio.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:radio.trailingAnchor constant:8],
        [label.centerYAnchor constraintEqualToAnchor:option.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:option.trailingAnchor constant:-4],
    ]];
    [option addTarget:self action:@selector(ame_enumTapped:) forControlEvents:UIControlEventTouchUpInside];
    return option;
}

- (void)ame_enumTapped:(UIControl *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    self.selectedIndex = index;
    [self ame_refreshRadioStates];
    if (self.onSelect) self.onSelect(index);
}

- (NSUInteger)ame_optionCount {
    NSUInteger total = 0;
    for (NSArray<UIControl *> *rowOptions in self.optionRows) total += rowOptions.count;
    return total;
}

- (void)ame_reloadSelectedIndex:(NSInteger)index {
    BOOL valid = (index >= 0 && (NSUInteger)index < [self ame_optionCount]);
    self.selectedIndex = valid ? (NSUInteger)index : NSNotFound;
    [self ame_refreshRadioStates];
}

- (NSUInteger)ame_selectedIndex {
    return self.selectedIndex;
}

- (void)ame_refreshRadioStates {
    for (NSArray<UIControl *> *rowOptions in self.optionRows) {
        for (UIControl *option in rowOptions) {
            ame_SettingRadioDot *radio = nil;
            for (UIView *sub in option.subviews) {
                if ([sub isKindOfClass:[ame_SettingRadioDot class]]) { radio = (ame_SettingRadioDot *)sub; break; }
            }
            [radio ame_setSelected:((NSUInteger)option.tag == self.selectedIndex)];
        }
    }
}

@end
