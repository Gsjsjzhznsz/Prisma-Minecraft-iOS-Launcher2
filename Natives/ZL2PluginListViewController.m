#import "ZL2PluginListViewController.h"
#import "AmePluginKit.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "PLRendererPluginService.h"
#import "utils.h" // localize

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ═══ ★Task429（§11.4 管理端最小接入）：渲染器插件软链协议 ═══
// PLRendererPluginService / PLRendererPluginEntry 的影子协议 —— 本页零
// import 服务头、零链接符号依赖（服务 TU 未进构建时 NSClassFromString 得
// nil，渲染器插件组整组隐藏；ame428 PLGameIntegrityService 软链判例同款）。
@protocol Ame429RendererServiceShadow <NSObject>
+ (NSArray<NSDictionary *> *)rendererChoiceOverrides;
+ (BOOL)isRendererPluginEnabled:(NSString *)pluginId;
+ (void)setRendererPluginEnabled:(BOOL)enabled pluginId:(NSString *)pluginId;
+ (BOOL)uninstallRendererPlugin:(NSString *)pluginId;
@end
@protocol Ame429RendererEntryShadow <NSObject>
@property (nonatomic, readonly) NSString *pluginId;
@property (nonatomic, readonly) NSString *rendererName;
@property (nonatomic, readonly) NSString *driverType;
@property (nonatomic, readonly) NSArray<NSString *> *abi;
@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly) BOOL enabled;
@end

// ═══════════════════════════════════════════════════════════════════
// ZL2PluginListViewController 实现（Task 317 / ★ Task345 结构性重排）
// 口径注释：
//  · ★ Task345（用户第四轮复诉"插件只变了配色"定案）：本页旧实现是
//    系统按钮式表格单元格 —— 系统容器的圆角/几何不经 ame341/ame343
//    令牌引擎，fluent-ui 插件的形状/布局覆盖到达时【本页纹丝不动】
//    （色与字阶变了、排版没变 = "只变了配色"感知的结构性根源）。
//    重排三件：① 页首 hero 头卡（图标瓦片 + 计数摘要 + 两个一级动作
//    按钮，全部走令牌）；② Plain 卡片流自绘单元格（图标瓦片 36pt +
//    标题/副文 + 尾随开关/chevron，圆角/边距/行高全经
//    ZL2Theme radius*/ame343_layoutMetric 消费 —— 插件覆盖即全页生效）；
//    ③ 节标题自绘（卡外 labelMedium）。逻辑链（安装/启停/贡献行/对话框）
//    逐位保留零改动。
//  · 表三区：0=已装插件卡（含启停开关） 1=插件贡献行 2=API 说明行
//    3=使用指南（Task327）
//  · 安装链：文档选择器(zip) → 后台解压+校验 → 主线程权限确认 M3 对话框
//    （高危权限 ⚠ 标注 + 默认拒绝说明）→ 落位自动启用
//  · 启停开关 = Runtime 装载/卸载；开关即生效，无需重启启动器
//  · 贡献行点按 → Runtime 转发到插件 JS 回调
// ═══════════════════════════════════════════════════════════════════

#pragma mark - Task345 自绘插件卡单元格

/// 自绘卡片单元格：图标瓦片 + 双行文本 + 尾随槽（开关或 chevron）。
/// 圆角/边距/瓦片尺寸全部经 ZL2Theme 令牌与 ame343 布局刻度消费——
/// fluent-ui 等主题插件的形状/布局覆盖到达时，本 cell 与页面一同变排。
@interface Ame345PluginCardCell : UITableViewCell
@property (nonatomic, strong) UIView *card;          ///< 卡底（surfaceBright + radiusM）
@property (nonatomic, strong) UIView *tile;          ///< 图标瓦片（primaryContainer + radiusM）
@property (nonatomic, strong) UIImageView *tileIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UIView *trailingSlot;  ///< 外挂槽（开关/chevron 由 caller 塞）
// 单行/双行双态约束组（Task345 自调整尺寸确定性）
@property (nonatomic, strong) NSLayoutConstraint *cardMinHeight;
@property (nonatomic, strong) NSLayoutConstraint *titleCenterConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleBottomConstraint; ///< 正文流态：title.bottom ≤ card.bottom - inB
@property (nonatomic, strong) NSLayoutConstraint *subBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *subFlowConstraint;
@end

