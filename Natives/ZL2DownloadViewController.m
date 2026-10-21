//
// ZL2DownloadViewController.m — ZL2 风格下载页实现（7.0-UI-9-a：下载页分类 M3 重写）
//
// 移植对象：ZalithLauncher2 DownloadScreen.kt（GNU GPL 参考副本，只读）。
// ZL2 原布局为「左类别轨 + 内容区」双栏；本页按移动端信息架构适配为
// 「大标题 + 横向类别 chips + 内容容器」竖向三段，chips 是主页
// ZL2HomeViewController 同款 UIControl chip 模式的横排变体（图标 14pt +
// fontLabelMedium 文字、选中 primaryContainer / 未选 surfaceContainer），
// iPhone 窄屏横向滚动 / iPad 宽屏单行铺开，双 idiome 同一套代码。
//
// 六类目标 VC（顺序对标 ZL2 DownloadScreen TabMenu）：
//   0 游戏   DownloadViewController              [[alloc] init]
//   1 整合包 ModpackImportViewController         [[alloc] init]
//   2 模组   ModsManagerViewController           [[alloc] init]
//       —— spec 原文为基类 ResourceListViewController；经 .h/.m 取证：
//         基类自身未实现 reloadResourceList（仅子类实现），而其
//         viewWillAppear 无条件调用 [self reloadResourceList]
//         （ResourceListViewController.m L133），裸基类实例首显必崩
//         unrecognized selector，故替换为同族具体子类 ModsManagerViewController
//         （真正的 Mod 管理页，init 转调基类 initWithTitle 注入模组图标）。
//         偏差已记 worklog，待编排侧确认。
//   3 资源包 ResourcePacksManagerViewController  [[alloc] init]
//   4 存档   WorldsManagerViewController         [[alloc] init]
//   5 光影包 ShadersManagerViewController        [[alloc] init]
//   各管理页 init 均自带「兼容既有调用方」转发（转调 ResourceListViewController
//   基类 initWithTitle:resourceTypeIcon:iconColor: 注入默认标题/图标），plain init
//   为 .h 取证确认的可用签名；spec 中「initWithStyle:UITableViewStyleInsetGrouped」
//   属壳侧 AccountListViewController 的签名，六类目标 VC 均不适用。
//
// 任务胶囊（页头行右侧）：仅 [DownloadTaskManager sharedManager].hasActiveTasks
// 时显示；surfaceContainerHigh 底 / radiusXL（高 32 渲染为全圆胶囊）/ 高 32，
// 内含 60×3 UIProgressView（首个活动任务 progress，负值截 0）+ assignment 类
// SF 图标（SF1.0 档 doc.plaintext，fallback doc.text.fill）+ 活动任务数
// fontLabelMedium；点按第一个活动任务调 [PLTaskProgressViewController
// presentForTaskId:]（ZL2HomeViewController 同款用法）。
//
// 嵌入的旧 VC 保持原样（存量页，后续轮次退役），本页职责是 ZL2 结构壳：
// 懒建 NSMutableDictionary 缓存 + addChildViewController + 四边钉进容器 +
// didMoveToParentViewController；切换时旧的 hidden=YES 新的 hidden=NO，
// 0.18s crossDissolve（与壳同款手法）。
//
// 导航栏约定：本页由壳包在 UINavigationController 里（根页），viewWillAppear
// 隐藏系统栏、viewWillDisappear 恢复——子页经父链 navigationController push 出
// 去的旧页面有返回栏，pop 回来自动隐藏。
//
// 通知面：监听 DownloadTaskManagerDidUpdateTaskNotification /
// DownloadTaskManagerAggregateStateDidChangeNotification（任务胶囊实时刷新；
// addObserver:selector: 在投递线程同步回调，selector 内 dispatch 主线程）。
// 零发送：类别切换是页内状态，不涉壳契约（@"ZL2ShellNavigate" 等不经过本页）。
//
// 红线遵守：颜色/字体/圆角一律 ZL2Theme 类方法（无 AmeTheme/硬编码 UIColor/
// traitCollection 分支）；iOS 14.0 API 上限（无 button.configuration/UIMenu 等；
// SF 符号全 SF1.0 级并带旧名 fallback）；新建视图一律
// translatesAutoresizingMaskIntoConstraints = NO；chips 选中态由属性/数组
// 下标派生（tag 仅作类别下标载荷，不做 viewWithTag: 身份查找）。
//

