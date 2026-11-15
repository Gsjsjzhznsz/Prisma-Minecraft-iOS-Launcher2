#import "ZL2PluginRepoViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2MotionKit.h" // ★Task429：MD3 动效体系（插件仓库卡列表入场示范接入）
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

// ============================================================================
// ★ Task431（仓库页按钮修复）：仓库卡片动作胶囊 → 真按钮（与本仓插件仓库页
//   的 Ame431RepoCardCell 同款接棒；ZL2M3CardCell 全仓消费面 = 两仓库页）。
//   病历（用户 iPad 截图两报）：
//   ① 动作按钮几何只有 >= 约束无等式钉死，复用换内容可漂移——本类把右缘/
//      宽/高/纵向中心显式钉死（令牌与 kit 胶囊同源：contentView.trailing
//      -(cardMarginH+cardInsetX)、pillMinWidth、pillHeight、标题字阶 centerY）。
//   ② kit 胶囊 userInteractionEnabled=NO，点击语义 = 整行点击（didSelectRow
//      直连安装链）+ Task429 PressableCard 挂在卡片上的 LPGR（minimumPress
//      Duration 0）滑动起手即播按压动画 —— "在选项上滑动即触发安装"误触
//      根源。修法：安装/更新唯一入口 = 按钮 handler，行体点击零动作；行体
//      按压手势退役，按压效果保留在按钮本身；kit 展示胶囊 applyActionStyle:3
//      隐藏，文本避让约束同步收窄到按钮左缘。
// ============================================================================
@interface Ame431PluginRepoCardCell : ZL2M3CardCell
/// 动作按钮回调（nil = 按钮纯展示态）。cellForRow 每次装配都重设
/// （handler 捕获业务 id 而非 indexPath）——cell 复用安全。
@property (nonatomic, copy) void (^ame431_actionHandler)(void);
/// 0=安装/更新(primary) 1=已安装(灰) 2=可更新(warning) 3=隐藏（含 kit 展示胶囊隐藏）
- (void)ame431_applyActionStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(void))handler;
@end

@implementation Ame431PluginRepoCardCell {
    UIButton *_ame431_button;
    NSLayoutConstraint *_ame431_titleToButton;
    NSLayoutConstraint *_ame431_subToButton;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // ① 行体按压手势退役：PressableCard 挂在卡片视图上的 LPGR（签名 =
        //   UILongPressGestureRecognizer + minimumPressDuration 0）。先摘除
        //   （后段还要给按钮挂 Pressable，顺序不可倒——按钮按压效果须保留）。
        for (UIView *ame431_v in self.contentView.subviews) {
            NSArray<UIGestureRecognizer *> *ame431_gs = [ame431_v gestureRecognizers] ?: @[];
            for (UIGestureRecognizer *ame431_g in ame431_gs) {
                if ([ame431_g isKindOfClass:[UILongPressGestureRecognizer class]] &&
                    ((UILongPressGestureRecognizer *)ame431_g).minimumPressDuration <= 0.0) {
                    [ame431_v removeGestureRecognizer:ame431_g];
                }
            }
        }
        // kit 展示态胶囊整体退役（按钮接棒；隐藏态文本 fallback 约束由 kit 侧保持）
        [self applyActionStyle:3 title:@""];
        _ame431_button = [UIButton buttonWithType:UIButtonTypeCustom];
        _ame431_button.translatesAutoresizingMaskIntoConstraints = NO;
        _ame431_button.layer.cornerRadius = [ZL2Theme radiusS];
        _ame431_button.layer.masksToBounds = YES;
        _ame431_button.titleLabel.font = [ZL2Theme fontLabelMedium];
        _ame431_button.titleLabel.textAlignment = NSTextAlignmentCenter;
        _ame431_button.titleLabel.numberOfLines = 1;
        _ame431_button.contentEdgeInsets = UIEdgeInsetsMake(0, [ZL2Theme ame343_layoutMetric:@"pillGap" fallback:10.0], 0,
                                                            [ZL2Theme ame343_layoutMetric:@"pillGap" fallback:10.0]);
        [_ame431_button addTarget:self action:@selector(ame431_actionTapped)
               forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_ame431_button];
        CGFloat ame431_trailing = [ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0] +
                                  [ZL2Theme ame343_layoutMetric:@"cardInsetX" fallback:14.0];
        _ame431_titleToButton = [self.titleLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:_ame431_button.leadingAnchor
                                     constant:-[ZL2Theme ame343_layoutMetric:@"pillGap" fallback:10.0]];
        _ame431_subToButton = [self.subLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:_ame431_button.leadingAnchor
                                     constant:-[ZL2Theme ame343_layoutMetric:@"pillGap" fallback:10.0]];
        [NSLayoutConstraint activateConstraints:@[
            [_ame431_button.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                          constant:-ame431_trailing],
            [_ame431_button.widthAnchor constraintGreaterThanOrEqualToConstant:
                [ZL2Theme ame343_layoutMetric:@"pillMinWidth" fallback:56.0]],
            [_ame431_button.heightAnchor constraintEqualToConstant:
                [ZL2Theme ame343_layoutMetric:@"pillHeight" fallback:28.0]],
            [_ame431_button.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        ]];
        // ② 按钮自身按压效果（0.94 档 + 触觉——与原卡片按压同档；挂靠手势
        //   cancelsTouchesInView=NO，不干扰 TouchUpInside）
        [ZL2M3Pressable attachToView:_ame431_button pressedScale:0.94];
    }
    return self;
}

