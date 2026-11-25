//
//  ZL2RendererRepoViewController.m
//  Amethyst
//
//  ★Task475 在线渲染器仓库页。双区表：0 = 远程目录（renderer-repo/index.json
//  三镜像拉取）/ 1 = 本地已装渲染器插件档（PLRendererPluginService 扫描）。
//  行尾动作：安装 / 更新 / 已安装（灰）；安装链 = 镜像下载（cache-busting
//  query，Task342 判例）→ 内存 sha256 → installRendererPluginFromZip 全量
//  校验（首装自动启用）。下载走后台队列 + 装入态防重入（ame333 同款）。
//

#import "ZL2RendererRepoViewController.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "PLRendererPluginService.h"
#import "utils.h" // localize

#import <CommonCrypto/CommonDigest.h>

// ★Task475 远程目录三通道（探测顺序即优先级；ghfast 前缀代理 = 国内加速面；
//   插件仓库页 ame333 同族范式，基址指向仓内 renderer-repo/ 目录）。
static NSString * const ame475_repoBaseOfficial = @"https://raw.githubusercontent.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2/main/renderer-repo/";
static NSString * const ame475_repoBaseJsdelivr = @"https://cdn.jsdelivr.net/gh/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2@main/renderer-repo/";
static NSString * const ame475_repoBaseGhfast   = @"https://ghfast.top/https://raw.githubusercontent.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2/main/renderer-repo/";
// jsdelivr 对 @main 分支引用按固定窗口缓存（Task340 判例）：拉取前先打
// purge 端点预清缓存；失败不阻断（raw/ghfast 通道兜底）。
static NSString * const ame475_repoMirrorPrefKey = @"ame475.renderer.repo.mirror";

// ═══ 动作卡 cell（插件仓库页 Ame431PluginRepoCardCell 同款接棒：自持实现
//   零跨文件符号依赖；右缘/宽/高/纵向中心显式钉死防复用漂移）═══
@interface Ame475RendererRepoCardCell : UITableViewCell
@property (nonatomic, copy) void (^ame475_actionHandler)(void);
- (void)ame475_setTitles:(NSString *)title sub:(NSString *)sub;
- (void)ame475_applyActionStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(void))handler;
@end