@implementation Ame345PluginCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.clipsToBounds = NO;

        _card = [[UIView alloc] init];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = [ZL2Theme surfaceBright];
        _card.layer.cornerRadius = [ZL2Theme radiusM];
        _card.layer.borderWidth = 1.0;
        _card.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
        _card.clipsToBounds = YES;
        [self.contentView addSubview:_card];

        _tile = [[UIView alloc] init];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _tile.backgroundColor = [ZL2Theme primaryContainer];
        _tile.layer.cornerRadius = [ZL2Theme radiusM];
        _tile.clipsToBounds = YES;
        [_card addSubview:_tile];

        _tileIcon = [[UIImageView alloc] init];
        _tileIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _tileIcon.contentMode = UIViewContentModeScaleAspectFit;
        _tileIcon.tintColor = [ZL2Theme onPrimaryContainer];
        [_tile addSubview:_tileIcon];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.numberOfLines = 1;
        [_card addSubview:_titleLabel];

        _subLabel = [[UILabel alloc] init];
        _subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subLabel.numberOfLines = 2;
        [_card addSubview:_subLabel];

        [self ame345_installConstraints];
        [self ame345_refreshTokens];
    }
    return self;
}

- (void)ame345_installConstraints {
    // 布局刻度经 ame343（无覆盖 = fallback 即现行 ZL2 刻度）：
    // 卡片外边距 H / 内边距 X·Top·Bottom / 内容间隙 / 卡片圆角走 radiusM。
    CGFloat mV = [ZL2Theme ame343_layoutMetric:@"cardMarginV" fallback:5.0];
    CGFloat inX = [ZL2Theme ame343_layoutMetric:@"cardInsetX" fallback:14.0];
    CGFloat inT = [ZL2Theme ame343_layoutMetric:@"cardInsetTop" fallback:12.0];
    CGFloat inB = [ZL2Theme ame343_layoutMetric:@"cardInsetBottom" fallback:12.0];
    CGFloat tileSide = 36.0;

    // 高度确定性：单行态 = card.minHeight（瓦片 + 上下内边距）驱动；
    // 双行态 = title.top → sub.bottom 链驱动（ame345_setTitles 切换）。
    _cardMinHeight = [_card.heightAnchor constraintGreaterThanOrEqualToConstant:tileSide + inT + inB];

    _titleCenterConstraint = [_titleLabel.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor];
    _titleTopConstraint = [_titleLabel.topAnchor constraintEqualToAnchor:_card.topAnchor constant:inT];
    _titleBottomConstraint = [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_card.bottomAnchor constant:-inB];
    _subBottomConstraint = [_subLabel.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-inB];
    _subFlowConstraint = [_subLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0];
    _titleTopConstraint.active = NO;   // 默认单行态
    _titleBottomConstraint.active = NO;
    _subBottomConstraint.active = NO;
    _subFlowConstraint.active = NO;
    _titleCenterConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        _cardMinHeight,

        [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:mV],
        [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-mV],
        [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

        [_tile.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:inX],
        [_tile.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        [_tile.widthAnchor constraintEqualToConstant:tileSide],
        [_tile.heightAnchor constraintEqualToConstant:tileSide],
        [_tileIcon.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
        [_tileIcon.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
        [_tileIcon.widthAnchor constraintEqualToConstant:20.0],
        [_tileIcon.heightAnchor constraintEqualToConstant:20.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_card.trailingAnchor constant:-inX],
        _titleCenterConstraint,
        _titleTopConstraint,

        [_subLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_card.trailingAnchor constant:-inX],
        _subBottomConstraint,
        _subFlowConstraint,
    ]];
}

/// 主题令牌重算（复用出列与明暗切换共走；圆角/边距/字体随插件覆盖生效）。
- (void)ame345_refreshTokens {
    CGFloat mH = [ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0];
    _card.backgroundColor = [ZL2Theme surfaceBright];
    _card.layer.cornerRadius = [ZL2Theme radiusM];
    _card.layer.borderColor = [ZL2Theme outlineVariant].CGColor;
    _tile.backgroundColor = [ZL2Theme primaryContainer];
    _tile.layer.cornerRadius = [ZL2Theme radiusM];
    _tileIcon.tintColor = [ZL2Theme onPrimaryContainer];
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _subLabel.font = [ZL2Theme fontBodyMedium];
    _subLabel.textColor = [ZL2Theme onSurfaceVariant];
    // 附件槽右缘随卡片外边距重算（重用池 cell 跨宽度场景兜底）。
    if (_trailingSlot.superview) {
        _trailingSlot.frame = CGRectMake(0, 0,
            _trailingSlot.frame.size.width, _trailingSlot.frame.size.height);
    }
    (void)mH;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 尾随槽钉卡内右缘（frame 布局与 autolayout 混用最小面：槽内容自管）。
    if (_trailingSlot.superview) {
        CGFloat mH = [ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0];
        CGFloat inX = [ZL2Theme ame343_layoutMetric:@"cardInsetX" fallback:14.0];
        CGFloat cardRight = self.contentView.bounds.size.width - mH - inX;
        CGFloat cy = self.contentView.bounds.size.height / 2.0;
        CGSize s = _trailingSlot.frame.size;
        _trailingSlot.frame = CGRectMake(cardRight - s.width, cy - s.height / 2.0, s.width, s.height);
    }
}

/// 文本行基线偏移补偿（tile 居中锚定，文本双行上下展开）。
- (void)ame345_setTitles:(NSString *)title sub:(NSString *)sub icon:(NSString *)iconName {
    self.titleLabel.text = title ?: @"";
    self.subLabel.text = sub ?: @"";
    self.subLabel.hidden = (sub.length == 0);
    UIImage *img = iconName.length ? [UIImage systemImageNamed:iconName] : nil;
    if (!img && iconName.length) img = [UIImage systemImageNamed:iconName]; // Task111 二次补拉语义
    self.tileIcon.image = img;
    self.tile.hidden = (img == nil);
    // 单行/双行态切换（自调整尺寸双驱动源，见 ame345_installConstraints 注）。
    BOOL twoLine = !self.subLabel.hidden;
    _titleCenterConstraint.active = !twoLine;
    _titleTopConstraint.active = twoLine;
    _titleBottomConstraint.active = NO;   // 正文流态复用复位（ame345_setBodyFlowMode 再启）
    _subBottomConstraint.active = twoLine;
    _subFlowConstraint.active = twoLine;
    // 多行长文本（API/指南行）换行后由 intrinsic 高度接管。
    [self ame345_refreshTokens];
}

/// 无副文本多行正文态（API 说明/使用指南）：title 钉上缘，下缘≤卡底
///（不等式）——短文本回落 minHeight，长文本由 intrinsic 高度撑开卡片。
- (void)ame345_setBodyFlowMode {
    _titleCenterConstraint.active = NO;
    _titleTopConstraint.active = YES;
    _titleBottomConstraint.active = YES;
}

/// 尾随槽挂载（开关/chevron；nil 摘除）。
- (void)ame345_setTrailingSlot:(UIView *)slot {
    if (_trailingSlot.superview) [_trailingSlot removeFromSuperview];
    _trailingSlot = slot;
    if (slot) {
        slot.translatesAutoresizingMaskIntoConstraints = YES;
        [self.contentView addSubview:slot];
    }
    [self setNeedsLayout];
}

@end

#pragma mark - 页面

@interface ZL2PluginListViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *cards;   // {id, manifest, enabled}
@property (nonatomic, strong) NSArray<NSDictionary *> *contributedRows;
@property (nonatomic, strong) UILabel *ame345_heroCountLabel;
@property (nonatomic, assign) CGFloat ame345_lastHeroWidth;
// ★Task429：渲染器插件条目（id<Ame429RendererEntryShadow>；软链消费，
//   空 = 服务缺席/无插件档，渲染器插件组整组隐藏）
@property (nonatomic, strong) NSArray *ame429_rendererEntries;
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

    // ★ Task345：Plain 卡片流（Task325 仓库页同款口径）——cell 自绘卡底，
    //   圆角/边距全经令牌，插件形状/布局覆盖即全页生效。
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 86.0;
    self.table.contentInset = UIEdgeInsetsMake(6, 0, 16, 0);
    [self.table registerClass:[Ame345PluginCardCell class] forCellReuseIdentifier:@"ame345.plugin.card"];
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self ame345_installHeroHeader];
    [self ame317_reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ame345_remindHeroHeaderIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame317_reload];
}

