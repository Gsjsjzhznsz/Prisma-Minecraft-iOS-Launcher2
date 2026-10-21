//
// ZL2ShellViewController.m — ZL2 风格导航壳实现（7.0-UI-8）
//
// 结构：左 M3 NavigationRail（ZL2RailView 组件）+ 右内容区（child VC 切换，
// 懒建缓存 + 首显 attach + crossDissolve 0.18s 过渡）。
// 页面序：0 主页(ZL2Home) / 1 下载(Download) / 2 版本管理(VersionManager)
//         / 3 账户(AccountList) / 4 设置(LauncherPreferences)。
// 功能页复用现有 VC（7.0-UI-1~7 迁移成果继续有效），仅壳与主页为 ZL2 新写；
// 旧 LauncherCardLayoutViewController / LauncherRootViewController 自本轮起
// 不再作为默认根（SceneDelegate 直连本壳），类文件保留至游戏域桥接退役。
//

#import "ZL2ShellViewController.h"
#import "ZL2Theme.h"
#import "ZL2RailView.h"
#import "ZL2HomeViewController.h"
#import "DownloadViewController.h"
#import "VersionManagerViewController.h"
#import "AccountListViewController.h"
#import "LauncherPreferencesViewController.h"

NSString * const ZL2ShellNavigateNotification = @"ZL2ShellNavigate";

#pragma mark - 私有扩展

@interface ZL2ShellViewController () <ZL2RailViewDelegate>
@property(nonatomic, strong) ZL2RailView *rail;
@property(nonatomic, strong) UIView *container;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@property(nonatomic, assign) NSInteger currentIndex;
@end

@implementation ZL2ShellViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _childCache = [NSMutableDictionary dictionary];
        _currentIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // rail：五项对标 ZL2 信息架构（主页/下载/版本管理/账户/设置）
    CGFloat railW = [ZL2RailView widthForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    self.rail = [[ZL2RailView alloc] initWithItems:@[@"主页", @"下载", @"版本", @"账户", @"设置"]
                                           symbols:@[@"house.fill",
                                                     @"arrow.down.circle.fill",
                                                     @"folder.fill",
                                                     @"person.fill",
                                                     @"gearshape.fill"]];
    self.rail.translatesAutoresizingMaskIntoConstraints = NO;
    self.rail.delegate = self;
    [self.view addSubview:self.rail];

    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    self.container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.container];

    [NSLayoutConstraint activateConstraints:@[
        [self.rail.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.rail.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.rail.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.rail.widthAnchor constraintEqualToConstant:railW],

        [self.container.leadingAnchor constraintEqualToAnchor:self.rail.trailingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.container.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 通知契约：旧启动链（ShowHomePage）+ FCL 账户契约（ShowAccountManager）
    // + ZL2 程序化切页（ZL2ShellNavigate）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showHome)
                                                 name:@"ShowHomePage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showAccount)
                                                 name:@"ShowAccountManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_onNavigate:)
                                                 name:ZL2ShellNavigateNotification
                                               object:nil];

    [self showPageAtIndex:0];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 通知

- (void)ame_showHome {
    [self showPageAtIndex:0];
}

- (void)ame_showAccount {
    [self showPageAtIndex:3];
}

- (void)ame_onNavigate:(NSNotification *)note {
    NSInteger index = [note.userInfo[@"index"] integerValue];
    [self showPageAtIndex:index];
}

#pragma mark - 页面切换

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index > 4) return;
    if (index == self.currentIndex) {
        self.rail.selectedIndex = index;
        return;
    }

    UIViewController *next = [self ame_childForIndex:index];
    UIViewController *prev = [self ame_currentChild];

    [self ame_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.container
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.currentIndex = index;
    self.rail.selectedIndex = index;
}

#pragma mark - Child 管理（懒建缓存 + 首显 attach）

- (UIViewController *)ame_currentChild {
    if (self.currentIndex < 0) return nil;
    return self.childCache[@(self.currentIndex)];
}

- (void)ame_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.container addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.container.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

- (UIViewController *)ame_childForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *vc;
    switch (index) {
        case 0: {
            // 主页：ZL2 新写，单页无 push 需求（切页走通知契约），不包 nav
            vc = [[ZL2HomeViewController alloc] init];
            break;
        }
        case 1: {
            DownloadViewController *download = [[DownloadViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:download];
            break;
        }
        case 2: {
            VersionManagerViewController *versions = [[VersionManagerViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:versions];
            break;
        }
        case 3: {
            AccountListViewController *accounts =
                [[AccountListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            vc = [[UINavigationController alloc] initWithRootViewController:accounts];
            break;
        }
        case 4: {
            LauncherPreferencesViewController *prefs = [[LauncherPreferencesViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:prefs];
            break;
        }
        default:
            return nil;
    }
    self.childCache[@(index)] = vc;
    return vc;
}

+ (CGFloat)railWidthForSizeClass:(UIUserInterfaceIdiom)idiom {
    return [ZL2RailView widthForIdiom:idiom];
}

#pragma mark - ZL2RailViewDelegate

- (void)railView:(ZL2RailView *)rail didSelectIndex:(NSInteger)index {
    [self showPageAtIndex:index];
}

@end