#import "ZL2DownloadViewController.h"
#import "ZL2Theme.h"
#import "DownloadViewController.h"
#import "ModpackImportViewController.h"
#import "ModsManagerViewController.h"
#import "ResourcePacksManagerViewController.h"
#import "WorldsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskProgressViewController.h"

// SF Symbols 取图兜底（ZL2HomeViewController 同款 helper：符号名异常时降级到
// 旧名而不是空白；本页符号全为 SF1.0 级，正常路径不会走 fallback）
static UIImage *ZL2DownloadSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

@interface ZL2DownloadViewController ()

// 页头行
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIControl *taskCapsule;      // 任务胶囊（可点）
@property (nonatomic, strong) UIProgressView *taskProgressView;
@property (nonatomic, strong) UIImageView *taskIconView;
@property (nonatomic, strong) UILabel *taskCountLabel;

// 类别 chips 横向滚动行
@property (nonatomic, strong) UIScrollView *chipsScroll;
@property (nonatomic, strong) UIStackView *chipsStack;
// chips 三条平行数组（与 arrangedSubviews 同序）——选中态着色按数组下标派生，
// 禁 viewWithTag 存状态（chip.tag 仅作 ame_chipTapped: 的类别下标载荷）
@property (nonatomic, strong) NSMutableArray<UIControl *> *chipControls;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *chipIconViews;
@property (nonatomic, strong) NSMutableArray<UILabel *> *chipLabels;

// 内容容器与子页
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@property (nonatomic, assign) NSInteger selectedIndex;   // -1 = 尚未选中

// 类别模型（顺序对标 ZL2 DownloadScreen TabMenu；文案暂硬编码中文，
// 与主页 7.0-UI-8 同口径，i18n 入表为后续轮待办）
@property (nonatomic, copy) NSArray<NSString *> *categoryTitles;
@property (nonatomic, copy) NSArray<NSString *> *categorySymbols;

@end

@implementation ZL2DownloadViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _chipControls = [NSMutableArray array];
        _chipIconViews = [NSMutableArray array];
        _chipLabels = [NSMutableArray array];
        _childCache = [NSMutableDictionary dictionary];
        _selectedIndex = -1;
        _categoryTitles = @[@"游戏", @"整合包", @"模组", @"资源包", @"存档", @"光影包"];
        _categorySymbols = @[@"gamecontroller", @"archivebox", @"puzzlepiece",
                             @"paintbrush", @"globe", @"lightbulb"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    [self buildViews];
    [self ame_applyChipAppearance];
    [self refreshTaskCapsule];

    // 首显 attach 类别 0（与壳同款：默认选中第 0 项并立即挂载，避免白屏）
    [self ame_showCategory:0];

    // 通知监听：任务胶囊实时刷新（进度/数量/显隐）；dealloc 统一移除。
    // 两枚通知可能由 manager 在非主线程投递，selector 内 dispatch 主线程。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_taskManagerDidChange:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_taskManagerDidChange:)
                                                 name:DownloadTaskManagerAggregateStateDidChangeNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 根页隐藏系统栏：pop 回来自动隐藏（子页 push 出去时 viewWillDisappear
    // 已恢复系统栏，旧子页可见返回栏）。navigationController 为 nil 时（如
    // 预览 harness 直嵌）消息落空，天然安全。
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self refreshTaskCapsule];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 恢复系统栏：旧子页 push 出去后可见返回栏
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout

- (void)buildViews {
    // ① 页头行：大标题居左
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"下载";
    _titleLabel.font = [ZL2Theme fontTitleLarge];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.isAccessibilityElement = YES;
    _titleLabel.accessibilityLabel = @"下载";
    [self.view addSubview:_titleLabel];

    [self buildTaskCapsule];

    // ② 类别 chips 横向滚动行（高 40；viewport 钉 safeArea，chip 起点与标题对齐）
    _chipsScroll = [[UIScrollView alloc] init];
    _chipsScroll.showsHorizontalScrollIndicator = NO;
    _chipsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_chipsScroll];

    _chipsStack = [[UIStackView alloc] init];
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.spacing = 8;
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_chipsScroll addSubview:_chipsStack];

    for (NSUInteger i = 0; i < self.categoryTitles.count; i++) {
        [_chipsStack addArrangedSubview:[self ame_chipAtIndex:i]];
    }

    // ③ 内容容器（占满余下空间；子页四边钉入）
    _contentContainer = [[UIView alloc] init];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _contentContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_contentContainer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *contentLG = _chipsScroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],

        [_taskCapsule.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_taskCapsule.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],

        [_chipsScroll.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
        [_chipsScroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_chipsScroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_chipsScroll.heightAnchor constraintEqualToConstant:40],

        // 首枚 chip 左缘 +20 与标题对齐；尾枚 chip 右缘 -20 保滚动终点内边距；
        // 垂直 +4/-4 全钉定（chip 高 32 + 上下 4 = 滚动行高 40，内容尺寸无歧义）
        [_chipsStack.leadingAnchor constraintEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentLG.trailingAnchor constraintEqualToAnchor:_chipsStack.trailingAnchor constant:20],
        [_chipsStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:4],
        [contentLG.bottomAnchor constraintEqualToAnchor:_chipsStack.bottomAnchor constant:4],

        [_contentContainer.topAnchor constraintEqualToAnchor:_chipsScroll.bottomAnchor constant:4],
        [_contentContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)buildTaskCapsule {
    _taskCapsule = [[UIControl alloc] init];
    _taskCapsule.backgroundColor = [ZL2Theme surfaceContainerHigh];
    // spec 指定 radiusXL：高 32 时 CoreAnimation 渲染收敛为全圆胶囊
    _taskCapsule.layer.cornerRadius = [ZL2Theme radiusXL];
    _taskCapsule.translatesAutoresizingMaskIntoConstraints = NO;
    _taskCapsule.hidden = YES;   // 显隐由 refreshTaskCapsule 按 hasActiveTasks 派生
    _taskCapsule.isAccessibilityElement = YES;
    _taskCapsule.accessibilityTraits = UIAccessibilityTraitButton;
    [_taskCapsule addTarget:self
                     action:@selector(ame_taskCapsuleTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_taskCapsule];

    _taskProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _taskProgressView.trackTintColor = [ZL2Theme outlineVariant];
    _taskProgressView.progressTintColor = [ZL2Theme primary];
    _taskProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    [_taskCapsule addSubview:_taskProgressView];

    // assignment 类图标（SF1.0 档：doc.plaintext iOS13，fallback doc.text.fill iOS13）
    UIImage *capsuleIcon = ZL2DownloadSystemImage(@"doc.plaintext", @"doc.text.fill");
    _taskIconView = [[UIImageView alloc] initWithImage:[capsuleIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _taskIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _taskIconView.contentMode = UIViewContentModeScaleAspectFit;
    _taskIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_taskCapsule addSubview:_taskIconView];

    _taskCountLabel = [[UILabel alloc] init];
    _taskCountLabel.font = [ZL2Theme fontLabelMedium];
    _taskCountLabel.textColor = [ZL2Theme onSurface];
    _taskCountLabel.numberOfLines = 1;
    _taskCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_taskCapsule addSubview:_taskCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_taskCapsule.heightAnchor constraintEqualToConstant:32],
        [_taskProgressView.leadingAnchor constraintEqualToAnchor:_taskCapsule.leadingAnchor constant:12],
        [_taskProgressView.centerYAnchor constraintEqualToAnchor:_taskCapsule.centerYAnchor],
        [_taskProgressView.widthAnchor constraintEqualToConstant:60],
        [_taskProgressView.heightAnchor constraintEqualToConstant:3],
        [_taskIconView.leadingAnchor constraintEqualToAnchor:_taskProgressView.trailingAnchor constant:8],
        [_taskIconView.centerYAnchor constraintEqualToAnchor:_taskCapsule.centerYAnchor],
        [_taskIconView.widthAnchor constraintEqualToConstant:14],
        [_taskIconView.heightAnchor constraintEqualToConstant:14],
        [_taskCountLabel.leadingAnchor constraintEqualToAnchor:_taskIconView.trailingAnchor constant:4],
        [_taskCountLabel.centerYAnchor constraintEqualToAnchor:_taskCapsule.centerYAnchor],
        [_taskCountLabel.trailingAnchor constraintEqualToAnchor:_taskCapsule.trailingAnchor constant:-12],
    ]];
}