#pragma mark - Task345 hero 头卡

- (void)ame345_installHeroHeader {
    CGFloat mH = [ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0];
    CGFloat inX = [ZL2Theme ame343_layoutMetric:@"cardInsetX" fallback:14.0];
    CGFloat inT = [ZL2Theme ame343_layoutMetric:@"cardInsetTop" fallback:12.0];
    CGFloat inB = [ZL2Theme ame343_layoutMetric:@"cardInsetBottom" fallback:12.0];
    CGFloat gap = [ZL2Theme ame343_layoutMetric:@"cardContentGap" fallback:4.0];
    CGFloat btnH = [ZL2Theme ame343_layoutMetric:@"buttonHeight" fallback:40.0];

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

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = localize(@"ame317.list.title", nil);
    titleLabel.font = [ZL2Theme fontHeadline];
    titleLabel.textColor = [ZL2Theme onSurface];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = [ZL2Theme fontBodyMedium];
    countLabel.textColor = [ZL2Theme onSurfaceVariant];
    self.ame345_heroCountLabel = countLabel;

    // 一级动作行：仓库（实心）+ 导入（描边）——原"+"菜单动作上浮为可见操作。
    CGFloat rS = [ZL2Theme radiusS];
    UIButton *repoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    repoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    repoBtn.backgroundColor = [ZL2Theme primary];
    repoBtn.layer.cornerRadius = rS;
    [repoBtn setTitle:localize(@"ame318.repo.nav", nil) forState:UIControlStateNormal];
    [repoBtn setTitleColor:[ZL2Theme onPrimary] forState:UIControlStateNormal];
    repoBtn.titleLabel.font = [ZL2Theme fontLabelLarge];
    [repoBtn addTarget:self action:@selector(ame318_openRepo) forControlEvents:UIControlEventTouchUpInside];

    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    importBtn.translatesAutoresizingMaskIntoConstraints = NO;
    importBtn.backgroundColor = [UIColor clearColor];
    importBtn.layer.cornerRadius = rS;
    importBtn.layer.borderWidth = 1.0;
    importBtn.layer.borderColor = [ZL2Theme outline].CGColor;
    [importBtn setTitle:localize(@"ame345.list.action.import", nil) forState:UIControlStateNormal];
    [importBtn setTitleColor:[ZL2Theme primary] forState:UIControlStateNormal];
    importBtn.titleLabel.font = [ZL2Theme fontLabelLarge];
    [importBtn addTarget:self action:@selector(ame317_pickPluginZip) forControlEvents:UIControlEventTouchUpInside];

    [card addSubview:tile];
    [card addSubview:titleLabel];
    [card addSubview:countLabel];
    [card addSubview:repoBtn];
    [card addSubview:importBtn];

    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inX],
        [tile.topAnchor constraintEqualToAnchor:card.topAnchor constant:inT],
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

        [repoBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inX],
        [repoBtn.topAnchor constraintEqualToAnchor:tile.bottomAnchor constant:inT],
        [repoBtn.heightAnchor constraintEqualToConstant:btnH],
        [importBtn.leadingAnchor constraintEqualToAnchor:repoBtn.trailingAnchor constant:gap + inX],
        [importBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inX],
        [importBtn.centerYAnchor constraintEqualToAnchor:repoBtn.centerYAnchor],
        [importBtn.heightAnchor constraintEqualToAnchor:repoBtn.heightAnchor],
        [repoBtn.widthAnchor constraintEqualToAnchor:importBtn.widthAnchor],
        [importBtn.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-inB],

        [card.bottomAnchor constraintEqualToAnchor:repoBtn.bottomAnchor constant:inB],
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

