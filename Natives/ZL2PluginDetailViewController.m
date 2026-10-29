#import "ZL2PluginDetailViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "utils.h" // localize

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginDetailViewController 实现（Task 317）
// 表结构：0=信息卡 1=启用开关 2=权限组（manifest 声明 + 未声明的全部组灰态）
//        3=卸载（destructive 确认）
// ═══════════════════════════════════════════════════════════════════

@interface ZL2PluginDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, copy) NSString *pluginId;
@property (nonatomic, strong) AmePluginManifest *manifest;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<AmePluginPermissionItem *> *permItems;
@property (nonatomic, assign) CGFloat ame345_lastHeroWidth;
@end

@implementation ZL2PluginDetailViewController

- (instancetype)initWithPluginId:(NSString *)pluginId {
    self = [super init];
    if (self) {
        _pluginId = [pluginId copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.title = self.pluginId;
    self.manifest = [AmePluginManager manifestForPlugin:self.pluginId];
    self.permItems = [AmePluginPermissions allPermissions];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.delegate = self;
    self.table.dataSource = self;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self ame345_installHeroHeader];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ame345_remindHeroHeaderIfNeeded];
}

#pragma mark - Task345 hero 身份卡（信息节升级）

// 原信息节是单张系统 cell 里的三行字（v/作者/简介挤 detailTextLabel）。
// 重排为页首 hero 卡：56pt 图标瓦片 + 标题字阶大标题 + 版本·作者元行 +
// 多行简介段落；圆角/边距/字阶全走令牌（ame341/ame343 覆盖即生效）。
- (void)ame345_installHeroHeader {
    CGFloat mH = [ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0];
    CGFloat inX = [ZL2Theme ame343_layoutMetric:@"cardInsetX" fallback:14.0];
    CGFloat inT = [ZL2Theme ame343_layoutMetric:@"cardInsetTop" fallback:12.0];
    CGFloat inB = [ZL2Theme ame343_layoutMetric:@"cardInsetBottom" fallback:12.0];
    CGFloat gap = [ZL2Theme ame343_layoutMetric:@"cardContentGap" fallback:4.0];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [ZL2Theme surfaceBright];
    card.layer.cornerRadius = [ZL2Theme radiusL];
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    card.clipsToBounds = YES;

    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [ZL2Theme primaryContainer];
    tile.layer.cornerRadius = [ZL2Theme radiusM];
    tile.clipsToBounds = YES;
    UIImageView *tileIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"puzzlepiece.extension"]];
    tileIcon.translatesAutoresizingMaskIntoConstraints = NO;
    tileIcon.contentMode = UIViewContentModeScaleAspectFit;
    tileIcon.tintColor = [ZL2Theme onPrimaryContainer];
    [tile addSubview:tileIcon];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.numberOfLines = 1;
    nameLabel.text = self.manifest ? (self.manifest.name ?: self.pluginId) : self.pluginId;
    nameLabel.font = [ZL2Theme fontHeadline];
    nameLabel.textColor = [ZL2Theme onSurface];

    UILabel *metaLabel = [[UILabel alloc] init];
    metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    metaLabel.numberOfLines = 1;
    metaLabel.font = [ZL2Theme fontLabelMedium];
    metaLabel.textColor = [ZL2Theme onSurfaceVariant];
    if (self.manifest) {
        NSString *authorLine = self.manifest.author.length
            ? [NSString stringWithFormat:localize(@"ame317.list.by_author", nil), self.manifest.author] : @"-";
        metaLabel.text = [NSString stringWithFormat:@"v%@ · %@",
                          self.manifest.version ?: @"?", authorLine];
    } else {
        metaLabel.text = localize(@"ame317.detail.broken", nil);
    }

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.numberOfLines = 0;
    descLabel.font = [ZL2Theme fontBodyMedium];
    descLabel.textColor = [ZL2Theme onSurfaceVariant];
    descLabel.text = self.manifest ? (self.manifest.summary ?: @"") : @"";

    [card addSubview:tile];
    [card addSubview:nameLabel];
    [card addSubview:metaLabel];
    [card addSubview:descLabel];

    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inX],
        [tile.topAnchor constraintEqualToAnchor:card.topAnchor constant:inT],
        [tile.widthAnchor constraintEqualToConstant:56.0],
        [tile.heightAnchor constraintEqualToConstant:56.0],
        [tileIcon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [tileIcon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [tileIcon.widthAnchor constraintEqualToConstant:28.0],
        [tileIcon.heightAnchor constraintEqualToConstant:28.0],

        [nameLabel.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:gap + inX],
        [nameLabel.bottomAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-1.0],
        [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-inX],

        [metaLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [metaLabel.topAnchor constraintEqualToAnchor:tile.centerYAnchor constant:1.0],
        [metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-inX],

        [descLabel.topAnchor constraintEqualToAnchor:tile.bottomAnchor constant:inT],
        [descLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inX],
        [descLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inX],
        [descLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inB],
    ]];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:6.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:mH],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-mH],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:0],
    ]];
    self.table.tableHeaderView = header;
    self.ame345_lastHeroWidth = 0;
}