// 单枚类别 chip（home 页 chipWithTitle: 的带图标变体）：
// 高 32 / 水平内边距 16（垂直由 32 高与 14pt 图标天然给出 ≥8）/ radiusS /
// 图标 14pt + 文字 fontLabelMedium；选中着色统一走 ame_applyChipAppearance
- (UIControl *)ame_chipAtIndex:(NSUInteger)index {
    UIControl *chip = [[UIControl alloc] init];
    chip.backgroundColor = [ZL2Theme surfaceContainer];   // 初始未选态（appearance 统一刷新）
    chip.layer.cornerRadius = [ZL2Theme radiusS];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    // tag 仅作 ame_chipTapped: 的类别下标载荷（不做 viewWithTag: 身份查找）
    chip.tag = (NSInteger)index;
    chip.isAccessibilityElement = YES;
    chip.accessibilityLabel = self.categoryTitles[index];
    chip.accessibilityTraits = UIAccessibilityTraitButton;

    // SF1.0 基名 + 同族 fill 兜底（gamecontroller/puzzlepiece 为 iOS14 档，
    // archivebox/paintbrush/globe/lightbulb 为 iOS13 档，均为 SF1.0 级）
    NSString *symbol = self.categorySymbols[index];
    UIImage *iconImage = ZL2DownloadSystemImage(symbol, [symbol stringByAppendingString:@".fill"]);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [chip addSubview:iconView];

    UILabel *label = [[UILabel alloc] init];
    label.text = self.categoryTitles[index];
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [chip addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [chip.heightAnchor constraintEqualToConstant:32],
        [iconView.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:16],
        [iconView.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:14],
        [iconView.heightAnchor constraintEqualToConstant:14],
        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:6],
        [label.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-16],
    ]];

    [chip addTarget:self
             action:@selector(ame_chipTapped:)
   forControlEvents:UIControlEventTouchUpInside];

    [_chipControls addObject:chip];
    [_chipIconViews addObject:iconView];
    [_chipLabels addObject:label];
    return chip;
}

#pragma mark - Chips 选中态（数组下标派生，单一来源）

- (void)ame_applyChipAppearance {
    for (NSUInteger i = 0; i < self.chipControls.count; i++) {
        BOOL selected = ((NSInteger)i == self.selectedIndex);
        UIControl *chip = self.chipControls[i];
        chip.backgroundColor = selected ? [ZL2Theme primaryContainer]
                                        : [ZL2Theme surfaceContainer];
        self.chipIconViews[i].tintColor = selected ? [ZL2Theme onPrimaryContainer]
                                                   : [ZL2Theme onSurfaceVariant];
        self.chipLabels[i].textColor = selected ? [ZL2Theme onPrimaryContainer]
                                                : [ZL2Theme onSurfaceVariant];
        chip.accessibilityTraits = UIAccessibilityTraitButton |
                                   (selected ? UIAccessibilityTraitSelected : 0);
    }
}

