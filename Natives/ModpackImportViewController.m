#import "utils.h"
//
//  ModpackImportViewController.m
//  Amethyst
//
//  参照 FCL ModpackImportScreen / HMCL ModpackProviderPane / ZL2 ModpackImportScreen 重做
//
//  设计要点：
//    1. 顶部使用 UISegmentedControl 切换 "导入 / 导出"，导出切换时 push 到独立的 ModpackExportViewController
//    2. 导入流程：选择文件 → 解析（轻量 HUD）→ 预览卡片（mod 信息）→ 导入（统一进度页，自动弹出）→ 完成提示
//    3. redesign-download-ui Phase 5 Task 5.1：删除自定义 FCL 风格进度卡片，导入进度由
//       ModpackImportService 注册 DownloadTaskManager 主任务（6 阶段 + autoPresentDetail）驱动
//       PLTaskProgressViewController 统一进度页展示；取消经由统一进度页"取消"按钮 →
//       DownloadTaskManager 置主任务 Cancelled → service 轮询感知（checkCancelledWithError）
//    4. 已导入整合包列表使用现代化的卡片样式
//

#import "ModpackImportViewController.h"
#import "AmeNativeMenu.h"       // ★ Task240：菜单全面系统原生 UIMenu 化
#import "BackgroundManager.h"
#import "ModpackImportService.h"
#import "AmeTheme.h"            // ★ 7.0-UI-3f：Fluent 设计令牌（导入页按钮/文案/卡片面迁移）
#import "ModpackExportViewController.h"
#import "PLProfiles.h"
#import "UnzipKit.h"
// ★Task428：格式探测前置层（工作项一 2.2）
#import "installer/modpack/ModpackConfiguration.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ModpackImportViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UISegmentedControl *tabSegment;       // 顶部 "导入 | 导出" 切换
@property (nonatomic, strong) UIView *headerContainerView;          // 顶部说明 + 选择文件按钮
@property (nonatomic, strong) UILabel *hintLabel;                   // 支持格式说明
@property (nonatomic, strong) UIButton *importButton;               // 主导入按钮
@property (nonatomic, strong) UIButton *importFolderButton;         // ★Task432：文件夹导入入口（MultiMC 未压缩实例目录）
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *importedModpacks;
@property (nonatomic, strong) ModpackImportService *importService;
@property (nonatomic, strong) NSDictionary *currentImportingModpack;

// 轻量加载 HUD（仅解析/删除等本地短操作使用；导入进度走统一进度页）
@property (nonatomic, strong) UIView *loadingOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UILabel *loadingLabel;
@end

@implementation ModpackImportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 适配自定义启动器背景：将当前视图控制器透明化，使全局背景壁纸能够透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.title = localize(@"i18n_str_118", nil);

    [[BackgroundManager sharedManager] applyEffectToView:self.view];

    self.importService = [[ModpackImportService alloc] init];
    self.importedModpacks = [NSMutableArray array];

    [self setupNavigationTab];
    [self setupUI];
    [self loadImportedModpacks];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 回到导入页时，确保 tab 显示"导入"
    self.tabSegment.selectedSegmentIndex = 0;
}

#pragma mark - 顶部 Tab 切换（导入 / 导出）

- (void)setupNavigationTab {
    self.tabSegment = [[UISegmentedControl alloc] initWithItems:@[localize(@"i18n_str_156", nil), localize(@"i18n_str_1298", nil)]];
    self.tabSegment.selectedSegmentIndex = 0;
    [self.tabSegment addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];

    // 放置在 navigationItem.titleView，宽度自适应
    CGSize fittingSize = [self.tabSegment sizeThatFits:CGSizeMake(220, 30)];
    self.tabSegment.frame = CGRectMake(0, 0, MAX(180, fittingSize.width), 30);
    self.navigationItem.titleView = self.tabSegment;
}

- (void)tabChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 1) {
        // 切换到导出：push 到 ModpackExportViewController
        ModpackExportViewController *exportVC = [[ModpackExportViewController alloc] init];
        exportVC.preselectedProfileName = PLProfiles.current.selectedProfileName;
        [self.navigationController pushViewController:exportVC animated:YES];
        // 立即把 tab 切回"导入"，因为返回时 viewWillAppear 会重置
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.selectedSegmentIndex = 0;
        });
    }
}

#pragma mark - UI Setup