- (void)ame345_refreshHeroCount {
    if (!self.ame345_heroCountLabel) return;
    NSUInteger running = 0;
    for (NSDictionary *card in self.cards) {
        if ([card[@"enabled"] boolValue]) running++;
    }
    self.ame345_heroCountLabel.text = [NSString stringWithFormat:
        localize(@"ame345.list.hero.count", nil),
        (unsigned long)self.cards.count, (unsigned long)running];
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
    // ★Task429（§11.4 管理端最小接入）：渲染器插件组（与 JS 插件共用
    //   安装/启停/删除存储层，仅包格式校验不同）。软链取扫描面；服务
    //   缺席 = 空组隐藏。启停直写 state.json enabled 表（与 JS 插件详情
    //   页开关同源）；删除走服务卸载链（目录 + purge state）。
    //   ★Task432：扫描面提取为 ame429_rescanRendererEntries（拨杆回调同步
    //   局部刷新复用同一份扫描实现，避免双份漂移）。
    [self ame429_rescanRendererEntries];
    [self ame345_refreshHeroCount];
    [self.table reloadData];
}

/// ★Task432（P2 开关 0.15s 重载竞态）：渲染器插件组扫描面提取（原 ame317_reload
/// 内联块）——ame317_reload 与拨杆同步局部刷新共用；服务缺席 = 空组。
- (void)ame429_rescanRendererEntries {
    Class ame429_svc = NSClassFromString(@"PLRendererPluginService");
    NSArray *ame429_scanned = nil;
    // ★Task429-r1 热修判例（smoke CI 实录：Class 类型直发 +availableRenderers =
    //   no known class method）——ame428 判例同款 performSelector 软链。
    if (ame429_svc && [ame429_svc respondsToSelector:NSSelectorFromString(@"availableRenderers")]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        ame429_scanned = [ame429_svc performSelector:NSSelectorFromString(@"availableRenderers")];
        #pragma clang diagnostic pop
    }
    NSMutableArray *ame429_list = [NSMutableArray array];
    for (id ame429_entry in ame429_scanned) {
        if ([ame429_entry conformsToProtocol:@protocol(Ame429RendererEntryShadow)]) {
            [ame429_list addObject:ame429_entry];
        }
    }
    self.ame429_rendererEntries = [ame429_list copy];
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
        NSString *rendererId = nil;
        BOOL rendererPackage = NO;
        if (code == AmePluginInstallErrBadSchema || code == AmePluginInstallErrBadEntry) {
            AmePluginInstallResult rendererCode =
                [PLRendererPluginService installRendererPluginFromZip:url.path outId:&rendererId];
            if (rendererCode == AmePluginInstallOK) {
                code = rendererCode;
                rendererPackage = YES;
            }
        }
        [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (rendererPackage) {
                [wself ame317_reload];
                [ZL2M3Dialog showTitle:rendererId ?: localize(@"ame317.common.ok", @"完成")
                                   body:localize(@"ame429.renderer.installed", @"渲染器插件已安装并启用")
                           confirmTitle:localize(@"ame317.common.ok", @"确定")
                            destructive:NO
                             onConfirm:nil
                              onCancel:nil];
            } else {
                [wself ame317_installDidFinish:code manifest:m];
            }
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
    // ★Task429：+1 渲染器插件组（有插件档才出现；0-3 区 index 零漂移）
    return 4 + (self.ame429_rendererEntries.count > 0 ? 1 : 0);   // ★ Task327：0 已装 / 1 贡献行 / 2 API 行 / 3 使用指南 / 4 渲染器插件
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(self.cards.count, 1); // 空态占位行
    if (section == 1) return self.contributedRows.count;
    if (section == 4) return self.ame429_rendererEntries.count;   // ★Task429：渲染器插件
    return 1; // API 版本说明行 / 指南行
}

/// Task345：节标题自绘（卡外 labelMedium；原系统组头随 Plain 样式退役）。
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = nil;
    if (section == 0) text = localize(@"ame317.list.section_installed", nil);
    else if (section == 1) text = localize(@"ame317.list.section_rows", nil);
    else if (section == 3) text = localize(@"ame327.plugin.guide.title", nil);
    else if (section == 4) text = localize(@"ame429.list.section_renderers", nil);   // ★Task429
    else text = localize(@"ame317.list.section_about", nil);

    UILabel *label = [[UILabel alloc] init];
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.text = text;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *wrap = [[UIView alloc] init];
    wrap.backgroundColor = [UIColor clearColor];
    [wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor
                                            constant:[ZL2Theme ame343_layoutMetric:@"cardMarginH" fallback:16.0] + 4.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor constant:-20.0],
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:10.0],
        [label.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-2.0],
    ]];
    return wrap;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 28.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    Ame345PluginCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ame345.plugin.card"
                                                                 forIndexPath:indexPath];

    // 文本行（API/指南/空态共用排版：无瓦片、无尾随槽）。
    if (indexPath.section == 0 && self.cards.count == 0) {
        [cell ame345_setTitles:localize(@"ame317.list.empty", nil)
                           sub:nil
                          icon:nil];
        return cell;
    }
    if (indexPath.section == 2) {
        [cell ame345_setTitles:[NSString stringWithFormat:
            localize(@"ame317.list.api_line", nil), [AmePluginManager apiVersion]]
                           sub:nil
                          icon:@"curlybraces"];
        cell.titleLabel.numberOfLines = 0;
        cell.titleLabel.font = [ZL2Theme fontBodyMedium];
        cell.titleLabel.textColor = [ZL2Theme onSurfaceVariant];
        [cell ame345_setBodyFlowMode];
        return cell;
    }
    if (indexPath.section == 3) {
        // ★ Task327：使用指南行（效果即用 / 高危授权 / AI 写插件）
        [cell ame345_setTitles:localize(@"ame327.plugin.guide.body", nil)
                           sub:nil
                          icon:@"questionmark.circle"];
        cell.titleLabel.numberOfLines = 0;
        cell.titleLabel.font = [ZL2Theme fontBodyMedium];
        cell.titleLabel.textColor = [ZL2Theme onSurfaceVariant];
        [cell ame345_setBodyFlowMode];
        return cell;
    }
    if (indexPath.section == 4) {
        // ★Task429：渲染器插件卡（启停开关与 JS 插件同源 state.json；
        //   点按 = 卸载确认弹窗）。副文 = 驱动类型 · ABI · 版本（§11.4 三字段
        //   档位呈现面）。
        id<Ame429RendererEntryShadow> ame429_entry =
            self.ame429_rendererEntries[(NSUInteger)indexPath.row];
        NSString *ame429_sub = [NSString stringWithFormat:@"%@ · %@ · v%@",
            ame429_entry.driverType,
            [ame429_entry.abi componentsJoinedByString:@"/"],
            ame429_entry.version];
        [cell ame345_setTitles:ame429_entry.rendererName
                           sub:ame429_sub
                          icon:@"cpu"];
        cell.titleLabel.textColor = ame429_entry.enabled ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
        ZL2M3Switch *sw = [[ZL2M3Switch alloc] init];
        sw.on = ame429_entry.enabled;
        sw.tag = 10000 + indexPath.row;   // 渲染器组 tag 偏移（与 section 0 启停开关分流）
        [sw addTarget:self action:@selector(ame317_enableToggled:)
             forControlEvents:UIControlEventValueChanged];
        UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [ZL2M3Switch switchWidth] + 8, [ZL2M3Switch switchHeight])];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [slot addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[
            [sw.centerYAnchor constraintEqualToAnchor:slot.centerYAnchor],
            [sw.leadingAnchor constraintEqualToAnchor:slot.leadingAnchor],
        ]];
        [cell ame345_setTrailingSlot:slot];
        return cell;
    }

    if (indexPath.section == 0) {
        NSDictionary *card = self.cards[(NSUInteger)indexPath.row];
        AmePluginManifest *m = card[@"manifest"];
        BOOL enabled = [card[@"enabled"] boolValue];
        NSString *ver = [NSString stringWithFormat:@"v%@", m.version ?: @"?"];
        NSString *authorLine = m.author.length ?
            [NSString stringWithFormat:localize(@"ame317.list.by_author", nil), m.author] : @"";
        NSString *sub = [NSString stringWithFormat:@"%@ · %@",
                         ver, authorLine];
        [cell ame345_setTitles:(m.name ?: m.pluginId)
                           sub:sub
                          icon:@"puzzlepiece.extension"];
        cell.titleLabel.textColor = enabled ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];

        // 启停开关（Task345：挂自绘槽，layoutSubviews 钉卡内右缘）。
        ZL2M3Switch *sw = [[ZL2M3Switch alloc] init];
        sw.on = enabled;
        sw.tag = indexPath.row;
        [sw addTarget:self action:@selector(ame317_enableToggled:)
             forControlEvents:UIControlEventValueChanged];
        UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [ZL2M3Switch switchWidth] + 8, [ZL2M3Switch switchHeight])];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [slot addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[
            [sw.centerYAnchor constraintEqualToAnchor:slot.centerYAnchor],
            [sw.leadingAnchor constraintEqualToAnchor:slot.leadingAnchor],
        ]];
        [cell ame345_setTrailingSlot:slot];
        return cell;
    }

    // 贡献行（section 1）：点按转发插件。
    NSDictionary *row = self.contributedRows[(NSUInteger)indexPath.row];
    [cell ame345_setTitles:(row[@"title"] ?: @"")
                       sub:[NSString stringWithFormat:@"%@ · %@",
                            localize(@"ame317.list.from_plugin", nil),
                            row[@"pluginName"] ?: @""]
                      icon:@"sparkles"];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = [ZL2Theme onSurfaceVariant];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14.0, 18.0)];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [slot addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[
        [chevron.centerXAnchor constraintEqualToAnchor:slot.centerXAnchor],
        [chevron.centerYAnchor constraintEqualToAnchor:slot.centerYAnchor],
    ]];
    [cell ame345_setTrailingSlot:slot];
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
    } else if (indexPath.section == 4) {
        // ★Task429：卸载确认（与 JS 插件卸载同款 purge state；运行中会话
        //   不受影响，下次启动生效）。
        id<Ame429RendererEntryShadow> ame429_entry =
            self.ame429_rendererEntries[(NSUInteger)indexPath.row];
        NSString *ame429_pid = ame429_entry.pluginId;
        __weak typeof(self) wself = self;
        [ZL2M3Dialog showTitle:ame429_entry.rendererName
                          body:localize(@"ame429.list.delete_confirm", nil)
                  confirmTitle:localize(@"ame429.list.delete_ok", nil)
                   destructive:YES
                    onConfirm:^{
            Class ame429_svc = NSClassFromString(@"PLRendererPluginService");
            if (ame429_svc && [ame429_svc respondsToSelector:@selector(uninstallRendererPlugin:)]) {
                id<Ame429RendererServiceShadow> ame429_shadow = ame429_svc;
                [ame429_shadow uninstallRendererPlugin:ame429_pid];
            }
            [wself ame317_reload];
        }
                     onCancel:nil];
    }
}