#pragma mark - 类别切换（懒建缓存 + 首显 attach + hidden 切换，壳同款手法）

- (void)ame_chipTapped:(UIControl *)sender {
    [self ame_showCategory:sender.tag];
}

- (void)ame_showCategory:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.categoryTitles.count) return;
    UIViewController *next = [self ame_childForIndex:index];
    if (!next) return;

    // 重复点击当前类别：仅归位外观，不重播过渡
    if (index == self.selectedIndex && next.view.superview) {
        [self ame_applyChipAppearance];
        return;
    }

    UIViewController *prev = nil;
    if (self.selectedIndex >= 0) {
        prev = self.childCache[@(self.selectedIndex)];
    }

    [self ame_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.contentContainer
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.selectedIndex = index;
    [self ame_applyChipAppearance];
}

- (UIViewController *)ame_childForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *vc = nil;
    switch (index) {
        case 0: {
            vc = [[DownloadViewController alloc] init];
            break;
        }
        case 1: {
            vc = [[ModpackImportViewController alloc] init];
            break;
        }
        case 2: {
            // 模组：spec 原文 ResourceListViewController（裸基类缺
            // reloadResourceList 实现，首显必崩），替换为同族具体子类，
            // 详见文件头说明
            vc = [[ModsManagerViewController alloc] init];
            break;
        }
        case 3: {
            vc = [[ResourcePacksManagerViewController alloc] init];
            break;
        }
        case 4: {
            vc = [[WorldsManagerViewController alloc] init];
            break;
        }
        case 5: {
            vc = [[ShadersManagerViewController alloc] init];
            break;
        }
        default:
            return nil;
    }
    self.childCache[@(index)] = vc;
    return vc;
}

- (void)ame_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

#pragma mark - 任务胶囊

- (void)refreshTaskCapsule {
    if (!self.isViewLoaded) return;

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    BOOL active = [manager hasActiveTasks];
    self.taskCapsule.hidden = !active;
    if (!active) return;

    // 活动任务数（Downloading + Pending）
    NSInteger activeCount = (NSInteger)[manager tasksWithStates:@[
        @(DownloadTaskStateDownloading),
        @(DownloadTaskStatePending),
    ]].count;
    self.taskCountLabel.text = [NSString stringWithFormat:@"%ld", (long)activeCount];
    self.taskCapsule.accessibilityLabel =
        [NSString stringWithFormat:@"下载任务进行中，共 %ld 个", (long)activeCount];

    // 首个活动任务的 progress（0~1；负值=未知 → 截 0）
    double progress = 0.0;
    for (DownloadTaskItem *item in [manager allTasks]) {
        if (item.state == DownloadTaskStateDownloading ||
            item.state == DownloadTaskStatePending) {
            progress = item.progress;
            break;
        }
    }
    if (progress < 0.0) progress = 0.0;
    if (progress > 1.0) progress = 1.0;
    [self.taskProgressView setProgress:(float)progress animated:NO];
}

- (void)ame_taskCapsuleTapped {
    // ZL2HomeViewController 同款用法：遍历 allTasks 取第一个活动任务的
    // taskId → 统一进度页（presentForTaskId: 自带同屏去重/替换）
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSString *taskId = nil;
    for (DownloadTaskItem *item in [manager allTasks]) {
        if (item.state == DownloadTaskStateDownloading ||
            item.state == DownloadTaskStatePending) {
            taskId = item.taskId;
            break;
        }
    }
    if (!taskId) {
        taskId = [manager allTasks].firstObject.taskId;   // 兜底（hasActiveTasks 恒真时不可达）
    }
    if (taskId.length > 0) {
        [PLTaskProgressViewController presentForTaskId:taskId];
    }
}

// manager 通知投递线程不定（addObserver:selector: 同步回调），统一回主线程刷 UI
- (void)ame_taskManagerDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshTaskCapsule];
    });
}

@end