- (void)setupUI {
    // 顶部说明 + 选择文件按钮容器
    self.headerContainerView = [[UIView alloc] init];
    self.headerContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerContainerView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerContainerView];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.textColor = [AmeTheme textSecondary];
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.text = localize(@"i18n_str_566", nil);
    [self.headerContainerView addSubview:self.hintLabel];

    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.importButton setTitle:[@"  " stringByAppendingString:localize(@"i18n_str_2055", nil)] forState:UIControlStateNormal];
    [self.importButton setImage:[UIImage systemImageNamed:@"doc.badge.plus"] forState:UIControlStateNormal];
    self.importButton.backgroundColor = [AmeTheme brandPrimary];
    [self.importButton setTitleColor:[AmeTheme textOnBrand] forState:UIControlStateNormal];
    self.importButton.tintColor = [AmeTheme textOnBrand];
    self.importButton.layer.cornerRadius = 12;
    self.importButton.layer.masksToBounds = YES;
    self.importButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.importButton addTarget:self action:@selector(selectModpackFile) forControlEvents:UIControlEventTouchUpInside];
    [self.headerContainerView addSubview:self.importButton];

    // ★Task432（P2 MMC 文件夹导入缺口）：补「导入文件夹」入口——MultiMC/Prism
    //   未压缩实例目录（mmc-pack.json / instance.cfg + .minecraft/）此前仅有
    //   zip 入口无法直接导入。次按钮走目录选择器（UTTypeFolder asCopy）。
    self.importFolderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.importFolderButton setTitle:[@"  " stringByAppendingString:localize(@"ame432.import.folder.button", @"导入文件夹")] forState:UIControlStateNormal];
    [self.importFolderButton setImage:[UIImage systemImageNamed:@"folder.badge.plus"] forState:UIControlStateNormal];
    self.importFolderButton.backgroundColor = [AmeTheme fillSubtle];
    [self.importFolderButton setTitleColor:[AmeTheme textPrimary] forState:UIControlStateNormal];
    self.importFolderButton.tintColor = [AmeTheme textPrimary];
    self.importFolderButton.layer.cornerRadius = 12;
    self.importFolderButton.layer.masksToBounds = YES;
    self.importFolderButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.importFolderButton addTarget:self action:@selector(selectModpackFolder) forControlEvents:UIControlEventTouchUpInside];
    [self.headerContainerView addSubview:self.importFolderButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ModpackCell"];
    self.tableView.rowHeight = 80;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [AmeTheme textSecondary];
    self.emptyLabel.text = localize(@"i18n_str_568", nil);
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.headerContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.headerContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.hintLabel.topAnchor constraintEqualToAnchor:self.headerContainerView.topAnchor],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.headerContainerView.leadingAnchor],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.headerContainerView.trailingAnchor],

        [self.importButton.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:10],
        [self.importButton.leadingAnchor constraintEqualToAnchor:self.headerContainerView.leadingAnchor],
        [self.importButton.trailingAnchor constraintEqualToAnchor:self.headerContainerView.trailingAnchor],
        [self.importButton.heightAnchor constraintEqualToConstant:50],

        // ★Task432：文件夹导入次按钮位于主按钮下方（header 容器底缘由它收口）
        [self.importFolderButton.topAnchor constraintEqualToAnchor:self.importButton.bottomAnchor constant:10],
        [self.importFolderButton.leadingAnchor constraintEqualToAnchor:self.headerContainerView.leadingAnchor],
        [self.importFolderButton.trailingAnchor constraintEqualToAnchor:self.headerContainerView.trailingAnchor],
        [self.importFolderButton.heightAnchor constraintEqualToConstant:44],
        [self.importFolderButton.bottomAnchor constraintEqualToAnchor:self.headerContainerView.bottomAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.headerContainerView.bottomAnchor constant:12],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

#pragma mark - 轻量加载 HUD（解析/删除等本地短操作）

- (void)showLoadingHUD:(NSString *)title {
    [self hideLoadingHUD];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    overlay.userInteractionEnabled = YES;
    [self.view addSubview:overlay];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.color = [UIColor whiteColor];
    spinner.hidesWhenStopped = NO;
    [spinner startAnimating];
    [overlay addSubview:spinner];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [spinner.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor constant:-24],

        [label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:12],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.widthAnchor constraintLessThanOrEqualToConstant:260]
    ]];

    self.loadingOverlay = overlay;
    self.loadingSpinner = spinner;
    self.loadingLabel = label;
}

- (void)hideLoadingHUD {
    if (self.loadingOverlay) {
        [self.loadingSpinner stopAnimating];
        [self.loadingOverlay removeFromSuperview];
        self.loadingOverlay = nil;
        self.loadingSpinner = nil;
        self.loadingLabel = nil;
    }
}

- (void)loadImportedModpacks {
    NSArray *modpacks = [self.importService getImportedModpacks];
    [self.importedModpacks removeAllObjects];
    [self.importedModpacks addObjectsFromArray:modpacks];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.emptyLabel.hidden = self.importedModpacks.count > 0;
        [self.tableView reloadData];
    });
}

#pragma mark - 文件选择

