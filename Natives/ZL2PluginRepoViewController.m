#import "ZL2PluginRepoViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "utils.h" // localize
#import "UnzipKit.h"

#import <CommonCrypto/CommonDigest.h>

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginRepoViewController 实现（Task 318 内置插件仓库 / ★ Task333 上仓）
// 口径注释：
//  · 双区表：0=远程官方仓库（index.json 拉取，zip 下载 → sha256 校验 →
//    installFromZip 全量校验链）1=包内预置（builtin-plugins，随包件）
//  · ★ Task333 插件上仓：四件演示插件迁移出 IPA（bundle 只留 plugin-survey
//    勘测件），从本页远程安装/更新；IPA 体积让渡虽小（KB 级），架构收益
//    = 插件可独立于启动器发版更新 + 仓库化分发
//  · 镜像加速（用户："国内可以使用加速源"）：三通道按序探测（记忆镜像
//    优先 → jsdelivr CDN → raw 官方 → ghfast 前缀代理），index 拉取成功者
//    即为本次会话下载通道；选择结果落偏好供下次首试
//  · 官方信任面：index official=true 件 = 与 bundle 内置件同信任根（同
//    GitHub 仓库同发布者）→ noteRepoOfficialIndex 落缓存 + 授权自愈覆盖
//    （声明权限全量授，ame.super 永不代授）；第三方件默认拒原样保留
//  · 安装链 = 与手动导入同一条 installFromZip 全量校验（manifest schema/
//    entry 防逃逸/首装授权普通授高危拒）
// ═══════════════════════════════════════════════════════════════════

static NSString *ame318_builtinRoot(void) {
    return [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"builtin-plugins"];
}

// ★ Task333：远程仓库基址三通道（探测顺序即优先级；ghfast 前缀代理 = 国内
//   加速面）。nsstring 常量放文件级避免块内捕获静态存储雷。
static NSString * const ame333_repoBaseOfficial  = @"https://raw.githubusercontent.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2/main/plugin-repo/";
static NSString * const ame333_repoBaseJsdelivr  = @"https://cdn.jsdelivr.net/gh/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2@main/plugin-repo/";
static NSString * const ame333_repoBaseGhfast    = @"https://ghfast.top/https://raw.githubusercontent.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2/main/plugin-repo/";
// ★Task340：jsdelivr purge 端点（官方 API，GET 即刷新该路径的 CDN 缓存）。
//   装机日志实锤（5a6c059）：index.json 第五件 fluent-ui 已入库，用户打开
//   插件仓库页仍只见 4 件——jsdelivr 对 @main 分支引用按固定窗口缓存
//   （~12h），push 不会主动失效，远程区数据源完全来自 index → 新件在
//   缓存窗口内不可见（用户："为什么插件列表没有远程仓库的 fluent-ui"）。
//   修法 = 拉取 jsdelivr 通道前先打 purge 端点预清缓存；失败不阻断
//   （旧缓存可接受，raw/ghfast 通道兜底，CI 侧另加 push 后自动 purge）。
static NSString * const ame333_repoMirrorPrefKey = @"ame333.plugin.repo.mirror";

@interface ZL2PluginRepoViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;      // 包内区 {dirName, manifest}
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *remoteItems; // 远程区 {id,name,version,author,summary,file,size,sha256,official}
@property (nonatomic, strong) NSMutableSet<NSString *> *installing;       // 插件 id 防重入
@property (nonatomic, copy) NSString *remoteStatus;                       // 远程区状态行（nil=隐藏状态行）
@property (nonatomic, assign) BOOL remoteFetched;
@end

@implementation ZL2PluginRepoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    self.title = localize(@"ame318.repo.title", nil);
    self.items = [NSMutableArray array];
    self.remoteItems = [NSMutableArray array];
    self.installing = [NSMutableSet set];
    self.remoteStatus = localize(@"ame333.repo.fetching", nil);

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

    // Task325：系统组头 → 自绘小字标题
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
    [self ame333_fetchRemoteIndex];   // 异步非阻塞，回来 reload
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame318_reload];
}

