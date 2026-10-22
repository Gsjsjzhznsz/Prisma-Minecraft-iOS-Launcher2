//
// ZL2SearchIdViewController.m — ZL2 按项目 ID 直查页（结构契约见 .h）
//

#import "ZL2SearchIdViewController.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2FavoritesStore.h"

#include <stdlib.h>

#pragma mark - API 双源本地最小类声明（7.0-UI-10-f import 手术判例同款：
#pragma mark 真实头依赖链在预览 TU 会与桩实现撞符号，消费方 TU 自含声明，
#pragma mark 选择器一一对应；主构建由桩/真实实现按链接目标自洽）

@interface ModrinthAPI : NSObject
+ (instancetype)sharedInstance;
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
@end

@interface CurseForgeAPI : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)isSourceAvailable;
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
@end

@interface ZL2SearchIdViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *idField;
@property (nonatomic, strong) NSMutableArray<UIControl *> *platformChips;
@property (nonatomic, strong) NSMutableArray<UILabel *> *platformChipLabels;
@property (nonatomic, assign) NSInteger platform;   // 1 = Modrinth / 2 = CurseForge
@property (nonatomic, strong) UIControl *searchButton;

@property (nonatomic, strong) UIView *resultCard;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *downloadsLabel;
@property (nonatomic, strong) UILabel *categoriesLabel;
@property (nonatomic, strong) UIControl *favoriteButton;
@property (nonatomic, strong) UILabel *favoriteLabel;
@property (nonatomic, strong) UIControl *openLinkButton;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong, nullable) NSDictionary *fetchedProject;
@end

@implementation ZL2SearchIdViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    _platform = 1;
    [self ame_buildViews];
}

#pragma mark - 布局

