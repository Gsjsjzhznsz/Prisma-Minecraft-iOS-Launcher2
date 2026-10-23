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
        BOOL declared = [self.manifest.permissions containsObject:item.permissionId];
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
        sw.userInteractionEnabled = declared && self.manifest != nil;
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
