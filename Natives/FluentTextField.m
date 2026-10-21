//
// FluentTextField.m — fluent2_kit fluent_text_field 规格的 ObjC 实现
//

#import "FluentTextField.h"
#import "AmeTheme.h"

@implementation FluentTextField {
    UILabel *_fieldLabel;
    UIView *_fieldBox;
    UILabel *_helperLabel;
    NSLayoutConstraint *_boxHeight;
}

- (instancetype)initWithFieldLabel:(NSString *)fieldLabel
                       placeholder:(NSString *)placeholder
                        isRequired:(BOOL)isRequired {
    if (self = [super initWithFrame:CGRectZero]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _fieldBox = [[UIView alloc] init];
        _fieldBox.translatesAutoresizingMaskIntoConstraints = NO;
        _fieldBox.layer.cornerRadius = [AmeTheme radiusM];
        _fieldBox.layer.cornerCurve = kCACornerCurveContinuous;
        _fieldBox.layer.borderWidth = 1.0;
        [self addSubview:_fieldBox];

        _textField = [[UITextField alloc] init];
        _textField.placeholder = placeholder;
        _textField.font = [AmeTheme fontBody];
        _textField.textColor = [AmeTheme textPrimary];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.delegate = (id<UITextFieldDelegate>)self;
        [_fieldBox addSubview:_textField];

        NSLayoutConstraint *labelTop = nil;
        if (fieldLabel.length > 0) {
            _fieldLabel = [[UILabel alloc] init];
            _fieldLabel.font = [AmeTheme fontCaption];
            _fieldLabel.textColor = [AmeTheme textSecondary];
            _fieldLabel.text = isRequired ? [fieldLabel stringByAppendingString:@" *"] : fieldLabel;
            _fieldLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:_fieldLabel];
            labelTop = [_fieldLabel.topAnchor constraintEqualToAnchor:self.topAnchor];
        }

        _boxHeight = [_fieldBox.heightAnchor constraintEqualToConstant:40.0];
        _boxHeight.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [NSLayoutConstraint constraintWithItem:_fieldBox attribute:NSLayoutAttributeTop
                                        relatedBy:NSLayoutRelationEqual
                                           toItem:(fieldLabel.length > 0 ? _fieldLabel : self)
                                        attribute:NSLayoutAttributeBottom
                                       multiplier:1.0 constant:(fieldLabel.length > 0 ? 6 : 0)],
            [_fieldBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_fieldBox.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_textField.leadingAnchor constraintEqualToAnchor:_fieldBox.leadingAnchor constant:12],
            [_textField.trailingAnchor constraintEqualToAnchor:_fieldBox.trailingAnchor constant:-12],
            [_textField.topAnchor constraintEqualToAnchor:_fieldBox.topAnchor],
            [_textField.bottomAnchor constraintEqualToAnchor:_fieldBox.bottomAnchor],
        ]];
        if (labelTop) labelTop.active = YES;

        _helperLabel = [[UILabel alloc] init];
        _helperLabel.font = [AmeTheme fontCaption];
        _helperLabel.numberOfLines = 0;
        _helperLabel.hidden = YES;
        _helperLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_helperLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_helperLabel.topAnchor constraintEqualToAnchor:_fieldBox.bottomAnchor constant:4],
            [_helperLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_helperLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [_helperLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        [self ame_applyState];
        // 焦点态切换
        [_textField addTarget:self action:@selector(ame_applyState)
                     forControlEvents:UIControlEventEditingDidBegin | UIControlEventEditingDidEnd];
    }
    return self;
}

- (void)setHelperText:(NSString *)helperText {
    _helperText = [helperText copy];
    _helperLabel.text = helperText;
    _helperLabel.hidden = (helperText.length == 0);
}

- (void)setErrorShown:(BOOL)errorShown {
    _errorShown = errorShown;
    [self ame_applyState];
}

// 状态机：rest（bg5 底/stroke1 边）→ focus（surfaceCard 底/brand 2px 边）
//       → error（surfaceCard 底/danger 2px 边 + helper danger 色）
- (void)ame_applyState {
    BOOL focused = _textField.isEditing;
    if (_errorShown) {
        _fieldBox.backgroundColor = [AmeTheme surfaceCard];
        _fieldBox.layer.borderColor = [AmeTheme statusDanger].CGColor;
        _fieldBox.layer.borderWidth = 2.0;
        _helperLabel.textColor = [AmeTheme statusDanger];
    } else if (focused) {
        _fieldBox.backgroundColor = [AmeTheme surfaceCard];
        _fieldBox.layer.borderColor = [AmeTheme brandPrimary].CGColor;
        _fieldBox.layer.borderWidth = 2.0;
        _helperLabel.textColor = [AmeTheme textTertiary];
    } else {
        _fieldBox.backgroundColor = [AmeTheme fillSubtle];
        _fieldBox.layer.borderColor = [AmeTheme divider].CGColor;
        _fieldBox.layer.borderWidth = 1.0;
        _helperLabel.textColor = [AmeTheme textTertiary];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self ame_applyState];
}

// delegate 兜底（某些第三方键盘事件不触发 Editing 事件对）
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField { [self ame_applyState]; return YES; }
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField  { [self ame_applyState]; return YES; }

@end