- (void)selectModpackFile {
    // ★Task432：上一轮文件夹导入打包的 zip 等价流清理（tmp 内 ame432_folder_*；
    //   与 Task169 同口径：清理只发生在下一次选择的入口，正在进行的导入用的是
    //   解析副本/正在读取的包——既有串行约定内不作强同步）。
    [self ame432_cleanupFolderPackZips];
    NSArray<UTType *> *contentTypes = @[
        [UTType typeWithFilenameExtension:@"mrpack"],
        [UTType typeWithFilenameExtension:@"zip"]
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

/// ★Task432（P2 MMC 文件夹导入缺口）：目录选择器入口（UTTypeFolder + asCopy——
/// 选取即拷贝，拿到可直接读取的副本）。MultiMC/Prism 未压缩实例目录经
/// 「实例根定位 → 打平为 zip 等价流」后走既有解析/预览/导入链。
- (void)selectModpackFolder {
    [self ame432_cleanupFolderPackZips];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]
                                                                   asCopy:YES];
    if (!picker) {
        NSLog(@"[ModpackImport][Task432] folder picker unavailable (alloc/init returned nil)");
        return;
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

/// ★Task432：清理历史文件夹打包产物（tmp/ame432_folder_*.zip；新打包前执行）
- (void)ame432_cleanupFolderPackZips {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tmp = NSTemporaryDirectory();
        for (NSString *name in [fm contentsOfDirectoryAtPath:tmp error:nil]) {
            if ([name hasPrefix:@"ame432_folder_"]) {
                [fm removeItemAtPath:[tmp stringByAppendingPathComponent:name] error:nil];
            }
        }
    } @catch (NSException *e) {
        // 清理失败不影响本次导入（tmp 由系统择机回收）
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSURL *fileURL = urls.firstObject;

    // ★Task432（P2 MMC 文件夹导入缺口）：目录选择分流——UTTypeFolder asCopy
    //   返回目录 URL（无扩展名）；探测实例根后打包为 zip 等价流复用既有链。
    BOOL ame432_isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&ame432_isDir];
    if (ame432_isDir) {
        [self ame432_handlePickedDirectory:fileURL];
        return;
    }

    NSString *fileExtension = fileURL.pathExtension.lowercaseString;
    if (![fileExtension isEqualToString:@"mrpack"] && ![fileExtension isEqualToString:@"zip"]) {
        [self showAlertWithTitle:localize(@"i18n_str_569", nil) message:localize(@"i18n_str_570", nil)];
        return;
    }

    [self ame432_parseAndPreviewModpackAtURL:fileURL needsSecurityScope:YES];
}

/// ★Task432：解析 + 预览主流程（原 documentPicker 内联块提取——zip/mrpack 与
/// 目录打包等价流共用同一入口）。needsSecurityScope=NO 用于沙盒内临时副本
/// （startAccessingSecurityScopedResource 对沙盒内文件返回 NO，旧判定会误报
/// 571/572 错误弹窗；沙盒内文件本就无需作用域——Task169 病历同源结论）。
- (void)ame432_parseAndPreviewModpackAtURL:(NSURL *)fileURL needsSecurityScope:(BOOL)needsSecurityScope {
    if (needsSecurityScope) {
        BOOL accessGranted = [fileURL startAccessingSecurityScopedResource];
        if (!accessGranted) {
            [self showAlertWithTitle:localize(@"i18n_str_571", nil) message:localize(@"i18n_str_572", nil)];
            return;
        }
    }

    // 解析阶段：轻量 HUD（本地 zip 读取，通常 < 1s）
    [self showLoadingHUD:localize(@"i18n_str_255", nil)];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *modpackInfo = nil;

        // Task169：安全作用域存活期间先把文件拷贝进应用沙盒 tmp，之后
        // 解析/预览/安装全程只用本地副本。病历（装机 485b18c，"本地整合包
        // 要导入到应用文件之后再导入才能正常安装"）：文件选择器给出的
        // URL 是安全作用域资源，旧代码解析一完就 stopAccessing，而安装
        // 阶段（importModpack:）还会按 info[@"filePath"] 重新读取整个
        // 压缩包——从"文件"App/下载/iCloud 选的包这时已无权访问，只有
        // 先拷进应用沙盒（"我的 iPhone"）的包才碰巧可用。拷贝同时会把
        // iCloud 占位文件实体化。失败则原路径回退（沙盒内文件本就不需要
        // 作用域，行为不变）。
        // ★Task432：沙盒内副本（目录打包等价流）无需实体化拷贝，直接以
        //   原路径解析/安装（needsSecurityScope=NO 路径），避免大目录双倍
        //   tmp 占用；该 zip 在导入完成后由 ame432_cleanupFolderPackZips 清理。
        NSURL *parseURL = fileURL;
        if (needsSecurityScope) {
            @try {
                NSFileManager *fm = [NSFileManager defaultManager];
                [self ame169_cleanupStaleImportCopies];
                unsigned long long ame169_ms = (unsigned long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
                NSString *localCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"ame169_modpack_%llu.%@",
                     ame169_ms,
                     fileURL.pathExtension ?: @"zip"]];
                NSError *copyError = nil;
                if (![fm copyItemAtPath:fileURL.path toPath:localCopy error:&copyError]) {
                    NSLog(@"[ModpackImport] Task169 scoped copy failed (%@), falling back to original path: %@",
                          copyError.localizedDescription, fileURL.lastPathComponent);
                } else {
                    parseURL = [NSURL fileURLWithPath:localCopy];
                    NSLog(@"[ModpackImport] Task169 scoped copy OK: %@ -> %@ (%.1f MB)",
                          fileURL.lastPathComponent, localCopy,
                          (double)[[fm attributesOfItemAtPath:localCopy error:nil] fileSize] / 1048576.0);
                }
            } @catch (NSException *copyException) {
                NSLog(@"[ModpackImport] Task169 scoped copy threw (%@), falling back to original path", copyException.reason);
            }
        }

        @try {
            // ★Task428（工作项一 2.2）：格式探测前置层——先按特征文件探测：
            //   新格式（Technic modpack.cfg / FTB webmanifest.json）经 ModpackConfiguration
            //   归一到中间表示后走既有安装链；既有格式（Modrinth/CurseForge/MultiMC/
            //   PlainZip/MCBBS）仍交服务层解析；服务层解析失败时换成明确报错文案
            //   （不再笼统「无效整合包」）。
            ModpackFormatKind ame428_kind = [ModpackConfiguration ame428_probeFormatAtURL:parseURL];
            if (ame428_kind == ModpackFormatKindTechnic || ame428_kind == ModpackFormatKindFTB) {
                modpackInfo = [ModpackConfiguration ame428_modpackInfoForURL:parseURL kind:ame428_kind error:&error];
            } else {
                modpackInfo = [self.importService parseModpackAtURL:parseURL error:&error];
                if (!modpackInfo) {
                    error = [ModpackConfiguration ame428_unrecognizedFormatError:error];
                }
            }
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"ModpackImportError" code:9999
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_573", nil), exception.reason]}];
        }

        if (needsSecurityScope) {
            [fileURL stopAccessingSecurityScopedResource];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !modpackInfo) {
                [self hideLoadingHUD];
                [self showAlertWithTitle:localize(@"i18n_str_206", nil) message:error.localizedDescription ?: localize(@"i18n_str_574", nil)];
                return;
            }
            self.currentImportingModpack = modpackInfo;
            [self hideLoadingHUD];
            [self showModpackPreview:modpackInfo fileURL:parseURL];
        });
    });
}

