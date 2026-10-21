//
// FluentListCell.m — fluent2_kit fluent_list_view 规格的 ObjC 实现
//

#import "FluentListCell.h"
#import "AmeTheme.h"

@implementation FluentListCell {
    BOOL _multi;
    UIStackView *_textStack;
    NSLayoutConstraint *_height;
}

+ (instancetype)oneLineCellWithReuseIdentifier:(NSString *)identifier {
    FluentListCell *c = [self ame_cellWithIdentifier:identifier multi:NO];
    return c;
}

+ (instancetype)multiLineCellWithReuseIdentifier:(NSString *)identifier {
    return [self ame_cellWithIdentifier:identifier multi:YES];
}

+ (instancetype)ame_cellWithIdentifier:(NSString *)identifier multi:(BOOL)multi {
    FluentListCell *c = [[FluentListCell alloc] initWithStyle:(multi ? UITableViewCellStyleSubtitle
                                                                    : UITableViewCellStyleDefault)
                                             reuseIdentifier:identifier];
    return c;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        _multi = (style == UITableViewCellStyleSubtitle);
        self.backgroundColor = [AmeTheme surfaceCard];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.layer.cornerRadius = [AmeTheme radiusM];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        // 前导图标（20pt，fg2 tint）
        _leadingIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        _leadingIcon.contentMode = UIViewContentModeScaleAspectFit;
        _leadingIcon.tintColor = [AmeTheme textSecondary];
        _leadingIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_leadingIcon];

        // 文本栈
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [AmeTheme fontBody];
        _titleLabel.textColor = [AmeTheme textPrimary];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel]];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.spacing = 2;
        _textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_textStack];

        if (_multi) {
            _subtitleLabel = [[UILabel alloc] init];
            _subtitleLabel.font = [AmeTheme fontBody2];
            _subtitleLabel.textColor = [AmeTheme textSecondary];
            _subtitleLabel.numberOfLines = 2;
            [_textStack addArrangedSubview:_subtitleLabel];
        }

        // 右侧辅助文本（fg3 caption1）
        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [AmeTheme fontCaption];
        _detailLabel.textColor = [AmeTheme textTertiary];
        _detailLabel.setContentCompressionResistancePriority(UILayoutPriorityRequired - 1,
                                                             forHorizontalAxis);
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_detailLabel];

        CGFloat height = _multi ? 64.0 : 44.0;
        _height = [self.contentView.heightAnchor constraintEqualToConstant:height];
        _height.active = YES;

        [NSLayoutConstraint activateConstraints:@[
            [_leadingIcon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_leadingIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_leadingIcon.widthAnchor constraintEqualToConstant:20],
            [_leadingIcon.heightAnchor constraintEqualToConstant:20],

            [_textStack.leadingAnchor constraintEqualToAnchor:_leadingIcon.trailingAnchor constant:12],
            [_textStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_detailLabel.leadingAnchor constant:-8],

            [_detailLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_detailLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    // Fluent 行按压态：bg5 实底反白
    self.backgroundColor = highlighted ? [AmeTheme fillSubtle] : [AmeTheme surfaceCard];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.highlighted) self.backgroundColor = [AmeTheme fillSubtle];
}

@end