#pragma mark - 远程 index（镜像探测 + 下载通道选择）

/// 三通道按序探测（记忆镜像优先）——index JSON 拉取成功者即胜出。
/// 返回 (indexDict, baseURL)；全败返回 (nil, nil)。
- (NSDictionary *)ame333_fetchIndexWithBaseOut:(NSString **)baseOut {
    NSMutableArray<NSString *> *bases = [NSMutableArray array];
    NSString *remembered = [NSUserDefaults.standardUserDefaults stringForKey:ame333_repoMirrorPrefKey];
    if (remembered.length) [bases addObject:remembered];
    [bases addObjectsFromArray:@[ame333_repoBaseJsdelivr, ame333_repoBaseOfficial, ame333_repoBaseGhfast]];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 6.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    BOOL ame340_purged = NO;   // purge 每次页面打开至多一次（jsdelivr 与记忆镜像同域不重复打）
    for (NSString *base in bases) {
        // ★Task340：jsdelivr 通道拉取前预清 CDN 缓存（见 ame333_repoBaseGhfast
        //   上方注）；3s 超时，结果只取证不阻断。
        if (!ame340_purged && [base containsString:@"cdn.jsdelivr.net"]) {
            ame340_purged = YES;
            NSString *purgeUrl = [ame333_repoBaseJsdelivr stringByAppendingString:@"index.json"];
            purgeUrl = [purgeUrl stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"
                                                           withString:@"purge.jsdelivr.net"];
            NSURL *purge = [NSURL URLWithString:purgeUrl];
            if (purge) {
                dispatch_semaphore_t psem = dispatch_semaphore_create(0);
                __block NSInteger phttp = 0;
                [[session dataTaskWithURL:purge completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    phttp = ((NSHTTPURLResponse *)r).statusCode ?: 0;
                    dispatch_semaphore_signal(psem);
                }] resume];
                dispatch_semaphore_wait(psem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
                NSLog(@"[AmePluginRepo] Task340 jsdelivr index cache purge: http=%ld", (long)phttp);
            }
        }
        NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"index.json"]];
        if (!url) continue;
        // 常量基址 + 固定路径：semaphore 同步探测（页面上已有 fetching 状态行）
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSData *data = nil;
        [[session dataTaskWithURL:url
                completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            NSInteger http = ((NSHTTPURLResponse *)r).statusCode ?: 0;
            if (d.length > 2 && http == 200) data = d;
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)));
        if (!data) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        if (![json[@"plugins"] isKindOfClass:[NSArray class]]) continue;
        if (baseOut) *baseOut = base;
        return json;
    }
    return nil;
}

- (void)ame333_fetchRemoteIndex {
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *base = nil;
        NSDictionary *index = [wself ame333_fetchIndexWithBaseOut:&base];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            if (!index) {
                sself.remoteStatus = localize(@"ame333.repo.fetch_fail", nil);
                [sself tableReloadAndKeepScroll];
                NSLog(@"[AmePluginRepo] Task333 remote index fetch failed (all mirrors)");
                return;
            }
            [NSUserDefaults.standardUserDefaults setObject:base forKey:ame333_repoMirrorPrefKey];
            NSLog(@"[AmePluginRepo] Task333 remote index fetched via %@ (%lu plugins)", base,
                  (unsigned long)[index[@"plugins"] count]);
            // 官方信任面落缓存 + 授权自愈重跑（ame.super 永不代授）
            NSMutableDictionary<NSString *, NSString *> *official = [NSMutableDictionary dictionary];
            [sself.remoteItems removeAllObjects];
            for (id raw in index[@"plugins"]) {
                if (![raw isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *p = raw;
                NSString *pid = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : nil;
                NSString *file = [p[@"file"] isKindOfClass:[NSString class]] ? p[@"file"] : nil;
                if (pid.length == 0 || file.length == 0) continue;
                if ([pid hasPrefix:@"."]) continue;
                [sself.remoteItems addObject:p];
                if ([p[@"official"] boolValue]) official[pid] =
                    [p[@"version"] isKindOfClass:[NSString class]] ? p[@"version"] : @"";
            }
            sself.remoteStatus = nil;
            [sself tableReloadAndKeepScroll];
            if (official.count) {
                [AmePluginRuntime noteRepoOfficialIndex:official];
            }
        });
    });
}