- (void)ame_buildViews {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    _idField = [[UITextField alloc] init];
    _idField.placeholder = @"项目 ID / 别名（slug）";
    _idField.font = [ZL2Theme fontBodyMedium];
    _idField.textColor = [ZL2Theme onSurface];
    _idField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"项目 ID / 别名（slug）"
                                        attributes:@{NSForegroundColorAttributeName: [ZL2Theme onSurfaceVariant]}];
    _idField.backgroundColor = [ZL2Theme surfaceContainer];
    _idField.layer.cornerRadius = [ZL2Theme radiusS];
    _idField.delegate = self;
    _idField.returnKeyType = UIReturnKeySearch;
    _idField.autocorrectionType = UITextAutocorrectionTypeNo;
    _idField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _idField.leftView = leftPad;
    _idField.leftViewMode = UITextFieldViewModeAlways;
    _idField.translatesAutoresizingMaskIntoConstraints = NO;
    _idField.isAccessibilityElement = YES;
    _idField.accessibilityLabel = @"项目 ID 输入";
    [self.view addSubview:_idField];

    // 平台 chips（ZL2 PlatformListLayout 语义：Modrinth / CurseForge 单选）
    _platformChips = [NSMutableArray array];
    _platformChipLabels = [NSMutableArray array];
    UIStackView *chips = [[UIStackView alloc] init];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 8;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:chips];
    NSArray<NSString *> *platforms = @[@"Modrinth", @"CurseForge"];
    [platforms enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
        UIControl *chip = [[UIControl alloc] init];
        chip.backgroundColor = [ZL2Theme surfaceContainer];
        chip.layer.cornerRadius = [ZL2Theme radiusS];
        chip.layer.borderWidth = 1.0;
        chip.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.isAccessibilityElement = YES;
        chip.accessibilityLabel = name;
        [chip addTarget:self
                 action:@selector(ame_platformTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        chip.tag = (NSInteger)(idx + 1);
        UILabel *label = [[UILabel alloc] init];
        label.text = name;
        label.font = [ZL2Theme fontLabelMedium];
        label.textColor = [ZL2Theme onSurfaceVariant];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.userInteractionEnabled = NO;
        [chip addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:chip.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:chip.leadingAnchor constant:12],
            [chip.trailingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
            [chip.heightAnchor constraintEqualToConstant:32],
        ]];
        [chips addArrangedSubview:chip];
        [_platformChips addObject:chip];
        [_platformChipLabels addObject:label];
    }];

    _searchButton = [[UIControl alloc] init];
    _searchButton.backgroundColor = [ZL2Theme primary];
    _searchButton.layer.cornerRadius = [ZL2Theme radiusS];
    _searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    _searchButton.isAccessibilityElement = YES;
    _searchButton.accessibilityLabel = @"查询";
    [_searchButton addTarget:self
                      action:@selector(ame_searchTapped)
            forControlEvents:UIControlEventTouchUpInside];
    UILabel *searchLabel = [[UILabel alloc] init];
    searchLabel.text = @"查询";
    searchLabel.font = [ZL2Theme fontLabelLarge];
    searchLabel.textColor = [ZL2Theme onPrimary];
    searchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    searchLabel.userInteractionEnabled = NO;
    [_searchButton addSubview:searchLabel];
    [self.view addSubview:_searchButton];

    // 结果卡（ZL2 ResultProjectLayout 简化：图标 + 标题/作者 + 描述 + 统计 + 标签）
    _resultCard = [[UIView alloc] init];
    _resultCard.backgroundColor = [ZL2Theme surfaceBright];
    _resultCard.layer.cornerRadius = [ZL2Theme radiusL];
    _resultCard.translatesAutoresizingMaskIntoConstraints = NO;
    _resultCard.hidden = YES;
    [self.view addSubview:_resultCard];

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.layer.cornerRadius = [ZL2Theme radiusS];
    _iconView.clipsToBounds = YES;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_titleLabel];

    _authorLabel = [[UILabel alloc] init];
    _authorLabel.font = [ZL2Theme fontLabelMedium];
    _authorLabel.textColor = [ZL2Theme onSurfaceVariant];
    _authorLabel.numberOfLines = 1;
    _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_authorLabel];

    _descLabel = [[UILabel alloc] init];
    _descLabel.font = [ZL2Theme fontBodyMedium];
    _descLabel.textColor = [ZL2Theme onSurfaceVariant];
    _descLabel.numberOfLines = 2;
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_descLabel];

    _downloadsLabel = [[UILabel alloc] init];
    _downloadsLabel.font = [ZL2Theme fontLabelMedium];
    _downloadsLabel.textColor = [ZL2Theme onSurfaceVariant];
    _downloadsLabel.numberOfLines = 1;
    _downloadsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_downloadsLabel];

    _categoriesLabel = [[UILabel alloc] init];
    _categoriesLabel.font = [ZL2Theme fontLabelMedium];
    _categoriesLabel.textColor = [ZL2Theme onSurfaceVariant];
    _categoriesLabel.numberOfLines = 1;
    _categoriesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_resultCard addSubview:_categoriesLabel];

    _favoriteButton = [[UIControl alloc] init];
    _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteButton.isAccessibilityElement = YES;
    _favoriteButton.accessibilityLabel = @"收藏";
    [_favoriteButton addTarget:self
                        action:@selector(ame_favoriteTapped)
              forControlEvents:UIControlEventTouchUpInside];
    UIImageView *heartIcon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:@"heart"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    heartIcon.tintColor = [ZL2Theme onSurfaceVariant];
    heartIcon.contentMode = UIViewContentModeScaleAspectFit;
    heartIcon.translatesAutoresizingMaskIntoConstraints = NO;
    heartIcon.userInteractionEnabled = NO;
    heartIcon.tag = 101;
    [_favoriteButton addSubview:heartIcon];
    [_resultCard addSubview:_favoriteButton];

    _openLinkButton = [[UIControl alloc] init];
    _openLinkButton.backgroundColor = [ZL2Theme surfaceContainer];
    _openLinkButton.layer.cornerRadius = [ZL2Theme radiusS];
    _openLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    _openLinkButton.isAccessibilityElement = YES;
    _openLinkButton.accessibilityLabel = @"在浏览器打开";
    [_openLinkButton addTarget:self
                        action:@selector(ame_openLinkTapped)
              forControlEvents:UIControlEventTouchUpInside];
    UILabel *linkLabel = [[UILabel alloc] init];
    linkLabel.text = @"在浏览器打开项目页";
    linkLabel.font = [ZL2Theme fontLabelLarge];
    linkLabel.textColor = [ZL2Theme primary];
    linkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    linkLabel.userInteractionEnabled = NO;
    [_openLinkButton addSubview:linkLabel];
    [_resultCard addSubview:_openLinkButton];

    // 状态件
    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [ZL2Theme onSurfaceVariant];
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.text = @"输入项目 ID 或 slug，选择平台后查询";
    _statusLabel.font = [ZL2Theme fontBodyLarge];
    _statusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    UILayoutGuide *cardLG = _resultCard.layoutMarginsGuide;
    _resultCard.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 12);
    [NSLayoutConstraint activateConstraints:@[
        [_idField.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_idField.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_idField.heightAnchor constraintEqualToConstant:40],

        [chips.centerYAnchor constraintEqualToAnchor:_idField.centerYAnchor],
        [chips.leadingAnchor constraintGreaterThanOrEqualToAnchor:_idField.trailingAnchor constant:12],
        [chips.trailingAnchor constraintEqualToAnchor:_searchButton.leadingAnchor constant:-8],

        [_searchButton.centerYAnchor constraintEqualToAnchor:_idField.centerYAnchor],
        [_searchButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_searchButton.widthAnchor constraintEqualToConstant:88],
        [_searchButton.heightAnchor constraintEqualToConstant:40],
        [searchLabel.centerXAnchor constraintEqualToAnchor:_searchButton.centerXAnchor],
        [searchLabel.centerYAnchor constraintEqualToAnchor:_searchButton.centerYAnchor],

        [_resultCard.topAnchor constraintEqualToAnchor:_idField.bottomAnchor constant:16],
        [_resultCard.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_resultCard.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [_iconView.topAnchor constraintEqualToAnchor:cardLG.topAnchor constant:12],
        [_iconView.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:72],
        [_iconView.heightAnchor constraintEqualToConstant:72],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.topAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
        [_authorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],
        [_authorLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_authorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cardLG.trailingAnchor],

        [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_descLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cardLG.trailingAnchor],

        [_downloadsLabel.topAnchor constraintEqualToAnchor:_descLabel.bottomAnchor constant:4],
        [_downloadsLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],

        [_categoriesLabel.topAnchor constraintEqualToAnchor:_downloadsLabel.bottomAnchor constant:2],
        [_categoriesLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_categoriesLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_favoriteButton.leadingAnchor constant:-8],

        [_favoriteButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_favoriteButton.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],
        [_favoriteButton.widthAnchor constraintEqualToConstant:32],
        [_favoriteButton.heightAnchor constraintEqualToConstant:32],
        [heartIcon.centerXAnchor constraintEqualToAnchor:_favoriteButton.centerXAnchor],
        [heartIcon.centerYAnchor constraintEqualToAnchor:_favoriteButton.centerYAnchor],
        [heartIcon.widthAnchor constraintEqualToConstant:22],
        [heartIcon.heightAnchor constraintEqualToConstant:22],

        [_openLinkButton.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:12],
        [_openLinkButton.leadingAnchor constraintEqualToAnchor:cardLG.leadingAnchor],
        [_openLinkButton.trailingAnchor constraintEqualToAnchor:cardLG.trailingAnchor],
        [_openLinkButton.heightAnchor constraintEqualToConstant:40],
        [linkLabel.centerXAnchor constraintEqualToAnchor:_openLinkButton.centerXAnchor],
        [linkLabel.centerYAnchor constraintEqualToAnchor:_openLinkButton.centerYAnchor],
        [_resultCard.bottomAnchor constraintEqualToAnchor:_openLinkButton.bottomAnchor constant:12],

        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];
}

#pragma mark - 平台切换

- (void)ame_platformTapped:(UIControl *)sender {
    self.platform = sender.tag;
    [self ame_applyPlatformAppearance];
}

- (void)ame_applyPlatformAppearance {
    for (NSUInteger i = 0; i < self.platformChips.count; i++) {
        UIControl *chip = self.platformChips[i];
        BOOL selected = (chip.tag == self.platform);
        chip.backgroundColor = selected ? [ZL2Theme secondaryContainer] : [ZL2Theme surfaceContainer];
        self.platformChipLabels[i].textColor = selected ? [ZL2Theme onSecondaryContainer]
                                                        : [ZL2Theme onSurfaceVariant];
    }
}

#pragma mark - 查询（ZL2 SearchIdScreen 状态机语义：Loading/Result/NotFound/Error）

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self ame_searchTapped];
    return YES;
}