- (void)ame317_enableToggled:(ZL2M3Switch *)sender {
    // ZL2M3Kit 契约：UI 点击内部已自动翻转 _on 再发 ValueChanged，
    // sender.on 即新值（禁再取反——取反=把用户点击写回去）
    // ★Task429：渲染器组开关（tag >= 10000）直写 state.json enabled 表
    //   （与 JS 插件启停同源；启用 = 渲染器列表出现档位，停用 = 隐去，
    //   不触碰用户当前选中渲染器）。
    if (sender.tag >= 10000) {
        NSInteger ame429_row = (NSInteger)sender.tag - 10000;
        if (ame429_row < 0 || (NSUInteger)ame429_row >= self.ame429_rendererEntries.count) return;
        id<Ame429RendererEntryShadow> ame429_entry =
            self.ame429_rendererEntries[(NSUInteger)ame429_row];
        Class ame429_svc = NSClassFromString(@"PLRendererPluginService");
        if (ame429_svc && [ame429_svc respondsToSelector:@selector(setRendererPluginEnabled:pluginId:)]) {
            id<Ame429RendererServiceShadow> ame429_shadow = ame429_svc;
            [ame429_shadow setRendererPluginEnabled:sender.on pluginId:ame429_entry.pluginId];
        }
        // ★Task432（P2 开关 0.15s 重载竞态）：去掉 dispatch_after 延迟整页 reload
        //   （快速连拨时旧延迟回调与新状态交叉互踩）——回调内同步重扫渲染器组
        //   先更新 model 再局部 reloadRows；仅组出现/消失（section 数变化）时
        //   回退整页 reloadData。
        NSUInteger ame429_oldCount = self.ame429_rendererEntries.count;
        [self ame429_rescanRendererEntries];
        NSUInteger ame429_newCount = self.ame429_rendererEntries.count;
        if (ame429_oldCount == ame429_newCount &&
            (NSUInteger)ame429_row < self.ame429_rendererEntries.count) {
            [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:ame429_row inSection:4]]
                              withRowAnimation:UITableViewRowAnimationNone];
        } else {
            [self.table reloadData];
        }
        return;
    }
    if (self.cards.count == 0) return;
    NSUInteger ame432_row = (NSUInteger)sender.tag;
    if (ame432_row >= self.cards.count) return;
    NSDictionary *card = self.cards[ame432_row];
    NSString *pid = card[@"id"];
    BOOL next = sender.on;
    // ★Task432（P2 开关 0.15s 重载竞态）：启停主线程同步生效（setPluginEnabled
    //   同步装载/卸载 context），回调内先更新 model 再局部 reloadRows，消灭
    //   dispatch_after 延迟整页 reload 与快速连拨的交叉窗口。
    [AmePluginRuntime setPluginEnabled:pid enabled:next];
    NSMutableDictionary *ame432_updated = [card mutableCopy];
    ame432_updated[@"enabled"] = @([AmePluginPermissions pluginEnabled:pid] &&
                                   [AmePluginRuntime isRunning:pid]);
    self.cards[ame432_row] = ame432_updated;
    [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)ame432_row inSection:0]]
                      withRowAnimation:UITableViewRowAnimationNone];
}

@end