#pragma mark - ★Task432 目录式整合包导入（MultiMC/Prism 未压缩实例目录）

/// ★Task432（P2 MMC 文件夹导入缺口）：目录选择结果处理——持锁打包为 zip 等价流
/// 后交既有解析/预览链（needsSecurityScope=NO：产物在沙盒 tmp，无需作用域）。
- (void)ame432_handlePickedDirectory:(NSURL *)dirURL {
    BOOL accessGranted = [dirURL startAccessingSecurityScopedResource];
    if (!accessGranted) {
        // asCopy 副本/沙盒内目录可能无作用域可取——仅留痕不阻断（读取无需授权）
        NSLog(@"[ModpackImport][Task432] folder pick without security scope (asCopy/sandbox-local), continue: %@",
              dirURL.lastPathComponent);
    }
    [self showLoadingHUD:localize(@"ame432.import.folder.packing", @"正在打包文件夹…")];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSURL *zipURL = nil;
        @try {
            NSString *root = [self ame432_locateInstanceRootInDirectory:dirURL.path];
            if (!root) {
                error = [NSError errorWithDomain:@"ModpackImportError" code:1030
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                   localize(@"ame432.import.folder.unrecognized",
                                                            @"所选文件夹不是 MultiMC/Prism 整合包实例（未找到 mmc-pack.json / instance.cfg）")}];
            } else {
                zipURL = [self ame432_packDirectoryToZip:root error:&error];
            }
        } @catch (NSException *ame432_exc) {
            error = [NSError errorWithDomain:@"ModpackImportError" code:1031
                                    userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:
                                                   localize(@"ame432.import.folder.failed", @"文件夹打包失败：%@"),
                                                   ame432_exc.reason ?: @""]}];
        }
        if (accessGranted) [dirURL stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingHUD];
            if (error || !zipURL) {
                [self showAlertWithTitle:localize(@"ame432.import.folder.failed.title", @"无法导入文件夹")
                                 message:error.localizedDescription ?: localize(@"ame432.import.folder.failed.plain", @"文件夹打包失败")];
                return;
            }
            // zip 等价流（mmc-pack.json / instance.cfg / .minecraft/ 原样落 zip 根）
            // → 既有探测/解析链自动识别 MultiMC → 预览 → 统一进度页导入。
            [self ame432_parseAndPreviewModpackAtURL:zipURL needsSecurityScope:NO];
        });
    });
}

