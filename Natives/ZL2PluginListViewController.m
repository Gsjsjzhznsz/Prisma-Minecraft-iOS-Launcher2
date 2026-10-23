#import "ZL2PluginListViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "utils.h" // localize

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginListViewController 实现（Task 317）
// 口径注释：
//  · 表三区：0=已装插件卡（含启停开关） 1=插件贡献行 2=API 说明行
//  · 安装链：文档选择器(zip) → 后台解压+校验 → 主线程权限确认 M3 对话框
//    （高危权限 ⚠ 标注 + 默认拒绝说明）→ 落位自动启用
//  · 启停开关 = Runtime 装载/卸载；开关即生效，无需重启启动器
//  · 贡献行点按 → Runtime 转发到插件 JS 回调
// ═══════════════════════════════════════════════════════════════════

@interface ZL2PluginListViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *cards;   // {id, manifest, enabled}
@property (nonatomic, strong) NSArray<NSDictionary *> *contributedRows;
@end

@implementation ZL2PluginListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.title = localize(@"ame317.list.title", nil);
    self.cards = [NSMutableArray array];

    UIBarButtonItem *add = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self action:@selector(ame317_pickPluginZip)];
    // Task318：内置插件仓库入口（随包预置插件一键安装）
    UIBarButtonItem *repo = [[UIBarButtonItem alloc]
        initWithTitle:localize(@"ame318.repo.nav", nil)
                 style:UIBarButtonItemStylePlain
                target:self action:@selector(ame318_openRepo)];
    self.navigationItem.rightBarButtonItems = @[add, repo];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    // Task318：不 registerClass——注册类实例化的 UITableViewCell 是 Default 风格，
    // detailTextLabel 恒 nil；Subtitle 风格 cell 在 cellForRow 手建（见下）
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self ame317_reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame317_reload];
}

#pragma mark - 数据装配

- (void)ame317_reload {
    [self.cards removeAllObjects];
    for (NSString *pid in [AmePluginManager installedPluginIds]) {
        AmePluginManifest *m = [AmePluginManager manifestForPlugin:pid];
        if (!m) continue;
        BOOL enabled = [AmePluginPermissions pluginEnabled:pid] &&
                       [AmePluginRuntime isRunning:pid];
        [self.cards addObject:@{@"id": pid, @"manifest": m, @"enabled": @(enabled)}];
    }
    self.contributedRows = [AmePluginRuntime allContributedRows];
    [self.table reloadData];
}

#pragma mark - 安装链

- (void)ame318_openRepo {
    ZL2PluginRepoViewController *repo = [[ZL2PluginRepoViewController alloc] init];
    [self.navigationController pushViewController:repo animated:YES];
}

- (void)ame317_pickPluginZip {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSURL *url = urls[0];
    __weak typeof(self) wself = self;
    [url startAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AmePluginManifest *m = nil;
        AmePluginInstallResult code =
            [AmePluginManager installFromZip:url.path outManifest:&m];
        [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            [wself ame317_installDidFinish:code manifest:m];
        });
    });
}