- (void)ame_searchTapped {
    [self.idField resignFirstResponder];
    NSString *query = [self.idField.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) return;

    self.fetchedProject = nil;
    self.resultCard.hidden = YES;
    self.statusLabel.hidden = YES;
    [self.spinner startAnimating];

    NSString *endpoint = nil;
    if (self.platform == 1) {
        // Modrinth：ID 或 slug 均可直达 /project/{id|slug}
        endpoint = [NSString stringWithFormat:@"project/%@",
                    [query stringByAddingPercentEncodingWithAllowedCharacters:
                     [NSCharacterSet URLPathAllowedCharacterSet]]];
    } else {
        // CurseForge：/mods/{id}（数字 ID）
        endpoint = [NSString stringWithFormat:@"mods/%@", query];
    }

    __weak typeof(self) weakSelf = self;
    id api = (self.platform == 1) ? (id)[ModrinthAPI sharedInstance]
                                  : (id)[CurseForgeAPI sharedInstance];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        id response = [api getEndpoint:endpoint params:nil];
        // CurseForge 响应带 data 包裹（响应字段解包在外层 block 完成，
        // 避免嵌套 block 对局部变量的 __block 要求）
        if (self.platform == 2 && [response isKindOfClass:[NSDictionary class]]) {
            response = response[@"data"] ?: response;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;
            [s.spinner stopAnimating];
            if (!response) {
                s.statusLabel.text = @"查询失败：项目不存在或网络异常";
                s.statusLabel.hidden = NO;
                return;
            }
            [s ame_applyResult:response];
        });
    });
}