// UITableView reload 会回滚滚动位——远程区异步回包在用户阅读包内区时不打断
- (void)tableReloadAndKeepScroll {
    CGPoint offset = self.table.contentOffset;
    [self.table reloadData];
    [self.table layoutIfNeeded];
    [self.table setContentOffset:offset animated:NO];
}

#pragma mark - sha256（CommonCrypto，远程件完整性闸）

+ (NSString *)ame333_sha256OfFile:(NSString *)path {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    while (YES) {
        NSData *chunk = [fh readDataOfLength:256 * 1024];
        if (chunk.length == 0) break;
        CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
    }
    [fh closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

#pragma mark - 数据装配（包内区）

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

#pragma mark - 表格（0=远程区 1=包内区）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(self.remoteItems.count, 1); // 远程空态/状态行占位
    return MAX(self.items.count, 1);                          // 包内空态占位行
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return localize(@"ame333.repo.section_remote", nil);
    return localize(@"ame333.repo.section_builtin", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // ★ Task325：系统 Subtitle cell → ZL2M3CardCell（卡底/字体/动作胶囊全令牌化）
    ZL2M3CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZL2M3CardCell"
                                                          forIndexPath:indexPath];
    if (indexPath.section == 0 && self.remoteItems.count == 0) {
        cell.titleLabel.text = self.remoteStatus ?: localize(@"ame333.repo.fetch_empty", nil);
        cell.subLabel.text = @"";
        [cell applyActionStyle:3 title:@""];
        return cell;
    }
    if (indexPath.section == 1 && self.items.count == 0) {
        cell.titleLabel.text = localize(@"ame318.repo.empty", nil);
        cell.subLabel.text = @"";
        [cell applyActionStyle:3 title:@""];
        return cell;
    }

    if (indexPath.section == 0) {
        // ★ Task333：远程件卡 —— 已装同版=已安装 / 已装低版=可更新 / 未装=安装
        NSDictionary *p = self.remoteItems[(NSUInteger)indexPath.row];
        NSString *pid = p[@"id"];
        BOOL installing = [self.installing containsObject:pid];
        NSString *name = [p[@"name"] isKindOfClass:[NSString class]] && ((NSString *)p[@"name"]).length
            ? p[@"name"] : pid;
        cell.titleLabel.text = name;
        NSString *authorLine = ([p[@"author"] isKindOfClass:[NSString class]] && ((NSString *)p[@"author"]).length)
            ? [NSString stringWithFormat:localize(@"ame317.list.by_author", nil), p[@"author"]] : @"";
        cell.subLabel.text = [NSString stringWithFormat:@"v%@ · %@ · %@",
                              [p[@"version"] isKindOfClass:[NSString class]] ? p[@"version"] : @"?",
                              authorLine,
                              [p[@"summary"] isKindOfClass:[NSString class]] ? p[@"summary"] : @""];
        AmePluginManifest *installedM = [AmePluginManager manifestForPlugin:pid];
        if (!installedM) {
            [cell applyActionStyle:0 title:localize(installing ? @"ame318.repo.installing" : @"ame333.repo.install", nil)];
        } else if ([installedM.version compare:p[@"version"]] == NSOrderedAscending) {
            [cell applyActionStyle:0 title:localize(@"ame333.repo.update", nil)];
        } else {
            [cell applyActionStyle:1 title:localize(@"custom_controls.repo.installed_badge", nil)];
        }
        return cell;
    }

    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    AmePluginManifest *m = item[@"manifest"];
    NSString *dirName = item[@"dirName"];
    BOOL installed = ([[AmePluginManager installedPluginIds] containsObject:m.pluginId]);
    BOOL installing = [self.installing containsObject:m.pluginId];

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
    if (indexPath.section == 0) {
        if (self.remoteItems.count == 0) return;
        NSDictionary *p = self.remoteItems[(NSUInteger)indexPath.row];
        NSString *pid = p[@"id"];
        AmePluginManifest *installedM = [AmePluginManager manifestForPlugin:pid];
        // 已装同版或更高 → 详情页；已装低版或未装 → 下载安装/更新
        if (installedM && [installedM.version compare:p[@"version"]] != NSOrderedAscending) {
            ZL2PluginDetailViewController *detail =
                [[ZL2PluginDetailViewController alloc] initWithPluginId:pid];
            [self.navigationController pushViewController:detail animated:YES];
            return;
        }
        [self ame333_beginRemoteInstallForRow:(NSInteger)indexPath.row];
        return;
    }
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

#pragma mark - 远程安装链（镜像下载 → sha256 → installFromZip 全量校验链）

- (void)ame333_beginRemoteInstallForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.remoteItems.count) return;
    NSDictionary *p = self.remoteItems[(NSUInteger)row];
    NSString *pid = p[@"id"];
    NSString *file = p[@"file"];
    NSString *sha = p[@"sha256"];
    if (pid.length == 0 || file.length == 0) return;
    if ([self.installing containsObject:pid]) return;
    if (sha.length != 64) {
        [ZL2M3Dialog showTitle:localize(@"ame317.install.failed_title", nil)
                           body:localize(@"ame333.repo.sha_mismatch", nil)
                   confirmTitle:localize(@"ame317.common.ok", nil)
                    destructive:NO
                     onConfirm:nil
                      onCancel:nil];
        return;
    }
    [self.installing addObject:pid];
    [self tableReloadAndKeepScroll];

    NSString *base = [NSUserDefaults.standardUserDefaults stringForKey:ame333_repoMirrorPrefKey];
    if (base.length == 0) base = ame333_repoBaseOfficial;
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *tmpZip = [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"ame333-repo-%@.zip", [NSUUID UUID].UUIDString]];
        // ★Task342：下载 URL 加 cache-busting query（?cb=<毫秒时间戳>）——
        //   装机实弹（d377102 latestlog 2026-10-29）：Task340 purge 后 index 已
        //   是新 5 件，但 fluent-ui.zip 下载仍回 CDN 旧缓存 3045B（v1）→
        //   sha mismatch ×3（got=e5f4c0d1 want=6f21064d）。purge 只对 index
        //   生效，文件级缓存未失效。jsdelivr 的 cache key 含 query，未知
        //   query 即回源拿最新；raw/ghfast 通道 query 无害。双保险：下载前
        //   再对同路径打一次 purge.jsdelivr.net（3s 超时，结果只取证不阻断）。
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@?cb=%lld",
            base, file, (long long)([NSDate date].timeIntervalSince1970 * 1000.0)]];
        if (url && [base containsString:@"cdn.jsdelivr.net"]) {
            NSString *filePurgeUrl = [[[base stringByAppendingString:file]
                stringByReplacingOccurrencesOfString:@"cdn.jsdelivr.net"
                                          withString:@"purge.jsdelivr.net"]
                stringByAppendingString:@"?cb=1"];
            NSURL *filePurge = [NSURL URLWithString:filePurgeUrl];
            if (filePurge) {
                dispatch_semaphore_t fpsem = dispatch_semaphore_create(0);
                __block NSInteger fphttp = 0;
                NSURLSessionConfiguration *pcfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
                pcfg.timeoutIntervalForRequest = 3.0;
                [[NSURLSession sessionWithConfiguration:pcfg] dataTaskWithURL:filePurge completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    fphttp = ((NSHTTPURLResponse *)r).statusCode ?: 0;
                    dispatch_semaphore_signal(fpsem);
                }] resume];
                dispatch_semaphore_wait(fpsem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
                NSLog(@"[AmePluginRepo] Task342 jsdelivr file cache purge (%@): http=%ld", pid, (long)fphttp);
            }
        }
        AmePluginManifest *m = nil;
        AmePluginInstallResult code = AmePluginInstallErrDownload;
        if (url) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSLog(@"[AmePluginRepo] Task333 download %@ via %@ -> %@B", pid, base, data ? @(data.length) : @"0");
            NSString *gotSha = data.length ? [wself.class ame333_sha256OfStringData:data] : nil;
            if (data.length && gotSha && [gotSha isEqualToString:sha]) {
                [data writeToFile:tmpZip options:NSDataWritingAtomic error:nil];
                code = [AmePluginManager installFromZip:tmpZip outManifest:&m];
            } else if (!data.length) {
                NSLog(@"[AmePluginRepo] Task342 download failed for %@ (empty body via %@)", pid, base);
                code = AmePluginInstallErrDownload;
                m = nil;
            } else {
                NSLog(@"[AmePluginRepo] Task333 sha mismatch for %@ (got %@ want %@)", pid, gotSha, sha);
                code = AmePluginInstallErrShaMismatch;   // ★Task342：专属错误码，不再误报 zip 写入错误
                m = nil;
            }
        } else {
            NSLog(@"[AmePluginRepo] Task342 invalid download URL for %@ (base=%@ file=%@)", pid, base, file);
        }
        [[NSFileManager defaultManager] removeItemAtPath:tmpZip error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            [sself.installing removeObject:pid];
            if (code == AmePluginInstallOK && m && [p[@"official"] boolValue]) {
                // 官方件：声明权限即时全量授（与首方内置件同语义；ame.super 永不代授）
                NSMutableDictionary<NSString *, NSNumber *> *g = [NSMutableDictionary dictionary];
                for (NSString *perm in m.permissions) {
                    if ([perm isEqualToString:@"ame.super"]) continue;
                    g[perm] = @1;
                }
                [AmePluginPermissions replaceGrants:g forPlugin:m.pluginId];
                [AmePluginPermissions setPluginEnabled:YES pluginId:m.pluginId];
                NSLog(@"[AmePluginRepo] Task333 official plugin grants healed at install: %@", m.pluginId);
            }
            [sself ame318_installDidFinish:code manifest:m];
        });
    });
}

