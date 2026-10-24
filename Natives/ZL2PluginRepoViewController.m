#import "ZL2PluginRepoViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "utils.h" // localize
#import "UnzipKit.h"

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginRepoViewController 实现（Task 318 内置插件仓库）
// 口径注释：
//  · 单区表：0=内置插件卡（已装 → 详情页；未装 → 一键安装钮）
//  · 安装链 = 目录 → 临时 zip → installFromZip（与手动导入同一条
//    全量校验链：manifest schema/entry 防逃逸/首装默认授权普通授高危拒）
//  · 展示名 = ame318.builtin.<id>.name/desc 四表键优先，manifest 兜底
//  · 装完自动装载（enabled 态由首装授权语义决定）；返回列表页时
//    viewWillAppear 全量刷新，本页 reload 只服务本页状态
// ═══════════════════════════════════════════════════════════════════

static NSString *ame318_builtinRoot(void) {
    return [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"builtin-plugins"];
}

@interface ZL2PluginRepoViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items; // {dirName, manifest}
@property (nonatomic, strong) NSMutableSet<NSString *> *installing;  // dirName 防重入
@end

@implementation ZL2PluginRepoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.title = localize(@"ame318.repo.title", nil);
    self.items = [NSMutableArray array];
    self.installing = [NSMutableSet set];

    // ★ Task325：InsetGrouped+系统 Subtitle cell → Plain 卡片流（ZL2M3CardCell）
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 88.0;
    self.table.contentInset = UIEdgeInsetsMake(6, 0, 16, 0);
    [self.table registerClass:[ZL2M3CardCell class] forCellReuseIdentifier:@"ZL2M3CardCell"];
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Task325：系统组头 → 自绘小字标题（onSurfaceVariant + LabelLarge），
    // 语义与 ame318.repo.section_title 不变；frame 头 + autoresizing 宽度弹窗。
    UILabel *secTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 36)];
    secTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    secTitle.text = localize(@"ame318.repo.section_title", nil);
    secTitle.font = [ZL2Theme fontLabelLarge];
    secTitle.textColor = [ZL2Theme onSurfaceVariant];
    secTitle.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 36)];
    hdr.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [hdr addSubview:secTitle];
    [NSLayoutConstraint activateConstraints:@[
        [secTitle.topAnchor constraintEqualToAnchor:hdr.topAnchor constant:8],
        [secTitle.leadingAnchor constraintEqualToAnchor:hdr.leadingAnchor constant:32],
        [secTitle.trailingAnchor constraintEqualToAnchor:hdr.trailingAnchor constant:-32],
        [secTitle.bottomAnchor constraintEqualToAnchor:hdr.bottomAnchor constant:-4],
    ]];
    self.table.tableHeaderView = hdr;

    [self ame318_reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame318_reload];
}

#pragma mark - 数据装配

- (void)ame318_reload {
    [self.items removeAllObjects];
    NSString *root = ame318_builtinRoot();
    NSArray<NSString *> *dirs =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil];
    for (NSString *dirName in [dirs sortedArrayUsingSelector:@selector(compare:)]) {
        if ([dirName hasPrefix:@"."]) continue;
        NSString *manifestPath = [[root stringByAppendingPathComponent:dirName]
                                  stringByAppendingPathComponent:@"manifest.json"];
        NSData *data = [NSData dataWithContentsOfFile:manifestPath];
        if (!data) continue;
        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        AmePluginInstallResult errCode = AmePluginInstallOK;
        AmePluginManifest *m =
            [AmePluginManager validateManifestDictionary:json errCode:&errCode];
        if (!m) {
            // 包内插件由仓库方维护：校验不过直接跳过（不弹窗打扰用户）
            NSLog(@"[AmePluginRepo] builtin '%@' skipped (validate err=%ld)", dirName, (long)errCode);
            continue;
        }
        [self.items addObject:@{@"dirName": dirName, @"manifest": m}];
    }
    [self.table reloadData];
}

#pragma mark - 展示名（四表键优先，manifest 兜底）