- (void)ame345_remindHeroHeaderIfNeeded {
    UIView *header = self.table.tableHeaderView;
    if (!header) return;
    CGFloat width = CGRectGetWidth(self.table.bounds);
    if (width <= 0 || fabs(width - self.ame345_lastHeroWidth) < 0.5) return;
    self.ame345_lastHeroWidth = width;
    [header setNeedsLayout];
    [header layoutIfNeeded];
    CGFloat h = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGRect f = header.frame;
    f.size.height = h;
    header.frame = f;
    self.table.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table reloadData];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 2) return self.permItems.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return localize(@"ame317.detail.section_info", nil);
        case 1: return localize(@"ame317.detail.section_runtime", nil);
        case 2: return localize(@"ame317.detail.section_perms", nil);
        default: return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kId = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId forIndexPath:indexPath];
    cell.backgroundColor = [ZL2Theme surfaceBright];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;

    if (indexPath.section == 0) {
        AmePluginManifest *m = self.manifest;
        cell.textLabel.text = m ? (m.name ?: self.pluginId) : self.pluginId;
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = [ZL2Theme onSurface];
        if (m) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@\n%@\n%@",
                                         m.version ?: @"?",
                                         m.author ?: @"-",
                                         m.summary ?: @""];
        } else {
            cell.detailTextLabel.text = localize(@"ame317.detail.broken", nil);
        }
        cell.detailTextLabel.font = [ZL2Theme fontBodyMedium];
        cell.detailTextLabel.textColor = [ZL2Theme onSurfaceVariant];
    } else if (indexPath.section == 1) {
        cell.textLabel.text = localize(@"ame317.detail.enabled", nil);
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = [ZL2Theme onSurface];
        ZL2M3Switch *sw = [[ZL2M3Switch alloc] init];
        sw.on = [AmePluginRuntime isRunning:self.pluginId];
        [sw addTarget:self action:@selector(ame317_enableToggled:)
             forControlEvents:UIControlEventValueChanged];
        UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [ZL2M3Switch switchWidth] + 16, [ZL2M3Switch switchHeight])];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[
            [sw.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
            [sw.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        ]];
        cell.accessoryView = wrap;
    } else if (indexPath.section == 2) {
        AmePluginPermissionItem *item = self.permItems[(NSUInteger)indexPath.row];
        // ★ Task333：完全接管交互 —— ame.super 恒可切（用户侧主控开关，
        //   不要求 manifest 声明）；接管已开时其余权限开关全部变灰禁用
        //   （语义：接管态下逐项开关无执法意义），文本同步降透明度。
        BOOL ame333_isSuper = [item.permissionId isEqualToString:@"ame.super"];
        BOOL ame333_superGranted = [AmePluginPermissions pluginHasGrant:self.pluginId
                                                             permission:@"ame.super"];
        BOOL declared = ame333_isSuper ||
                        [self.manifest.permissions containsObject:item.permissionId];
        BOOL granted = [AmePluginPermissions pluginHasGrant:self.pluginId
                                                 permission:item.permissionId];
        cell.textLabel.text = [NSString stringWithFormat:@"%@%@",
                               item.danger ? @"⚠ " : @"",
                               localize(item.nameKey, nil)];
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = item.danger
            ? [ZL2Theme error]
            : (declared ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant]);
        NSString *desc = localize(item.descKey, nil);
        cell.detailTextLabel.text = declared ? desc
            : [NSString stringWithFormat:localize(@"ame317.detail.not_declared", nil), desc];
        cell.detailTextLabel.font = [ZL2Theme fontBodyMedium];
        cell.detailTextLabel.textColor = [ZL2Theme onSurfaceVariant];

        ZL2M3Switch *sw = [[ZL2M3Switch alloc] init];
        sw.on = granted;
        sw.userInteractionEnabled = ame333_isSuper
            ? (self.manifest != nil)
            : (!ame333_superGranted && declared && self.manifest != nil);
        sw.alpha = (!ame333_isSuper && ame333_superGranted) ? 0.35 : 1.0;
        cell.textLabel.alpha = (!ame333_isSuper && ame333_superGranted) ? 0.45 : 1.0;
        cell.detailTextLabel.alpha = (!ame333_isSuper && ame333_superGranted) ? 0.45 : 1.0;
        sw.tag = indexPath.row;
        [sw addTarget:self action:@selector(ame317_permToggled:)
             forControlEvents:UIControlEventValueChanged];
        UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [ZL2M3Switch switchWidth] + 16, [ZL2M3Switch switchHeight])];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[
            [sw.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
            [sw.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        ]];
        cell.accessoryView = wrap;
    } else {
        cell.textLabel.text = localize(@"ame317.detail.uninstall", nil);
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = [ZL2Theme error];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        [ZL2M3Dialog showTitle:localize(@"ame317.detail.uninstall_confirm_title", nil)
                           body:[NSString stringWithFormat:
                                 localize(@"ame317.detail.uninstall_confirm_body", nil), self.pluginId]
                   confirmTitle:localize(@"ame317.detail.uninstall", nil)
                    destructive:YES
                     onConfirm:^{ [self ame317_uninstall]; }
                      onCancel:nil];
    }
}