/// 平台响应 → 统一展示字典（Modrinth hit / CurseForge data 字段映射）
- (void)ame_applyResult:(NSDictionary *)raw {
    NSString *title = raw[@"title"] ?: raw[@"name"] ?: @"";
    NSString *desc = raw[@"description"] ?: raw[@"summary"] ?: @"";
    NSString *iconUrl = raw[@"icon_url"] ?: raw[@"iconUrl"] ?: @"";
    NSString *author = raw[@"author"] ?: @"";
    if (author.length == 0 && [raw[@"authors"] isKindOfClass:[NSArray class]] &&
        [raw[@"authors"] count] > 0) {
        author = raw[@"authors"][0][@"name"] ?: @"";
    }
    NSNumber *downloads = raw[@"downloads"] ?: raw[@"downloadCount"] ?: @0;
    NSArray *categories = raw[@"categories"] ?: raw[@"display_categories"] ?: @[];
    NSString *projectId = raw[@"project_id"] ?: raw[@"id"] ?: @"";
    if (![projectId isKindOfClass:[NSString class]]) {
        projectId = [projectId description] ?: @"";
    }
    NSString *slug = raw[@"slug"] ?: projectId;
    NSString *projectType = raw[@"project_type"] ?: @"";

    self.fetchedProject = @{
        @"platform": @(self.platform),
        @"projectId": projectId,
        @"title": title ?: @"",
        @"description": desc ?: @"",
        @"imageUrl": iconUrl ?: @"",
        @"author": author ?: @"",
        @"downloads": downloads ?: @0,
        @"projectType": projectType ?: @"",
        @"slug": slug ?: @"",
        @"categories": categories ?: @[],
    };

    self.titleLabel.text = title;
    self.authorLabel.text = author.length > 0 ? [NSString stringWithFormat:@"作者：%@", author] : @"";
    self.descLabel.text = desc;
    self.downloadsLabel.text = [NSString stringWithFormat:@"下载 %@", downloads];
    self.categoriesLabel.text = [categories componentsJoinedByString:@" · "];

    if (iconUrl.length > 0) {
        [self ame_loadIcon:iconUrl];
    }
    [self ame_refreshFavoriteState];
    self.resultCard.hidden = NO;
}

- (void)ame_loadIcon:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            s.iconView.image = image;
        });
    }];
    [task resume];
}

#pragma mark - 收藏 + 浏览器

- (void)ame_refreshFavoriteState {
    if (!self.fetchedProject) return;
    BOOL fav = [[ZL2FavoritesStore sharedStore]
        isFavoritePlatform:self.platform
                 projectId:self.fetchedProject[@"projectId"]];
    UIImageView *heart = [self.favoriteButton viewWithTag:101];
    heart.image = [UIImage systemImageNamed:(fav ? @"heart.fill" : @"heart")];
    heart.tintColor = fav ? [ZL2Theme tertiary] : [ZL2Theme onSurfaceVariant];
}

- (void)ame_favoriteTapped {
    if (!self.fetchedProject) return;
    [[ZL2FavoritesStore sharedStore] toggleFavoriteWithProject:self.fetchedProject];
    [self ame_refreshFavoriteState];
}

- (void)ame_openLinkTapped {
    if (!self.fetchedProject) return;
    NSString *urlString = nil;
    if (self.platform == 1) {
        urlString = [NSString stringWithFormat:@"https://modrinth.com/mod/%@", self.fetchedProject[@"slug"]];
        if ([self.fetchedProject[@"projectType"] isEqualToString:@"modpack"]) {
            urlString = [NSString stringWithFormat:@"https://modrinth.com/modpack/%@", self.fetchedProject[@"slug"]];
        }
    } else {
        urlString = [NSString stringWithFormat:@"https://www.curseforge.com/projects/%@", self.fetchedProject[@"slug"]];
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end