// 内存态 sha（下载流直算，免二次落盘读）
+ (NSString *)ame333_sha256OfStringData:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

#pragma mark - 包内安装链（目录 → 临时 zip → installFromZip 全量校验链）

- (void)ame318_beginInstallForRow:(NSInteger)row {
    if (self.items.count == 0) return;
    if (row < 0 || row >= (NSInteger)self.items.count) return;
    NSDictionary *item = self.items[(NSUInteger)row];
    NSString *dirName = item[@"dirName"];
    AmePluginManifest *pm = item[@"manifest"];
    if (pm.pluginId.length == 0) return;
    if ([self.installing containsObject:pm.pluginId]) return;
    [self.installing addObject:pm.pluginId];
    [self tableReloadAndKeepScroll];

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
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            [sself.installing removeObject:pm.pluginId];
            [sself ame318_installDidFinish:code manifest:m];
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
    if (relPaths.count == 0) {
        // ★Task342：静默 NO 取证（本轮用户弹窗"zip 写入错误"实为 ame333 sha
        //   失败文案错位，但本分支同样静默——builtin 根缺失/目录名不匹配
        //   时无任何日志，排查只能盲猜）。下次命中日志直接可见。
        NSLog(@"[AmePluginRepo] Task342 builtin zip collected 0 files (src=%@ dirName=%@ exists=%d)",
              src, dirName, [[NSFileManager defaultManager] fileExistsAtPath:src]);
        return NO;
    }

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
    [self tableReloadAndKeepScroll];
    if (code != AmePluginInstallOK) {
        NSString *body;
        switch (code) {
            case AmePluginInstallErrReadZip:    body = localize(@"ame318.repo.zip_failed", nil); break;
            case AmePluginInstallErrDownload:   body = localize(@"ame333.repo.download_failed", nil); break;
            case AmePluginInstallErrShaMismatch: body = localize(@"ame333.repo.sha_mismatch", nil); break;
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

    // 安装结果弹窗（高危 ⚠ 标注）。★ Task333：官方件授权已即时全量授
    // （预览仅告知），第三方件仍按既有口径：高危默认拒——详情页可改。
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
    [self tableReloadAndKeepScroll];
}

@end