@implementation Ame475RendererRepoCardCell {
    UILabel *_ame475_title;
    UILabel *_ame475_sub;
    UIButton *_ame475_button;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *card = [[UIView alloc] init];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.backgroundColor = [ZL2Theme surfaceContainer];
        card.layer.cornerRadius = [ZL2Theme radiusL];
        card.layer.masksToBounds = YES;
        [self.contentView addSubview:card];

        _ame475_title = [[UILabel alloc] init];
        _ame475_title.font = [ZL2Theme fontTitleMedium];
        _ame475_title.textColor = [ZL2Theme onSurface];
        _ame475_title.numberOfLines = 1;
        _ame475_title.lineBreakMode = NSLineBreakByTruncatingTail;
        _ame475_title.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_ame475_title];

        _ame475_sub = [[UILabel alloc] init];
        _ame475_sub.font = [ZL2Theme fontLabelMedium];
        _ame475_sub.textColor = [ZL2Theme onSurfaceVariant];
        _ame475_sub.numberOfLines = 3;
        _ame475_sub.lineBreakMode = NSLineBreakByTruncatingTail;
        _ame475_sub.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:_ame475_sub];

        _ame475_button = [UIButton buttonWithType:UIButtonTypeCustom];
        _ame475_button.translatesAutoresizingMaskIntoConstraints = NO;
        _ame475_button.layer.cornerRadius = [ZL2Theme radiusS];
        _ame475_button.layer.masksToBounds = YES;
        _ame475_button.titleLabel.font = [ZL2Theme fontLabelMedium];
        _ame475_button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        [_ame475_button addTarget:self action:@selector(ame475_actionTapped)
               forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_ame475_button];

        [NSLayoutConstraint activateConstraints:@[
            [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_ame475_button.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [_ame475_button.widthAnchor constraintGreaterThanOrEqualToConstant:64],
            [_ame475_button.heightAnchor constraintEqualToConstant:30],
            [_ame475_button.centerYAnchor constraintEqualToAnchor:_ame475_title.centerYAnchor],

            [_ame475_title.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
            [_ame475_title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [_ame475_title.trailingAnchor constraintLessThanOrEqualToAnchor:_ame475_button.leadingAnchor constant:-10],

            [_ame475_sub.topAnchor constraintEqualToAnchor:_ame475_title.bottomAnchor constant:4],
            [_ame475_sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [_ame475_sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [_ame475_sub.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)ame475_setTitles:(NSString *)title sub:(NSString *)sub {
    _ame475_title.text = title;
    _ame475_sub.text = sub;
}

- (void)ame475_applyActionStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(void))handler {
    _ame475_button.hidden = (style == 3);
    self.ame475_actionHandler = (style == 3) ? nil : handler;
    if (style == 3) return;
    switch (style) {
        case 1:   // 已安装（灰）
            _ame475_button.backgroundColor = [ZL2Theme surfaceContainerHighest];
            [_ame475_button setTitleColor:[ZL2Theme onSurfaceVariant] forState:UIControlStateNormal];
            break;
        case 2:   // 可更新（warning）
            _ame475_button.backgroundColor = [ZL2Theme warning];
            [_ame475_button setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
            break;
        case 4:   // ★Task477 卸载（error destructive）
            _ame475_button.backgroundColor = [ZL2Theme error];
            [_ame475_button setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
            break;
        default:  // 安装/更新中（primary）
            _ame475_button.backgroundColor = [ZL2Theme primary];
            [_ame475_button setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
            break;
    }
    [_ame475_button setTitle:title forState:UIControlStateNormal];
}

- (void)ame475_actionTapped {
    void (^ame475_h)(void) = self.ame475_actionHandler;
    if (ame475_h) ame475_h();
}

@end

// ═══ 主页面 ═══
@interface ZL2RendererRepoViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *remoteItems;  // {id,name,version,summary,file,size,sha256,official}
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *installedItems; // {pluginId,rendererName,version,enabled}
@property (nonatomic, strong) NSMutableSet<NSString *> *installing;         // 插件 id 防重入
@property (nonatomic, copy, nullable) NSString *remoteStatus;               // 远程区状态行（nil=隐藏）
@property (nonatomic, assign) BOOL remoteFetched;
@end

@implementation ZL2RendererRepoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.title = localize(@"ame475.repo.title", @"渲染器仓库");
    self.remoteItems = [NSMutableArray array];
    self.installedItems = [NSMutableArray array];
    self.installing = [NSMutableSet set];
    self.remoteStatus = localize(@"ame475.repo.fetching", @"正在拉取在线目录…");

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 88.0;
    self.table.contentInset = UIEdgeInsetsMake(6, 0, 16, 0);
    [self.table registerClass:[Ame475RendererRepoCardCell class]
           forCellReuseIdentifier:@"Ame475RendererRepoCardCell"];
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self ame475_reloadInstalled];
    [self ame475_fetchRemoteIndex];   // 异步非阻塞，回来 reload
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame475_reloadInstalled];
    [self.table reloadData];
}

// 已装档回查（按插件 id 对齐远程目录条目；未装 = nil）
- (nullable NSDictionary *)ame475_installedEntryForId:(NSString *)pid {
    for (NSDictionary *ame475_i in self.installedItems) {
        if ([ame475_i[@"pluginId"] isKindOfClass:[NSString class]]
            && [(NSString *)ame475_i[@"pluginId"] isEqualToString:pid]) {
            return ame475_i;
        }
    }
    return nil;
}

#pragma mark - 本地已装面

- (void)ame475_reloadInstalled {
    [self.installedItems removeAllObjects];
    NSArray<PLRendererPluginEntry *> *ame475_entries = [PLRendererPluginService availableRenderers];
    for (PLRendererPluginEntry *ame475_e in ame475_entries) {
        [self.installedItems addObject:@{
            @"pluginId": ame475_e.pluginId ?: @"",
            @"rendererName": ame475_e.rendererName ?: @"",
            @"version": ame475_e.version ?: @"",
            @"enabled": @(ame475_e.enabled),
        }];
    }
}

#pragma mark - 远程目录拉取（三镜像 + jsdelivr purge 预清，ame333 同族）

- (void)ame475_fetchRemoteIndex {
    NSString *ame475_base = [NSUserDefaults.standardUserDefaults stringForKey:ame475_repoMirrorPrefKey];
    if (ame475_base.length == 0) ame475_base = ame475_repoBaseOfficial;
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *ame475_index = nil;
        NSString *ame475_usedBase = ame475_base;
        for (NSString *ame475_b in @[ame475_base, ame475_repoBaseOfficial, ame475_repoBaseGhfast, ame475_repoBaseJsdelivr]) {
            if (ame475_b.length == 0) continue;
            NSURL *ame475_url = [NSURL URLWithString:[NSString stringWithFormat:@"%@index.json?cb=%lld",
                ame475_b, (long long)([NSDate date].timeIntervalSince1970 * 1000.0)]];
            if (!ame475_url) continue;
            NSData *ame475_data = [NSData dataWithContentsOfURL:ame475_url];
            if (ame475_data.length > 0) {
                ame475_index = [[NSString alloc] initWithData:ame475_data encoding:NSUTF8StringEncoding];
                ame475_usedBase = ame475_b;
                NSLog(@"[Ame475] renderer repo index fetched via %@ (%@ B)", ame475_b, @(ame475_data.length));
                break;
            }
        }
        NSArray<NSDictionary *> *ame475_renderers = [wself.class ame475_parseIndex:ame475_index];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            [sself.remoteItems removeAllObjects];
            [sself.remoteItems addObjectsFromArray:ame475_renderers];
            sself.remoteFetched = YES;
            sself.remoteStatus = (ame475_renderers.count == 0)
                ? localize(@"ame475.repo.fetch_failed", @"在线目录拉取失败（三镜像均不可达）")
                : nil;
            if (ame475_renderers.count > 0) {
                // 镜像粘性记忆（成功的通道下次优先）
                [NSUserDefaults.standardUserDefaults setObject:ame475_usedBase
                                                        forKey:ame475_repoMirrorPrefKey];
            }
            [sself.table reloadData];
        });
    });
}

+ (NSArray<NSDictionary *> *)ame475_parseIndex:(NSString *)text {
    if (text.length == 0) return @[];
    NSData *ame475_data = [text dataUsingEncoding:NSUTF8StringEncoding];
    id ame475_json = ame475_data ? [NSJSONSerialization JSONObjectWithData:ame475_data options:0 error:nil] : nil;
    if (![ame475_json isKindOfClass:[NSDictionary class]]) return @[];
    id ame475_list = ame475_json[@"renderers"];
    if (![ame475_list isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSDictionary *> *ame475_out = [NSMutableArray array];
    for (id ame475_r in ame475_list) {
        if (![ame475_r isKindOfClass:[NSDictionary class]]) continue;
        NSString *ame475_id = ame475_r[@"id"];
        NSString *ame475_file = ame475_r[@"file"];
        NSString *ame475_sha = ame475_r[@"sha256"];
        if (![ame475_id isKindOfClass:[NSString class]] || ame475_id.length == 0) continue;
        if (![ame475_file isKindOfClass:[NSString class]] || ame475_file.length == 0) continue;
        if (![ame475_sha isKindOfClass:[NSString class]] || ame475_sha.length != 64) continue;
        [ame475_out addObject:ame475_r];
    }
    return ame475_out;
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;   // 0 = 远程目录 / 1 = 本地已装
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        if (self.remoteItems.count > 0) return self.remoteItems.count;
        return (self.remoteStatus.length > 0 || !self.remoteFetched) ? 1 : 0;   // 状态行/空态占位
    }
    return self.installedItems.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return localize(@"ame475.repo.section_remote", @"在线目录");
    return self.installedItems.count > 0 ? localize(@"ame475.repo.section_local", @"已安装") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    Ame475RendererRepoCardCell *cell = [self.table dequeueReusableCellWithIdentifier:@"Ame475RendererRepoCardCell"
                                                                       forIndexPath:indexPath];
    if (indexPath.section == 0) {
        if (self.remoteItems.count == 0) {
            NSString *ame475_status = self.remoteStatus ?: localize(@"ame475.repo.empty", @"在线目录为空");
            [cell ame475_setTitles:ame475_status sub:@""];
            [cell ame475_applyActionStyle:3 title:@"" handler:nil];
            return cell;
        }
        NSDictionary *ame475_p = self.remoteItems[(NSUInteger)indexPath.row];
        NSString *ame475_pid = ame475_p[@"id"];
        NSString *ame475_title = [NSString stringWithFormat:@"%@  v%@",
            ame475_p[@"name"] ?: ame475_pid, ame475_p[@"version"] ?: @"?"];
        NSInteger ame475_sizeMB = [(ame475_p[@"size"] ?: @(0)) integerValue] / (1024 * 1024);
        NSString *ame475_sub = [NSString stringWithFormat:@"%@\n%@ · %.1f MB · sha256 ✓",
            ame475_p[@"summary"] ?: @"",
            localize(@"ame475.repo.official", @"官方件"), (double)ame475_sizeMB];
        [cell ame475_setTitles:ame475_title sub:ame475_sub];

        NSDictionary *ame475_installed = [self ame475_installedEntryForId:ame475_pid];
        if ([self.installing containsObject:ame475_pid]) {
            [cell ame475_applyActionStyle:0
                                    title:localize(@"ame475.repo.installing", @"下载中…")
                                  handler:nil];
        } else if (ame475_installed == nil) {
            __weak typeof(self) wself475 = self;
            [cell ame475_applyActionStyle:0
                                    title:localize(@"ame475.repo.install", @"安装")
                                  handler:^{ [wself475 ame475_beginRemoteInstallForPluginId:ame475_pid]; }];
        } else if ([ame475_installed[@"version"] isEqualToString:ame475_p[@"version"]]) {
            [cell ame475_applyActionStyle:1
                                    title:localize(@"ame475.repo.installed", @"已安装")
                                  handler:nil];
        } else {
            __weak typeof(self) wself475b = self;
            [cell ame475_applyActionStyle:2
                                    title:localize(@"ame475.repo.update", @"更新")
                                  handler:^{ [wself475b ame475_beginRemoteInstallForPluginId:ame475_pid]; }];
        }
        return cell;
    }
    NSDictionary *ame475_i = self.installedItems[(NSUInteger)indexPath.row];
    NSString *ame475_isub = [NSString stringWithFormat:@"%@ · %@",
        ame475_i[@"pluginId"],
        ([ame475_i[@"enabled"] boolValue]
            ? localize(@"ame475.repo.enabled", @"已启用")
            : localize(@"ame475.repo.disabled", @"已停用（插件页可启停）"))];
    [cell ame475_setTitles:[NSString stringWithFormat:@"%@  v%@",
        ame475_i[@"rendererName"], ame475_i[@"version"]] sub:ame475_isub];
    // ★Task477 卸载入口三面之一（用户实测「装完找不到卸载」定谳）：本地已装
    //   行尾常驻卸载钮（error destructive）→ ZL2M3Dialog 红色确认 →
    //   uninstallRendererPlugin purge（插件列表页 ame429 同款语义；运行中
    //   会话不受影响，下次启动生效）。卸载后本地区重扫 + 双区表刷新。
    __weak typeof(self) wself477 = self;
    NSString *ame477_pid = ame475_i[@"pluginId"];
    [cell ame475_applyActionStyle:4
                            title:localize(@"ame477.repo.uninstall", @"卸载")
                          handler:^{
        [ZL2M3Dialog showTitle:ame475_i[@"rendererName"] ?: ame477_pid
                          body:localize(@"ame429.list.delete_confirm", nil)
                  confirmTitle:localize(@"ame429.list.delete_ok", nil)
                   destructive:YES
                    onConfirm:^{
            [PLRendererPluginService uninstallRendererPlugin:ame477_pid];
            [wself477 ame475_reloadInstalled];
            [wself477.table reloadData];
        }
                     onCancel:nil];
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - 远程安装链（镜像下载 → sha256 → installRendererPluginFromZip）

- (void)ame475_beginRemoteInstallForPluginId:(NSString *)pid {
    NSUInteger ame475_idx = [self.remoteItems indexOfObjectPassingTest:^BOOL(NSDictionary *p, NSUInteger idx, BOOL *stop) {
        return [p[@"id"] isKindOfClass:[NSString class]] && [(NSString *)p[@"id"] isEqualToString:pid];
    }];
    if (ame475_idx == NSNotFound) return;
    NSDictionary *ame475_p = self.remoteItems[ame475_idx];
    NSString *ame475_file = ame475_p[@"file"];
    NSString *ame475_sha = ame475_p[@"sha256"];
    if (ame475_file.length == 0 || ame475_sha.length != 64) return;
    if ([self.installing containsObject:pid]) return;
    [self.installing addObject:pid];
    [self.table reloadData];

    NSString *ame475_base = [NSUserDefaults.standardUserDefaults stringForKey:ame475_repoMirrorPrefKey];
    if (ame475_base.length == 0) ame475_base = ame475_repoBaseOfficial;
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *ame475_tmpZip = [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"ame475-repo-%@.zip", [NSUUID UUID].UUIDString]];
        // ★Task342 同款：下载 URL 加 cache-busting query（jsdelivr 文件级缓存
        // 失效双保险）；sha256 内存直算（ame333 范式）。
        NSURL *ame475_url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@?cb=%lld",
            ame475_base, ame475_file, (long long)([NSDate date].timeIntervalSince1970 * 1000.0)]];
        AmePluginInstallResult ame475_code = AmePluginInstallErrDownload;
        NSString *ame475_installedId = nil;
        if (ame475_url) {
            NSData *ame475_data = [NSData dataWithContentsOfURL:ame475_url];
            NSLog(@"[Ame475] renderer package download %@ via %@ -> %@B", pid, ame475_base, ame475_data ? @(ame475_data.length) : @"0");
            NSString *ame475_gotSha = ame475_data.length ? [wself.class ame475_sha256OfData:ame475_data] : nil;
            if (ame475_data.length && [ame475_gotSha isEqualToString:ame475_sha]) {
                [ame475_data writeToFile:ame475_tmpZip options:NSDataWritingAtomic error:nil];
                ame475_code = [PLRendererPluginService installRendererPluginFromZip:ame475_tmpZip
                                                                             outId:&ame475_installedId];
            } else if (!ame475_data.length) {
                NSLog(@"[Ame475] renderer package download FAILED for %@ (empty body via %@)", pid, ame475_base);
            } else {
                NSLog(@"[Ame475] renderer package sha mismatch for %@ (got %@ want %@)", pid, ame475_gotSha, ame475_sha);
                ame475_code = AmePluginInstallErrShaMismatch;
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:ame475_tmpZip error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            [sself.installing removeObject:pid];
            [sself ame475_reloadInstalled];
            [sself.table reloadData];
            NSString *ame475_body = nil;
            switch (ame475_code) {
                case AmePluginInstallOK:
                    NSLog(@"[Ame475] renderer repo install ok: %@ (id=%@, auto-enabled on first install)",
                          pid, ame475_installedId);
                    ame475_body = localize(@"ame475.repo.install_ok", @"渲染器插件已安装并启用；在设置→渲染器选择该档位后启动游戏生效。");
                    break;
                case AmePluginInstallErrShaMismatch:
                    ame475_body = localize(@"ame475.repo.sha_mismatch", @"下载内容校验失败（sha256 不符），请重试或切换镜像。");
                    break;
                default:
                    ame475_body = localize(@"ame475.repo.download_failed", @"下载失败（网络不可达），请检查网络或稍后重试。");
                    break;
            }
            [ZL2M3Dialog showTitle:(ame475_code == AmePluginInstallOK
                                        ? localize(@"ame317.common.ok", @"完成")
                                        : localize(@"ame475.repo.install_failed", @"安装失败"))
                              body:ame475_body
                      confirmTitle:localize(@"ame317.common.ok", @"确定")
                       destructive:NO
                        onConfirm:nil
                         onCancel:nil];
        });
    });
}

#pragma mark - sha256（ame333 同款内存直算）

+ (NSString *)ame475_sha256OfData:(NSData *)data {
    unsigned char ame475_digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, ame475_digest);
    NSMutableString *ame475_hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int ame475_i = 0; ame475_i < CC_SHA256_DIGEST_LENGTH; ame475_i++) {
        [ame475_hex appendFormat:@"%02x", ame475_digest[ame475_i]];
    }
    return ame475_hex;
}

@end