/// ★Task432：MultiMC 实例根定位——所选目录自身含 mmc-pack.json / instance.cfg
/// 即实例根；否则向下扫一层找含标志文件的子目录（用户误选 instances/ 父目录的
/// 常见形态）。找不到返回 nil（明确报错，不猜）。
- (nullable NSString *)ame432_locateInstanceRootInDirectory:(NSString *)dirPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isRoot = [fm fileExistsAtPath:[dirPath stringByAppendingPathComponent:@"mmc-pack.json"]] ||
                  [fm fileExistsAtPath:[dirPath stringByAppendingPathComponent:@"instance.cfg"]];
    if (isRoot) return dirPath;
    NSString *packHit = nil;
    NSString *cfgHit = nil;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dirPath error:nil]) {
        NSString *sub = [dirPath stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        [fm fileExistsAtPath:sub isDirectory:&isDir];
        if (!isDir) continue;
        if (!packHit && [fm fileExistsAtPath:[sub stringByAppendingPathComponent:@"mmc-pack.json"]]) packHit = sub;
        if (!cfgHit && [fm fileExistsAtPath:[sub stringByAppendingPathComponent:@"instance.cfg"]]) cfgHit = sub;
    }
    return packHit ?: cfgHit;
}

/// ★Task432：实例根目录 → zip 等价流（沙盒 tmp）。zip 文件名带实例目录名——
/// 服务层 parseMMCPack 在缺 instance.cfg name 键时按包文件名回退取名。
- (nullable NSURL *)ame432_packDirectoryToZip:(NSString *)rootPath error:(NSError **)error {
    // 目录名净化为安全文件名段（保留原实例名供服务层取名回退）
    NSMutableString *safe = [[[rootPath.lastPathComponent ?: @"instance"
        componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]
        componentsJoinedByString:@"_"] mutableCopy];
    if (safe.length == 0) [safe setString:@"instance"];
    NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ame432_folder_%@_%lld.zip",
         safe, (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)]];

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:error];
    if (!archive) return nil;
    BOOL ok = [self ame432_zipTreeAt:rootPath prefix:@"" archive:archive error:error];
    archive = nil;   // UZKArchive 按次开关落盘；置 nil 确保写柄释放
    if (!ok) {
        [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];
        return nil;
    }
    unsigned long long ame432_size =
        (unsigned long long)[[NSFileManager defaultManager] attributesOfItemAtPath:zipPath error:nil].fileSize;
    NSLog(@"[ModpackImport][Task432] folder packed to zip: %@ (%.1f MB)",
          zipPath.lastPathComponent, (double)ame432_size / 1048576.0);
    return [NSURL fileURLWithPath:zipPath];
}

/// ★Task432：目录树递归写入 zip（prefix = 目录在 zip 内的相对路径，根为 @""）。
/// 噪声剔除口径与探测层一致（.DS_Store / __MACOSX）；注意不跳 .minecraft 等
/// 点前缀目录（MultiMC 实例的 .minecraft/ 就是本体内容）。空目录不产生 zip
/// 条目（MMC 安装链按文件条目建目录，无空目录依赖）。
- (BOOL)ame432_zipTreeAt:(NSString *)dirPath
                  prefix:(NSString *)prefix
                 archive:(UZKArchive *)archive
                   error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:dirPath error:error];
    if (!entries) return NO;
    for (NSString *name in entries) {
        if ([name isEqualToString:@".DS_Store"] || [name isEqualToString:@"__MACOSX"]) continue;
        @autoreleasepool {
            NSString *full = [dirPath stringByAppendingPathComponent:name];
            NSString *zipEntry = prefix.length > 0
                ? [NSString stringWithFormat:@"%@/%@", prefix, name]
                : name;
            BOOL isDir = NO;
            [fm fileExistsAtPath:full isDirectory:&isDir];
            if (isDir) {
                if (![self ame432_zipTreeAt:full prefix:zipEntry archive:archive error:error]) return NO;
            } else {
                NSData *data = [NSData dataWithContentsOfFile:full
                                                      options:NSDataReadingMappedIfSafe
                                                        error:error];
                if (!data) return NO;
                if (![archive writeData:data filePath:zipEntry error:error]) return NO;
            }
        }
    }
    return YES;
}