- (void)ame317_installDidFinish:(AmePluginInstallResult)code manifest:(AmePluginManifest *)m {
    if (code != AmePluginInstallOK) {
        NSString *body;
        switch (code) {
            case AmePluginInstallErrReadZip:    body = localize(@"ame317.install.err_zip", nil); break;
            case AmePluginInstallErrNoManifest: body = localize(@"ame317.install.err_manifest", nil); break;
            case AmePluginInstallErrBadJSON:    body = localize(@"ame317.install.err_json", nil); break;
            case AmePluginInstallErrBadSchema:  body = localize(@"ame317.install.err_schema", nil); break;
            case AmePluginInstallErrBadEntry:   body = localize(@"ame317.install.err_entry", nil); break;
            case AmePluginInstallErrAPITooNew:  body = localize(@"ame317.install.err_api", nil); break;
            case AmePluginInstallErrMove:       body = localize(@"ame317.install.err_move", nil); break;
            default:                            body = localize(@"ame317.install.err_zip", nil); break;
        }
        [ZL2M3Dialog showTitle:localize(@"ame317.install.failed_title", nil)
                           body:body
                   confirmTitle:localize(@"ame317.common.ok", nil)
                    destructive:NO
                     onConfirm:nil
                      onCancel:nil];
        return;
    }

    // 安装结果弹窗（高危 ⚠ 标注；高危默认拒绝——详情页可改）
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *p in m.permissions) {
        BOOL danger = [AmePluginPermissions isDangerous:p];
        [lines addObject:[NSString stringWithFormat:@"%@ %@",
            danger ? @"⚠" : @"·", localize([NSString stringWithFormat:@"ame317.perm.%@.name", p], nil)]];
    }
    NSString *permText = lines.count ? [lines componentsJoinedByString:@"\n"]
                                     : localize(@"ame317.install.no_perms", nil);
    NSString *body = [NSString stringWithFormat:@"%@\n\n%@",
                      localize(@"ame317.install.confirm_body", nil), permText];
    [ZL2M3Dialog showTitle:m.name
                       body:body
               confirmTitle:localize(@"ame317.common.ok", nil)
                destructive:NO
                 onConfirm:nil
                  onCancel:nil];
    // 首装自动装载（bootIfNeeded 已过，不补这一次装机则要用户再手动开一次）
    if ([AmePluginPermissions pluginEnabled:m.pluginId]) {
        [AmePluginRuntime setPluginEnabled:m.pluginId enabled:YES];
    }
    [self ame317_reload];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(self.cards.count, 1); // 空态占位行
    if (section == 1) return self.contributedRows.count;
    return 1; // API 版本说明行
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return localize(@"ame317.list.section_installed", nil);
    if (section == 1) return localize(@"ame317.list.section_rows", nil);
    return localize(@"ame317.list.section_about", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kId = @"cell";
    // Task318 修复：registerClass 体系实例化的 UITableViewCell 是 Default 风格，
    // detailTextLabel 恒 nil → Task317 上线以来副标题（版本/作者/简介）从未显示过。
    // 改为手建 Subtitle 风格 cell（不 registerClass，老 API dequeue 可回池）。
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                              reuseIdentifier:kId];
    cell.backgroundColor = [ZL2Theme surfaceBright];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (self.cards.count == 0) {
            cell.textLabel.text = localize(@"ame317.list.empty", nil);
            cell.textLabel.font = [ZL2Theme fontBodyMedium];
            cell.textLabel.textColor = [ZL2Theme onSurfaceVariant];
            cell.textLabel.numberOfLines = 0;
            return cell;
        }
        NSDictionary *card = self.cards[(NSUInteger)indexPath.row];
        AmePluginManifest *m = card[@"manifest"];
        BOOL enabled = [card[@"enabled"] boolValue];
        NSString *ver = [NSString stringWithFormat:@"v%@", m.version ?: @"?"];
        cell.textLabel.text = m.name ?: m.pluginId;
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = enabled ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
        NSString *authorLine = m.author.length ?
            [NSString stringWithFormat:localize(@"ame317.list.by_author", nil), m.author] : @"";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", ver, authorLine,
                                     m.summary ?: @""];
        cell.detailTextLabel.font = [ZL2Theme fontBodyMedium];
        cell.detailTextLabel.textColor = [ZL2Theme onSurfaceVariant];
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        ZL2M3Switch *sw = [[ZL2M3Switch alloc] init];
        sw.on = enabled;
        sw.tag = indexPath.row;
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
    } else if (indexPath.section == 1) {
        NSDictionary *row = self.contributedRows[(NSUInteger)indexPath.row];
        cell.textLabel.text = row[@"title"] ?: @"";
        cell.textLabel.font = [ZL2Theme fontTitleMedium];
        cell.textLabel.textColor = [ZL2Theme onSurface];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                     localize(@"ame317.list.from_plugin", nil),
                                     row[@"pluginName"] ?: @""];
        cell.detailTextLabel.font = [ZL2Theme fontBodyMedium];
        cell.detailTextLabel.textColor = [ZL2Theme onSurfaceVariant];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = [NSString stringWithFormat:
            localize(@"ame317.list.api_line", nil), [AmePluginManager apiVersion]];
        cell.textLabel.font = [ZL2Theme fontBodyMedium];
        cell.textLabel.textColor = [ZL2Theme onSurfaceVariant];
        cell.textLabel.numberOfLines = 0;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (self.cards.count == 0) return;
        NSDictionary *card = self.cards[(NSUInteger)indexPath.row];
        ZL2PluginDetailViewController *detail =
            [[ZL2PluginDetailViewController alloc] initWithPluginId:card[@"id"]];
        [self.navigationController pushViewController:detail animated:YES];
    } else if (indexPath.section == 1) {
        NSDictionary *row = self.contributedRows[(NSUInteger)indexPath.row];
        [AmePluginRuntime invokeRowTap:row[@"id"]];
    }
}

- (void)ame317_enableToggled:(ZL2M3Switch *)sender {
    // ZL2M3Kit 契约：UI 点击内部已自动翻转 _on 再发 ValueChanged，
    // sender.on 即新值（禁再取反——取反=把用户点击写回去）
    if (self.cards.count == 0) return;
    NSDictionary *card = self.cards[(NSUInteger)sender.tag];
    NSString *pid = card[@"id"];
    BOOL next = sender.on;
    [AmePluginRuntime setPluginEnabled:pid enabled:next];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self ame317_reload];
    });
}

@end