#pragma mark - 动作

- (void)ame317_enableToggled:(ZL2M3Switch *)sender {
    // ZL2M3Kit 契约：UI 点击内部已自动翻转，sender.on 即新值
    BOOL next = sender.on;
    [AmePluginRuntime setPluginEnabled:self.pluginId enabled:next];
    [self.table reloadData];
}

- (void)ame317_permToggled:(ZL2M3Switch *)sender {
    AmePluginPermissionItem *item = self.permItems[(NSUInteger)sender.tag];
    // ZL2M3Kit 契约：UI 点击内部已自动翻转，sender.on 即新值
    BOOL next = sender.on;
    [AmePluginPermissions setGrant:next forPlugin:self.pluginId permission:item.permissionId];
    // 运行中插件：静默重载保证贡献行/主题令牌与权限一致
    // （撤 ui.theme → 重载后 storage 重放因无授权不再应用；撤 ui.rows → 行清空）
    if ([AmePluginRuntime isRunning:self.pluginId]) {
        BOOL enabled = [AmePluginPermissions pluginEnabled:self.pluginId];
        [AmePluginRuntime setPluginEnabled:self.pluginId enabled:NO];
        if (enabled) {
            [AmePluginRuntime setPluginEnabled:self.pluginId enabled:YES];
        }
    }
    [self.table reloadData];
}

- (void)ame317_uninstall {
    [AmePluginRuntime setPluginEnabled:self.pluginId enabled:NO];
    [AmePluginManager uninstallPlugin:self.pluginId];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