/// Task169：清理上一轮遗留的沙盒拷贝（tmp 里的 ame169_modpack_*）。
/// 拷贝在导入成功后不再需要；预览/安装正在进行的文件不会被误删
/// （导入流程串行，清理只发生在下一次选择的入口）。
- (void)ame169_cleanupStaleImportCopies {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tmp = NSTemporaryDirectory();
        for (NSString *name in [fm contentsOfDirectoryAtPath:tmp error:nil]) {
            if ([name hasPrefix:@"ame169_modpack_"]) {
                [fm removeItemAtPath:[tmp stringByAppendingPathComponent:name] error:nil];
            }
        }
    } @catch (NSException *e) {
        // 清理失败不影响导入（tmp 由系统择机回收）
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

#pragma mark - 整合包预览卡片（参照 FCL ModpackPreviewSheet / HMCL ModpackInfoPage）

- (void)showModpackPreview:(NSDictionary *)modpackInfo fileURL:(NSURL *)fileURL {
    NSString *name = modpackInfo[@"name"] ?: localize(@"i18n_str_121", nil);
    NSString *version = modpackInfo[@"version"] ?: localize(@"i18n_str_121", nil);
    NSString *author = modpackInfo[@"author"] ?: @"";
    NSString *mcVersion = modpackInfo[@"minecraftVersion"] ?: localize(@"i18n_str_121", nil);
    NSString *loader = modpackInfo[@"loader"] ?: @"Vanilla";
    NSString *loaderVersion = modpackInfo[@"loaderVersion"] ?: @"";
    NSString *format = modpackInfo[@"format"] ?: @"unknown";
    NSNumber *modCountNum = modpackInfo[@"modCount"];
    NSNumber *fileCountNum = modpackInfo[@"fileCount"];
    NSString *fileName = fileURL.lastPathComponent ?: @"";

    // 格式映射成中文（★Task428：technic/ftb 新格式；ame428_displayFormat 优先于安装链内部 format 键）
    NSDictionary *formatLabels = @{
        @"modrinth": @"Modrinth (.mrpack)",
        @"curseforge": @"CurseForge (.zip)",
        @"mcbbs": localize(@"i18n_str_575", nil),
        @"mmc": @"MMC (MultiMC/Prism)",
        @"plainzip": @"Plain ZIP (.minecraft)",
        @"technic": @"Technic",
        @"ftb": @"FTB"
    };
    NSString *ame428_displayFormat = modpackInfo[@"ame428_displayFormat"];
    NSString *ame428_formatKey = ([ame428_displayFormat isKindOfClass:[NSString class]] && ame428_displayFormat.length > 0)
        ? ame428_displayFormat : format;
    NSString *formatLabel = formatLabels[ame428_formatKey] ?: ame428_formatKey;

    NSMutableString *message = [NSMutableString string];
    [message appendFormat:localize(@"i18n_str_576", nil), fileName];
    [message appendFormat:localize(@"i18n_str_577", nil), formatLabel];
    [message appendFormat:localize(@"i18n_str_578", nil), name];
    [message appendFormat:localize(@"i18n_str_579", nil), version];
    if (author.length > 0) {
        [message appendFormat:localize(@"i18n_str_2056", nil), author];
    }
    [message appendString:@"\n"];
    [message appendFormat:@"Minecraft: %@\n", mcVersion];
    [message appendFormat:localize(@"i18n_str_581", nil), loader];
    if (loaderVersion.length > 0) {
        [message appendFormat:@" %@", loaderVersion];
    }
    [message appendString:@"\n\n"];

    // ★Task428：Technic 本地加载器降级提示（bin/modpack.jar 无法在 iOS 端自动执行）
    if ([modpackInfo[@"ame428_localLoaderJar"] boolValue]) {
        [message appendString:localize(@"ame428.import.technic.loaderhint", nil)];
        [message appendString:@"\n\n"];
    }

    if (modCountNum && modCountNum.integerValue > 0) {
        [message appendFormat:localize(@"i18n_str_582", nil), (long)modCountNum.integerValue];
    }
    if (fileCountNum && fileCountNum.integerValue > 0) {
        [message appendFormat:localize(@"i18n_str_583", nil), (long)fileCountNum.integerValue];
    }

    // Forge/NeoForge 警告
    if ([loader isEqualToString:@"Forge"] || [loader isEqualToString:@"NeoForge"]) {
        [message appendFormat:localize(@"i18n_str_584", nil), loader, loaderVersion];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_585", nil)
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self.currentImportingModpack = nil;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_156", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self startModpackImport:modpackInfo];
    }]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 导入流程

- (void)startModpackImport:(NSDictionary *)modpackInfo {
    // 重置取消状态
    [self.importService resetCancelState];

    // Task 5.1：不再显示自定义进度卡——importModpack 内部注册 DownloadTaskManager
    // 主任务（autoPresentDetail=YES），统一进度页自动弹出并接管全部进度展示；
    // 取消统一经由进度页"取消"按钮 → manager 置 Cancelled → service 轮询感知。
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSError *error = nil;
        __block BOOL success = NO;

        @try {
            success = [self.importService importModpack:modpackInfo
                                               progress:^(double progress, NSString *stageMessage) {
                // 进度细节已由 service 上报到统一进度页（阶段/文件计数/字节），
                // 此回调仅保留日志用途，驱动旧自定义进度卡的主线程刷新已移除。
                NSLog(@"[ModpackImport] progress %.0f%%: %@", progress * 100, stageMessage);
            } error:&error];
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"ModpackImportError" code:9998
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_586", nil), exception.reason]}];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // 检测是否被取消
            BOOL wasCancelled = [error.domain isEqualToString:@"ModpackImportError"] && error.code == 9999;
            NSString *localizedDesc = error.localizedDescription ?: @"";
            if (!wasCancelled && [localizedDesc containsString:localize(@"resman.common.cancel", nil)]) {
                wasCancelled = YES;
            }

            if (wasCancelled) {
                self.currentImportingModpack = nil;
                [self showAlertWithTitle:localize(@"i18n_str_127", nil) message:localize(@"i18n_str_525", nil)];
                return;
            }

            if (success) {
                self.currentImportingModpack = nil;
                // 关键修复（Task 72，"找不到版本信息"根因）：本地 .mrpack 导入成功后
                // 同样未发送 ReloadProfileList——localVersionList 快照不含刚写入的唯一化
                // 版本，用户点"立即启动"回到主界面按启动会弹"找不到版本信息"。
                // 与 DownloadViewController 在线整合包路径 / 直装路径（issue #61）对齐。
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
                NSLog(@"[ModpackImport] Task72 ReloadProfileList posted after local modpack import");
                [self showImportSuccess:modpackInfo];
            } else {
                // 阶段5修复（参照 FCL）：错误消息中追加失败文件列表（如有），
                // 让用户清楚知道是哪些 mod 下载失败，而不是只看到一个笼统的错误。
                NSString *message = error.localizedDescription ?: localize(@"i18n_str_97", nil);
                NSArray<NSDictionary *> *failed = self.importService.failedFiles;
                if (failed.count > 0) {
                    NSMutableString *msg = [NSMutableString stringWithString:message];
                    [msg appendFormat:localize(@"i18n_str_587", nil), (unsigned long)failed.count];
                    NSUInteger showCount = MIN(failed.count, (NSUInteger)5);
                    for (NSUInteger k = 0; k < showCount; k++) {
                        NSString *n = failed[k][@"fileName"] ?: failed[k][@"name"];
                        [msg appendFormat:@"\n  • %@", n ?: @"(unknown)"];
                    }
                    if (failed.count > showCount) {
                        [msg appendFormat:localize(@"i18n_str_450", nil), (unsigned long)failed.count];
                    }
                    message = [msg copy];
                }
                self.currentImportingModpack = nil;
                [self showAlertWithTitle:localize(@"i18n_str_263", nil) message:message];
            }
        });
    });
}