- (NSString *)ame318_displayNameForManifest:(AmePluginManifest *)m {
    NSString *key = [NSString stringWithFormat:@"ame318.builtin.%@.name", m.pluginId];
    NSString *v = localize(key, nil);
    return ([v isEqualToString:key] || v.length == 0) ? (m.name ?: m.pluginId) : v;
}

- (NSString *)ame318_displaySummaryForManifest:(AmePluginManifest *)m {
    NSString *key = [NSString stringWithFormat:@"ame318.builtin.%@.desc", m.pluginId];
    NSString *v = localize(key, nil);
    return ([v isEqualToString:key] || v.length == 0) ? (m.summary ?: @"") : v;
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.items.count, 1); // 空态占位行
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // ★ Task325：系统 Subtitle cell → ZL2M3CardCell（卡底/字体/动作胶囊全令牌化）。
    //   未装 = 整行点击安装（动作胶囊展示“安装/安装中”），已装 = 整行进详情页
    //   （胶囊展示“已安装”），交互语义与两态展示解耦。
    ZL2M3CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2M3CardCell"
                                                          forIndexPath:indexPath];
    if (self.items.count == 0) {
        cell.titleLabel.text = localize(@"ame318.repo.empty", nil);
        cell.subLabel.text = @"";
        [cell applyActionStyle:3 title:@""];
        return cell;
    }

    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    AmePluginManifest *m = item[@"manifest"];
    NSString *dirName = item[@"dirName"];
    BOOL installed = ([[AmePluginManager installedPluginIds] containsObject:m.pluginId]);
    BOOL installing = [self.installing containsObject:dirName];

    cell.titleLabel.text = [self ame318_displayNameForManifest:m];
    NSString *authorLine = m.author.length ?
        [NSString stringWithFormat:localize(@"ame317.list.by_author", nil), m.author] : @"";
    cell.subLabel.text = [NSString stringWithFormat:@"v%@ · %@ · %@",
                          m.version ?: @"?", authorLine,
                          [self ame318_displaySummaryForManifest:m]];
    if (installed) {
        [cell applyActionStyle:1 title:localize(@"custom_controls.repo.installed_badge", nil)];
    } else {
        [cell applyActionStyle:0 title:localize(installing ? @"ame318.repo.installing" : @"ame318.repo.install", nil)];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.items.count == 0) return;
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    AmePluginManifest *m = item[@"manifest"];
    if ([[AmePluginManager installedPluginIds] containsObject:m.pluginId]) {
        ZL2PluginDetailViewController *detail =
            [[ZL2PluginDetailViewController alloc] initWithPluginId:m.pluginId];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    // ★ Task325：未装 = 整行点击安装（accessoryView 时代按钮链退役）
    [self ame318_beginInstallForRow:(NSInteger)indexPath.row];
}

#pragma mark - 安装链（目录 → 临时 zip → installFromZip 全量校验链）

- (void)ame318_beginInstallForRow:(NSInteger)row {
    if (self.items.count == 0) return;
    if (row < 0 || row >= (NSInteger)self.items.count) return;
    NSDictionary *item = self.items[(NSUInteger)row];
    NSString *dirName = item[@"dirName"];
    if ([self.installing containsObject:dirName]) return;
    [self.installing addObject:dirName];
    [self.table reloadData];

    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *tmpZip = [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"ame318-builtin-%@.zip", [NSUUID UUID].UUIDString]];
        BOOL zipped = [wself ame318_zipBuiltinPlugin:dirName toPath:tmpZip];
        AmePluginManifest *m = nil;
        AmePluginInstallResult code = zipped
            ? [AmePluginManager installFromZip:tmpZip outManifest:&m]
            : AmePluginInstallErrReadZip;
        [[NSFileManager defaultManager] removeItemAtPath:tmpZip error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [wself.installing removeObject:dirName];
            [wself ame318_installDidFinish:code manifest:m];
        });
    });
}