- (void)ame431_applyActionStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(void))handler {
    BOOL ame431_hidden = (style == 3);
    _ame431_button.hidden = ame431_hidden;
    _ame431_titleToButton.active = !ame431_hidden;
    _ame431_subToButton.active = !ame431_hidden;
    self.ame431_actionHandler = ame431_hidden ? nil : handler;
    if (ame431_hidden) return;
    switch (style) {
        case 1:
            _ame431_button.backgroundColor = [ZL2Theme surfaceContainerHighest];
            [_ame431_button setTitleColor:[ZL2Theme onSurfaceVariant] forState:UIControlStateNormal];
            break;
        case 2:
            _ame431_button.backgroundColor = [ZL2Theme warning];
            [_ame431_button setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
            break;
        default:
            _ame431_button.backgroundColor = [ZL2Theme primary];
            [_ame431_button setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
            break;
    }
    [_ame431_button setTitle:title forState:UIControlStateNormal];
}

- (void)ame431_actionTapped {
    void (^ame431_h)(void) = self.ame431_actionHandler;
    if (ame431_h) ame431_h();
}

@end

@interface ZL2PluginRepoViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;      // 包内区 {dirName, manifest}
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *remoteItems; // 远程区 {id,name,version,author,summary,file,size,sha256,official}
@property (nonatomic, strong) NSMutableSet<NSString *> *installing;       // 插件 id 防重入
@property (nonatomic, copy) NSString *remoteStatus;                       // 远程区状态行（nil=隐藏状态行）
@property (nonatomic, assign) BOOL remoteFetched;
@property (nonatomic, strong) UILabel *ame345_heroCountLabel;             ///< Task345 hero 计数行
@property (nonatomic, assign) CGFloat ame345_lastHeroWidth;
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
    // ★ Task431：卡片 cell 换装 Ame431PluginRepoCardCell（动作胶囊 → 真按钮）
    [self.table registerClass:[Ame431PluginRepoCardCell class]
           forCellReuseIdentifier:@"Ame431PluginRepoCardCell"];
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // ★ Task345：系统组头小字 → hero 头卡（图标瓦片 + 标题字阶 + 远程/内置计数
    //   摘要；圆角/边距/字阶全走令牌，ame341/ame343 覆盖即生效）。
    [self ame345_installHeroHeader];

    [self ame318_reload];
    [self ame333_fetchRemoteIndex];   // 异步非阻塞，回来 reload
}

#pragma mark - Task345 hero 头卡

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
    UIImageView *tileIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox.fill"]];
    tileIcon.translatesAutoresizingMaskIntoConstraints = NO;
    tileIcon.contentMode = UIViewContentModeScaleAspectFit;
    tileIcon.tintColor = [ZL2Theme onPrimaryContainer];
    [tile addSubview:tileIcon];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = localize(@"ame318.repo.title", nil);
    titleLabel.font = [ZL2Theme fontHeadline];
    titleLabel.textColor = [ZL2Theme onSurface];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = [ZL2Theme fontBodyMedium];
    countLabel.textColor = [ZL2Theme onSurfaceVariant];
    self.ame345_heroCountLabel = countLabel;

    [card addSubview:tile];
    [card addSubview:titleLabel];
    [card addSubview:countLabel];

    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inX],
        [tile.topAnchor constraintEqualToAnchor:card.topAnchor constant:inT],
        [tile.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inB],
        [tile.widthAnchor constraintEqualToConstant:48.0],
        [tile.heightAnchor constraintEqualToConstant:48.0],
        [tileIcon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [tileIcon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [tileIcon.widthAnchor constraintEqualToConstant:24.0],
        [tileIcon.heightAnchor constraintEqualToConstant:24.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:gap + inX],
        [titleLabel.bottomAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-1.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-inX],

        [countLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [countLabel.topAnchor constraintEqualToAnchor:tile.centerYAnchor constant:1.0],
        [countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-inX],
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
    [self ame345_refreshHeroCount];
}

- (void)ame345_refreshHeroCount {
    if (!self.ame345_heroCountLabel) return;
    self.ame345_heroCountLabel.text = [NSString stringWithFormat:
        localize(@"ame345.repo.hero.count", nil),
        (unsigned long)self.remoteItems.count, (unsigned long)self.items.count];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
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
            [sself ame345_refreshHeroCount];
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
    [self ame345_refreshHeroCount];
    [self.table reloadData];
    // ★Task429：插件仓库卡列表入场示范接入（表 9-1「列表入场」行）——
    //   可见卡按 indexPath 递增 20ms 错峰 alpha+8pt 上移；同批防重入内置
    //   （viewDidLoad + viewWillAppear 双 reload 不叠播）；远程区异步刷新
    //   （tableReloadAndKeepScroll）不接入，保持阅读中不打断。
    [ZL2MotionList animateEntranceOfTableView:self.table];
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
    // ★ Task431：动作按钮 cell（原展示态胶囊 cell 退役）
    Ame431PluginRepoCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Ame431PluginRepoCardCell"
                                                                 forIndexPath:indexPath];
    if (indexPath.section == 0 && self.remoteItems.count == 0) {
        cell.titleLabel.text = self.remoteStatus ?: localize(@"ame333.repo.fetch_empty", nil);
        cell.subLabel.text = @"";
        [cell ame431_applyActionStyle:3 title:@"" handler:nil];
        return cell;
    }
    if (indexPath.section == 1 && self.items.count == 0) {
        cell.titleLabel.text = localize(@"ame318.repo.empty", nil);
        cell.subLabel.text = @"";
        [cell ame431_applyActionStyle:3 title:@"" handler:nil];
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
        // ★ Task431：动作按钮装配——安装/更新 = 按钮回调（唯一安装入口）；
        //   已安装 = 纯展示态角标 + 点按进详情（与原行点击语义同）。handler
        //   捕获 pluginId（点击时按 id 回查现值，防 reload 索引漂移）。
        __weak typeof(self) ame431_wself = self;
        if (!installedM) {
            [cell ame431_applyActionStyle:0
                                    title:localize(installing ? @"ame318.repo.installing" : @"ame333.repo.install", nil)
                                  handler:^{
                [ame431_wself ame333_beginRemoteInstallForPluginId:pid];
            }];
        } else if ([installedM.version compare:p[@"version"]] == NSOrderedAscending) {
            [cell ame431_applyActionStyle:0
                                    title:localize(@"ame333.repo.update", nil)
                                  handler:^{
                [ame431_wself ame333_beginRemoteInstallForPluginId:pid];
            }];
        } else {
            [cell ame431_applyActionStyle:1
                                    title:localize(@"custom_controls.repo.installed_badge", nil)
                                  handler:^{
                [ame431_wself ame431_openPluginDetail:pid];
            }];
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
    // ★ Task431：动作按钮装配——安装 = 按钮回调（唯一安装入口）；已安装 =
    //   展示态角标 + 点按进详情。handler 捕获 pluginId，cell 复用安全。
    __weak typeof(self) ame431_wself = self;
    if (installed) {
        [cell ame431_applyActionStyle:1
                                title:localize(@"custom_controls.repo.installed_badge", nil)
                              handler:^{
            [ame431_wself ame431_openPluginDetail:m.pluginId];
        }];
    } else {
        [cell ame431_applyActionStyle:0
                                title:localize(installing ? @"ame318.repo.installing" : @"ame318.repo.install", nil)
                              handler:^{
            [ame431_wself ame318_beginInstallForPluginId:m.pluginId];
        }];
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
        // ★ Task431：行点击仅保留"已装件 → 详情页"导航语义（未装/可更新件也
        //   进详情，安装/更新唯一入口 = 行尾动作按钮 ame431）——滑动/误触行体
        //   不再触发安装，也不再播按压动画（行体 Pressable 手势已在
        //   Ame431PluginRepoCardCell 内退役）。
        if (installedM) {
            [self ame431_openPluginDetail:pid];
        }
        return;
    }
    if (self.items.count == 0) return;
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    AmePluginManifest *m = item[@"manifest"];
    // ★ Task431：已装件 → 详情；未装件行点击零动作（安装唯一入口 = 按钮）
    if ([[AmePluginManager installedPluginIds] containsObject:m.pluginId]) {
        [self ame431_openPluginDetail:m.pluginId];
    }
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
                // ★Task342 r1 热修（CI dev 40734990645 实锤：missing '[' at
                //   start of message send expression @438）：三层消息链
                //   [[[session sessionWithConfig] dataTask] resume] 少一层
                //   `[`——对齐 Task340 既有模式（局部变量 + 两层消息）。
                NSURLSessionConfiguration *pcfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
                pcfg.timeoutIntervalForRequest = 3.0;
                NSURLSession *psession = [NSURLSession sessionWithConfiguration:pcfg];
                [[psession dataTaskWithURL:filePurge completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
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

// ★ Task431：按钮回调入口——按 id 回查当前行（防 reload 索引漂移），防重入
//   守卫沿用 ame333_beginRemoteInstallForRow:。
- (void)ame333_beginRemoteInstallForPluginId:(NSString *)pid {
    if (pid.length == 0) return;
    NSUInteger ame431_idx = [self.remoteItems indexOfObjectPassingTest:^BOOL(NSDictionary *p, NSUInteger idx, BOOL *stop) {
        return [p[@"id"] isKindOfClass:[NSString class]] && [(NSString *)p[@"id"] isEqualToString:pid];
    }];
    if (ame431_idx == NSNotFound) return;
    [self ame333_beginRemoteInstallForRow:(NSInteger)ame431_idx];
}

// ★ Task431：按钮回调入口——builtin 项按 manifest.pluginId 回查（dirName 与
//   pluginId 可能不同名），防重入守卫沿用 ame318_beginInstallForRow:。
- (void)ame318_beginInstallForPluginId:(NSString *)pid {
    if (pid.length == 0) return;
    NSUInteger ame431_idx = [self.items indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        AmePluginManifest *m = item[@"manifest"];
        return m != nil && [m.pluginId isEqualToString:pid];
    }];
    if (ame431_idx == NSNotFound) return;
    [self ame318_beginInstallForRow:(NSInteger)ame431_idx];
}

// ★ Task431：详情页导航收口（原 didSelectRow 内联链——按钮与行点击共用）
- (void)ame431_openPluginDetail:(NSString *)pid {
    ZL2PluginDetailViewController *detail =
        [[ZL2PluginDetailViewController alloc] initWithPluginId:pid];
    [self.navigationController pushViewController:detail animated:YES];
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