- (void)showImportSuccess:(NSDictionary *)modpackInfo {
    NSString *loader = modpackInfo[@"loader"];
    NSString *name = modpackInfo[@"name"];
    NSMutableString *msg = [NSMutableString stringWithFormat:localize(@"i18n_str_588", nil), name];
    if ([loader isEqualToString:@"Forge"] || [loader isEqualToString:@"NeoForge"]) {
        [msg appendFormat:localize(@"i18n_str_589", nil), loader, modpackInfo[@"loaderVersion"]];
    }

    // Task 5.2：成功结果中明确列出被跳过的文件（404/server-only 等），
    // 让用户知晓整合包可能不完整（此前仅在控制台日志可见）。
    NSArray<NSDictionary *> *skipped = [self.importService skippedDownloadFiles];
    if (skipped.count > 0) {
        [msg appendFormat:localize(@"i18n_str_590", nil), (unsigned long)skipped.count];
        NSUInteger showCount = MIN(skipped.count, (NSUInteger)5);
        for (NSUInteger k = 0; k < showCount; k++) {
            NSString *n = skipped[k][@"fileName"] ?: @"(unknown)";
            [msg appendFormat:@"\n  • %@", n];
        }
        if (skipped.count > showCount) {
            [msg appendFormat:localize(@"i18n_str_450", nil), (unsigned long)skipped.count];
        }
    }
    NSString *finalMsg = [msg copy];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_591", nil)
                                                                   message:finalMsg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_141", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self loadImportedModpacks];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_592", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self loadImportedModpacks];
        [self launchModpack:modpackInfo];
    }]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.importedModpacks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModpackCell" forIndexPath:indexPath];
    // 重置 cell 样式
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    // 重置 cell 样式：移除旧的 blurView 和 shadowView（cell 复用）
    for (UIView *subview in cell.contentView.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] ||
            (subview.layer.shadowOpacity > 0.0f)) {
            [subview removeFromSuperview];
        }
    }

    NSDictionary *modpack = self.importedModpacks[indexPath.row];
    NSString *name = modpack[@"name"] ?: localize(@"i18n_str_121", nil);
    NSString *mcVersion = modpack[@"minecraftVersion"] ?: localize(@"i18n_str_121", nil);
    NSString *loader = modpack[@"loader"] ?: localize(@"i18n_str_121", nil);

    cell.textLabel.text = name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Minecraft %@ - %@", mcVersion, loader];
    cell.imageView.image = [UIImage systemImageNamed:@"archivebox"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.backgroundColor = [UIColor clearColor];

    // 阶段6视觉统一：参照 ModernAssetCell / ModVersionTableViewCell / VersionCardCell 的卡片规范
    // （cornerRadius 12 + cornerCurve continuous + shadow offset 2/opacity 0.10/radius 4 + leading/trailing 10）
    // 由于 UIVisualEffectView 的 masksToBounds=YES 会同时裁剪 blur 和 shadow，需要单独的 shadowView
    // 提供阴影（与 blurView 同 frame），blurView 在上层提供毛玻璃效果。
    UIView *shadowView = [[UIView alloc] init];
    shadowView.translatesAutoresizingMaskIntoConstraints = NO;
    shadowView.layer.cornerRadius = 12;
    shadowView.layer.cornerCurve = kCACornerCurveContinuous;
    shadowView.layer.shadowColor = [UIColor blackColor].CGColor;
    shadowView.layer.shadowOffset = CGSizeMake(0, 2);
    shadowView.layer.shadowOpacity = 0.10;
    shadowView.layer.shadowRadius = 4;
    shadowView.layer.backgroundColor = [[AmeTheme surfaceCard] colorWithAlphaComponent:0.08].CGColor;
    [cell.contentView insertSubview:shadowView atIndex:0];

    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.layer.cornerRadius = 12;
    blurView.layer.cornerCurve = kCACornerCurveContinuous;
    blurView.layer.masksToBounds = YES;
    [cell.contentView insertSubview:blurView atIndex:1];
    [NSLayoutConstraint activateConstraints:@[
        [shadowView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [shadowView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:10],
        [shadowView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10],
        [shadowView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
        [blurView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [blurView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:10],
        [blurView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10],
        [blurView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4]
    ]];
    cell.backgroundView = nil;
    return cell;
}

#pragma mark - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *modpack = self.importedModpacks[indexPath.row];
    [self showModpackOptions:modpack];
}

- (void)showModpackOptions:(NSDictionary *)modpack {
    // ★ Task240：换装系统原生 UIMenu（旧 actionSheet 退役）。
    [AmeNativeMenu ame240_presentMenuWithTitle:modpack[@"name"]
                                     dictItems:@[
        @{ @"title": localize(@"i18n_str_593", nil), @"handler": ^{
            [self launchModpack:modpack];
        } },
        @{ @"title": localize(@"i18n_str_306", nil), @"destructive": @YES, @"handler": ^{
            [self deleteModpack:modpack];
        } },
    ] sourceView:self.view];
}

- (void)launchModpack:(NSDictionary *)modpack {
    NSString *profileName = modpack[@"profileName"];
    if (profileName && PLProfiles.current.profiles[profileName]) {
        PLProfiles.current.selectedProfileName = profileName;
        [self showAlertWithTitle:localize(@"i18n_str_594", nil) message:[NSString stringWithFormat:localize(@"i18n_str_595", nil), profileName]];
    } else {
        [self showAlertWithTitle:localize(@"i18n_str_42", nil) message:localize(@"i18n_str_596", nil)];
    }
}

- (void)deleteModpack:(NSDictionary *)modpack {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_457", nil) message:[NSString stringWithFormat:localize(@"i18n_str_597", nil), modpack[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self showLoadingHUD:localize(@"i18n_str_598", nil)];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            BOOL success = [self.importService deleteModpack:modpack error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideLoadingHUD];
                if (success) {
                    [self loadImportedModpacks];
                } else {
                    [self showAlertWithTitle:localize(@"i18n_str_458", nil) message:error.localizedDescription];
                }
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - 辅助方法

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [self showAlertWithTitle:title message:message completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message completion:(void (^ _Nullable)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion();
    }]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 重新应用透明化，确保背景效果切换后视图仍能透出全局背景
        [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
        [[BackgroundManager sharedManager] applyEffectToView:self.view];
        [self.tableView reloadData];
    });
}

@end