// 递归收集插件目录全部普通文件（跳过点前缀；相对路径 '/' 分隔作为 zip 条目名）
- (void)ame318_collectFilesUnder:(NSString *)dir
                        relative:(NSString *)rel
                          into:(NSMutableArray<NSString *> *)out {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *name in [entries sortedArrayUsingSelector:@selector(compare:)]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *abs = [dir stringByAppendingPathComponent:name];
        NSString *relPath = rel.length ? [NSString stringWithFormat:@"%@/%@", rel, name] : name;
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:abs isDirectory:&isDir] && isDir) {
            [self ame318_collectFilesUnder:abs relative:relPath into:out];
        } else {
            [out addObject:relPath];
        }
    }
}

- (BOOL)ame318_zipBuiltinPlugin:(NSString *)dirName toPath:(NSString *)zipPath {
    NSString *src = [ame318_builtinRoot() stringByAppendingPathComponent:dirName];
    NSMutableArray<NSString *> *relPaths = [NSMutableArray array];
    [self ame318_collectFilesUnder:src relative:@"" into:relPaths];
    if (relPaths.count == 0) return NO;

    NSError *err = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&err];
    if (!archive) {
        NSLog(@"[AmePluginRepo] UZKArchive init failed: %@", err.localizedDescription ?: @"nil");
        return NO;
    }
    BOOL ok = YES;
    for (NSString *relPath in relPaths) {
        NSData *data = [NSData dataWithContentsOfFile:[src stringByAppendingPathComponent:relPath]];
        if (!data || ![archive writeData:data filePath:relPath error:&err]) {
            NSLog(@"[AmePluginRepo] write entry '%@' failed: %@", relPath, err.localizedDescription ?: @"nil");
            ok = NO;
            break;
        }
    }
    return ok;
}

- (void)ame318_installDidFinish:(AmePluginInstallResult)code manifest:(AmePluginManifest *)m {
    [self.table reloadData];
    if (code != AmePluginInstallOK) {
        NSString *body;
        switch (code) {
            case AmePluginInstallErrReadZip:    body = localize(@"ame318.repo.zip_failed", nil); break;
            case AmePluginInstallErrNoManifest: body = localize(@"ame317.install.err_manifest", nil); break;
            case AmePluginInstallErrBadJSON:    body = localize(@"ame317.install.err_json", nil); break;
            case AmePluginInstallErrBadSchema:  body = localize(@"ame317.install.err_schema", nil); break;
            case AmePluginInstallErrBadEntry:   body = localize(@"ame317.install.err_entry", nil); break;
            case AmePluginInstallErrAPITooNew:  body = localize(@"ame317.install.err_api", nil); break;
            case AmePluginInstallErrMove:       body = localize(@"ame317.install.err_move", nil); break;
            default:                            body = localize(@"ame318.repo.zip_failed", nil); break;
        }
        [ZL2M3Dialog showTitle:localize(@"ame317.install.failed_title", nil)
                           body:body
                   confirmTitle:localize(@"ame317.common.ok", nil)
                    destructive:NO
                     onConfirm:nil
                      onCancel:nil];
        return;
    }

    // 安装结果弹窗（高危 ⚠ 标注；高危默认拒绝——详情页可改）。与手动导入流
    // 同文案同链：ame317.install.confirm_body + ame317.perm.<id>.name 逐行预览；
    // 覆盖重装时补一行私有存储清空提示。
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
    if ([[AmePluginManager installedPluginIds] containsObject:m.pluginId]) {
        // installFromZip 落位成功后 id 必在已装列表——能走到这里说明本次是覆盖重装
        body = [NSString stringWithFormat:@"%@\n\n%@",
                localize(@"ame318.repo.reinstall_body", nil), body];
    }
    [ZL2M3Dialog showTitle:m.name
                       body:body
               confirmTitle:localize(@"ame317.common.ok", nil)
                destructive:NO
                 onConfirm:nil
                  onCancel:nil];
    // 首装自动装载（与列表页导入流同语义：state.json enabled=YES 才装载）
    if ([AmePluginPermissions pluginEnabled:m.pluginId]) {
        [AmePluginRuntime setPluginEnabled:m.pluginId enabled:YES];
    }
    [self.table reloadData];
}

@end
