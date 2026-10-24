#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#import "customcontrols/CustomControlsUtils.h"
#import "HostManagerBridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
#import "config.h"
#import "FileLayoutService.h"  // Task316：文件层桌面/安卓同构（共享核心/实例扁平化/跨启动器导入）

#include <libgen.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include "utils.h"
#include "codesign.h"

// Task 43：shaderc 编译 fork server（实现于 Natives/shaderc_sandbox.m，
// CMake 同时编进本可执行文件）。在 init_redirectStdio 之后调用——见
// main() 内注释。
int ame_sb_fork_server_early(void);

#define CS_PLATFORM_BINARY 0x4000000
#define PT_TRACE_ME 0
#define PT_DETACH 11 
int ptrace(int, pid_t, caddr_t, int);
#define fm NSFileManager.defaultManager
extern char** environ;

void printEntitlementAvailability(NSString *key) {
    NSLog(@"* %@: %@", key, getEntitlementValue(key) ? @"YES" : @"NO");
}

void uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"Uncaught exception: %@", exception.description);
    NSLog(@"Call stack: %@", exception.callStackSymbols);
    // Task 27：ObjC 未捕获异常也直写 fatal_trace（同 abort/exit 取证通道），
    // 避免 latestlog 管道丢尾导致现场丢失
    NSString *reasonStr = [NSString stringWithFormat:@"NSException: %@ — %@",
        exception.name, exception.reason ?: @"(no reason)"];
    ame_write_fatal_trace(reasonStr.UTF8String);
    usleep(10000);
    handle_fatal_exit(SIGABRT);
}

bool init_checkForsubstrated() {
    // Please kindly tell pwn20wnd that he sucks
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    do {
        size += size / 10;
        newprocess = realloc(process, size);
        if (!newprocess){
            if (process){
                free(process);
            }
            return nil;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    } while (st == -1 && errno == ENOMEM);
    if (st == 0){
        if (size % sizeof(struct kinfo_proc) == 0){
            int nprocess = size / sizeof(struct kinfo_proc);
            if (nprocess){
                for (int i = nprocess - 1; i >= 0; i--){
                    if(strcmp(process[i].kp_proc.p_comm,"substrated") == 0) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

bool init_checkForJailbreak() {
    if (NSProcessInfo.processInfo.macCatalystApp) {
        // macOS doesn't automatically enable JIT.
        return false;
    } else if (init_checkForsubstrated()) {
        return true;
    }

    // Check if posix_spawn is hooked
    for (int i=0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i),"/usr/lib/pspawn_payload-stg2.dylib") == 0 ||
            strstr(_dyld_get_image_name(i),"/systemhook.dylib") != NULL) {
            return true;
        }
    }

    // Check if we have platform bit set
    // ★ Task274-f r2（F5）：flags 清零 + csops 返回值并入条件——原实现未初始化即用（csops 失败时按栈垃圾判定 platform 位）。失败/未置位统一落既有的 /Applications 目录探测兜底。
    uint32_t flags = 0;
    if (csops(0, CS_OPS_STATUS, &flags, sizeof(flags)) == 0 && (flags & CS_PLATFORM_BINARY) != 0) {
        return true;
    }

    return opendir("/Applications") != NULL;
}

void init_logDeviceAndVer(char *argument) {
    // Amethyst version
    // Task223（清单第 23 项“log 里遗留旧名字”）：横幅先报本 fork 身份
    //（Prisma，Task218 改名后的仓库名），上游出处行保持致谢语义不变。
    NSLog(@"[Pre-Init] Prisma Launcher (fork of Amethyst iOS Remastered) INIT!");
    NSLog(@"[Pre-Init] Fork: https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher");
    NSLog(@"[Pre-Init] Upstream: https://github.com/herbrine8403/Amethyst-iOS-MyRemastered");
    NSLog(@"[Pre-Init] Please try not to post this log of the remastered launcher to the original GitHub Issues for help.");
    NSLog(@"[Pre-Init] Version: %@ (%s)", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], CONFIG_TYPE);
    NSLog(@"[Pre-Init] Commit: %s (%s)", CONFIG_COMMIT, CONFIG_BRANCH);
    
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    const char *type;
    if (!access(tsPath.UTF8String, F_OK)) {
        type = "TrollStore";
    } else if (isJailbroken) {
        type = "Jailbroken";
    } else {
        type = "Unjailbroken";
    }
    setenv("POJAV_DETECTEDINST", type, 1);
    
    NSLog(@"[Pre-Init] Device: %@", [HostManager GetModelName]);
    NSLog(@"[Pre-Init] %@ (%s)", UIDevice.currentDevice.completeOSVersion, type);
    
    NSLog(@"[Pre-init] Entitlements availability:");
    printEntitlementAvailability(@"com.apple.developer.kernel.extended-virtual-addressing");
    printEntitlementAvailability(@"com.apple.developer.kernel.increased-memory-limit");
    printEntitlementAvailability(@"com.apple.private.security.no-sandbox");
    // JIT-relevant entitlements: TrollStore grants jb.pmap_cs.custom_trust
    // (kernel-level JIT without a debugger), which isJITEnabled() fast-paths
    // on. dynamic-codesigning is the per-app JIT entitlement (iOS 18+).
    // Logging them here settles "did the launcher even see my JIT entitlement"
    // questions from latestlog alone.
    printEntitlementAvailability(@"jb.pmap_cs.custom_trust");
    printEntitlementAvailability(@"dynamic-codesigning");
}

void init_redirectStdio() {
    if (getenv("LOG_TO_CONSOLE") != NULL) {
        NSLog(@"[Pre-init] LOG_TO_CONSOLE is set, not logging to latestlog.txt");
        return;
    }

    NSLog(@"[Pre-init] Starting logging STDIO to latestlog.txt\n");

    NSString *home = @(getenv("POJAV_HOME"));
    NSString *currName = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSString *oldName = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    // Task 171：异常死亡证据保全（多人游戏偶发崩溃的日志总被轮换吃掉）。
    // 病历：用户报"多人游戏有时候会崩溃，参考上一个提交的 log.old.txt"，
    // 但该文件是干净的 26.3 多人会话（mysv.dpdns.org，60fps，干净
    // exit(0)）——崩溃会话的 latestlog 在下一次启动的"先删后移"轮换里
    // 只能存活一代，用户再玩一局就永远丢了（本会话日志即被覆盖）。
    // 保全员：轮换前读旧 latestlog.txt 尾部 8KB，若没有 hooked_exit 的
    // "exit(N) called" 终止标记（正常退出/退出码非零都会留痕；原生
    // SIGSEGV/SIGKILL 类死亡无标记），把它复制为 latestlog.crash.txt
    // （只保留最近一份，不参与轮换链）。下次崩溃后从应用容器直接取回
    // 完整现场。
    {
        NSString *crashName = [home stringByAppendingPathComponent:@"latestlog.crash.txt"];
        if ([fm fileExistsAtPath:currName]) {
            NSData *tail = nil;
            NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:currName];
            if (h) {
                unsigned long long len = [h seekToEndOfFile];
                unsigned long long off = (len > 8192) ? (len - 8192) : 0;
                [h seekToFileOffset:off];
                tail = [h readDataToEndOfFile];
                [h closeFile];
            }
            BOOL hasExitMarker = NO;
            if (tail) {
                NSString *tailStr = [[NSString alloc] initWithData:tail
                                                           encoding:NSUTF8StringEncoding];
                hasExitMarker = (tailStr != nil) && [tailStr containsString:@") called"];
            }
            if (!hasExitMarker) {
                NSError *cpErr = nil;
                [fm removeItemAtPath:crashName error:nil];
                if ([fm copyItemAtPath:currName toPath:crashName error:&cpErr]) {
                    NSLog(@"[Pre-init] Task171: previous session died without an exit marker -- log preserved to latestlog.crash.txt (unclean-death forensics)");
                } else {
                    NSLog(@"[Pre-init] Task171: crash-log preservation failed: %@", cpErr.localizedDescription);
                }
            }
        }
    }
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];

    if (!file) {
        NSLog(@"[Pre-init] Error: failed to open %@", currName);
        assert(0 && "Failed to open latestlog.txt. Check oslog for more details.");
    }

    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered

    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    // ★ Task275（P3-a11）：pipe() 失败不再静默——原失败后 dup2(-1) 使整条日志链
    //   瘫痪且无任何痕迹。
    if (pipe(pfd) != 0) {
        NSLog(@"[Pre-init] pipe() failed (errno=%d) -- stdout/stderr stay console-only", errno);
    } else {
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));
    }

    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static BOOL filteredSessionID;
        ssize_t rsize;
        char buf[2048];
        // Task 27 加固：
        // ① read() EINTR 重试 —— 信号中断曾可能让读取线程意外退出，
        //    此后全部日志丢失（latestlog 冻结在退出点）。
        // ② 每次迭代包 @try —— 单次异常不再杀死整个读取循环。
        // ③ Session ID 审查改为定界 splice（见内注释），不再丢 chunk 尾数据。
        while (YES) {
            do {
                rsize = read(pfd[0], buf, sizeof(buf)-1);
            } while (rsize < 0 && errno == EINTR);
            if (rsize <= 0) break;
            // ★ Task275（P1-a1）：每次迭代包 @autoreleasepool——原无限循环体跑在 GCD
            //   为单个 block 建的唯一 pool 里，每条日志 chunk 的临时 ObjC 对象
            //   （NSString/NSArray/NSData/userInfo 字典）全进程生命周期单调堆积永不
            //   drain，MC 加载期日志速率高，长会话可泄漏数百 MB（Task 2-a 遗留）。
            @autoreleasepool {
            @try {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            // Filter out Session ID here
            // Task 27 修复：旧实现 strcpy(censor) 后 rsize=strlen(buf)，
            // ① chunk 内审查点之后的既有数据全部丢掉（写文件长度被截短）；
            // ② 匹配落在 chunk 末尾时会越界写入陈旧缓冲区。
            // 改为定界 splice：仅当结束符 ')' 在本 chunk 内才替换，尾部数据
            // 整体前移，rsize 只缩短实际长度差；ID 跨 chunk 则留待下一块。
            if (!filteredSessionID) {
                static const char kCensor[] = "(Session ID is <censored>)";
                char *sessionStr = strstr(buf, "(Session ID is ");
                if (sessionStr) {
                    ptrdiff_t off = sessionStr - buf;
                    const char *closeParen = memchr(sessionStr, ')', (size_t)(rsize - off));
                    if (closeParen) {
                        size_t idLen = (size_t)(closeParen - sessionStr) + 1;
                        size_t censorLen = sizeof(kCensor) - 1;
                        size_t tailLen = (size_t)rsize - (size_t)off - idLen;
                        if (censorLen != idLen) {
                            memmove(sessionStr + censorLen, closeParen + 1, tailLen);
                        }
                        memcpy(sessionStr, kCensor, censorLen);
                        rsize = (ssize_t)((size_t)off + censorLen + tailLen);
                        filteredSessionID = true;
                    }
                }
            }
            if (canAppendToLog) {
                // canAppendToLog=YES 时，通过 appendToLog: 同时更新 UI 表格和发送通知
                [PLLogOutputView appendToLog:@(buf)];
            } else {
                // canAppendToLog=NO 时（默认状态，用户未打开日志面板），
                // PLLogOutputView 不会更新 UI，但 LanPortDetector 仍需要实时检测
                // MC "对局域网开放"端口。直接在后台线程发送通知，
                // LanPortDetector 的处理是线程安全的（processLogLine: 是无状态的，
                // setPort:source: 内部 dispatch_async 到主线程）。
                //
                // 关键修复：之前 canAppendToLog=NO 时完全不发送通知，
                // 导致 LanPortDetector 无法实时检测端口，用户先"对局域网开放"
                // 再点"当房主"时无法生成分享代码。
                NSString *logString = @(buf);
                NSArray *lines = [logString componentsSeparatedByCharactersInSet:
                    [NSCharacterSet newlineCharacterSet]];
                for (NSString *line in lines) {
                    if (line.length > 0) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"PLLogOutputLineNotification"
                                                                            object:nil
                                                                          userInfo:@{@"line": line}];
                    }
                }
            }
            [file writeData:[NSData dataWithBytes:buf length:rsize]];
            // ★ Task275（效率·fsync 风暴）：原每 ≤2KB chunk 一次 synchronizeFile（逐块
            //   fsync 级刷盘），JVM 启动/shaderc 编译风暴期每秒数百次同步 I/O。改 8s
            //   节流（closeFile 前补一次终刷，不丢尾）。
            {
                static CFAbsoluteTime ame275_lastSync = 0;
                CFAbsoluteTime ame275_now = CFAbsoluteTimeGetCurrent();
                if (ame275_now - ame275_lastSync > 8.0) {
                    [file synchronizeFile];
                    ame275_lastSync = ame275_now;
                }
            }
            } @catch (NSException *e) {
                // 读取线程绝不能因单次异常死亡：死亡 = 后续日志全部丢失（Task 26 教训）
                NSLog(@"[Pre-init] latestlog reader exception: %@", e);
            }
            }
        }
        [file synchronizeFile];
        [file closeFile];
    });

    // We can start catching exception right now
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
}

void init_setupAccounts() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"accounts"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
}

// Task92：预启动主动导出 UniversalJIT26.js 到 $POJAV_HOME（Documents）。
// 背景：StikDebug 侧的 JIT26 脚本必须与本启动器的 brk 协议严格配套
// （legacy 0x69 = x0 大小/返回地址，Universal + Extension 才是完整实现）。
// 此前 Documents 副本只在「检测到 legacy 脚本」的启动失败路径里补拷，
// 用户得先失败一次才能在 StikDebug 的 Assign Script 里选到文件。改为
// 每次启动导出（内容一致则跳过写盘），旧版 StikDebug（无按应用名自动
// 分配 universal.js）也能提前手动指派正确脚本，避免协议不配。
void init_exportJIT26Script(void) {
    NSString *inBundle = [NSBundle.mainBundle pathForResource:@"UniversalJIT26" ofType:@"js"];
    if (!inBundle) {
        NSLog(@"[Pre-init] UniversalJIT26.js missing from bundle — skip export");
        return;
    }
    NSString *dst = [NSString stringWithFormat:@"%s/UniversalJIT26.js", getenv("POJAV_HOME")];
    NSData *bundleData = [NSData dataWithContentsOfFile:inBundle];
    NSData *existing = [NSData dataWithContentsOfFile:dst];
    if (bundleData && [bundleData isEqualToData:existing]) {
        return; // 副本已与 IPA 内置版本一致，避免无谓写盘
    }
    if ([fm createFileAtPath:dst contents:bundleData attributes:nil]) {
        NSLog(@"[Pre-init] Exported Universal JIT script to Documents (StikDebug Assign-Script ready)");
    } else {
        NSLog(@"[Pre-init] Failed to export Universal JIT script to %@", dst);
    }
}

void init_setupCustomControls() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"controlmap"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControl();
    generateAndSaveCustomControl();
    NSString *gamepadControlPath = [controlPath stringByAppendingPathComponent:@"gamepads"];
    [fm createDirectoryAtPath:gamepadControlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControlForGamepad();

    // ★ Task230（反馈 #3：持续奔跑没有效果）：存量布局死按钮迁移。装机日志
    //   （39633e4 latestlog.old:5667-5671）实锤用户布局里的"常用\n操作键"
    //   keycodes 全零（Task229 UNBOUND 诊断触发，用户按它期待奔跑却毫无
    //   反应）。出货布局已改为绑定 Left Control 341（sprint 键；配合已开启
    //   的 toggleSprint 即"持续奔跑"），但 generateAndSaveCustomControl 只在
    //   文件缺失时拷贝——存量安装拿不到新 bundle。此处对已安装的
    //   custom.json / classic.json / large-buttons.json 做同款修补：仅当
    //   按钮名含"常用"、四个键码全零时改为 341（用户自绑过的永不动）。
    //   Task231 修复（装机“打开闪退”根因，684915a 实测 latestlog 停在
    //   Task226 symlink 行）：(a) 递归 block 必须 __block——非 __block 自动
    //   变量在字面量求值时按值快照，此刻 ame230_walk 尚未赋值（ARC 零初始
    //   化为 nil），block 捕获 nil 后首次递归调用读 nil->invoke =
    //   EXC_BAD_ACCESS（硬件异常，@try 接不住）→ 无痕 SIGKILL 形态闪退；
    //   顶层 dict 必有 keys，首次递归必触发，每次启动必崩。
    //   (b) 解析必须 MutableContainers——options:0 返回不可变
    //   __NSDictionaryI，setValue:forKey: 抛 NSInvalidArgumentException
    //   被 @catch 吞掉，迁移永远失效（③白修）。
    //   反铒：Task232（反馈 #4 复发轮）：仅扫三个固定文件名不够——装机
    //   4bdd916 会话零 "sprint dead-button migrated" 锚点，用户布局是自建
    //   文件名（控件编辑器保存的任意名字）；且死按钮名含"持续 奔跑"
    //   不含"常用"。本轮改为扫描 controlmap 下【全部 .json】（排除 gamepads
    //   子目录），名字含"常用"或"奔跑"且四键码全零 → 绑 341（Left
    //   Control；配合 toggleSprint 即点一次持续奔跑）。用户自绑过（任一
    //   键码非零）的按钮永不动。
    @try {
        NSArray<NSString *> *ame230_all = [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:controlPath error:nil] ?: @[];
        NSMutableArray<NSString *> *ame230_files = [NSMutableArray array];
        for (NSString *ame230_fn in ame230_all) {
            if ([ame230_fn.pathExtension caseInsensitiveCompare:@"json"] != NSOrderedSame) continue;
            // 游戏手柄布局子目录里的文件不扫（形态不同，不迁移）
            NSString *ame230_full = [controlPath stringByAppendingPathComponent:ame230_fn];
            BOOL ame230_isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:ame230_full isDirectory:&ame230_isDir] && ame230_isDir) continue;
            [ame230_files addObject:ame230_fn];
        }
        for (NSString *ame230_fn in ame230_files) {
            NSString *ame230_p = [controlPath stringByAppendingPathComponent:ame230_fn];
            NSData *ame230_data = [NSData dataWithContentsOfFile:ame230_p];
            if (ame230_data == nil) continue;
            id ame230_obj = [NSJSONSerialization JSONObjectWithData:ame230_data
                                                            options:NSJSONReadingMutableContainers
                                                              error:nil];
            if (![ame230_obj isKindOfClass:[NSDictionary class]]) continue;
            __block BOOL ame230_changed = NO;
            __block void (^ame230_walk)(id) = ^(id node) {
                if ([node isKindOfClass:[NSDictionary class]]) {
                    // ★ Task247（T1 非SDL开常用操作键无法左右键 根修）：抽屉本体
                    //   保护。Task230 的全量 walk 把"常用\n操作键"抽屉本体的
                    //   [0,0,0,0] 误改绑 341（当时不知道这是抽屉开关按钮；Task233
                    //   实锤全零 = 抽屉本体合法形态）——用户每点一次抽屉 =
                    //   Task179 轻点锁定把 Ctrl 钉住，游戏内左/右键与疾跑行为随
                    //   抽屉开合漂移。本轮两件事：
                    //   ① 已污染布局修复：抽屉本体名字命中"常用/奔跑"且键码恰
                    //     为迁移产物 [341,0,0,0] → 复位全零（写回文件）；
                    //   ② 迁移规则收紧：抽屉容器（含 buttonProperties 的节点）
                    //     的 properties 子节点永不改绑；旧"全零→341"迁移仅对
                    //     非抽屉节点继续生效（用户自绑过的永不动）。
                    if ([node objectForKey:@"buttonProperties"] != nil) {
                        id ame230_body = [node objectForKey:@"properties"];
                        NSString *ame230_bodyName = [ame230_body isKindOfClass:[NSDictionary class]]
                            ? [ame230_body objectForKey:@"name"] : nil;
                        NSArray *ame230_bodyKc = [ame230_body isKindOfClass:[NSDictionary class]]
                            ? [ame230_body objectForKey:@"keycodes"] : nil;
                        if ([ame230_bodyName isKindOfClass:[NSString class]] &&
                            ([ame230_bodyName containsString:@"常用"] || [ame230_bodyName containsString:@"奔跑"]) &&
                            [ame230_bodyKc isKindOfClass:[NSArray class]] && ame230_bodyKc.count == 4 &&
                            [ame230_bodyKc[0] intValue] == 341 &&
                            [ame230_bodyKc[1] intValue] == 0 &&
                            [ame230_bodyKc[2] intValue] == 0 &&
                            [ame230_bodyKc[3] intValue] == 0) {
                            [ame230_body setValue:@[@0, @0, @0, @0] forKey:@"keycodes"];
                            ame230_changed = YES;
                            NSLog(@"[Pre-init] Task247: drawer-body Ctrl pollution reset (name=%@)", ame230_bodyName);
                        }
                        // 抽屉容器只递归 buttonProperties 子按钮（properties 已在上面处理）
                        NSArray *ame230_subs = [node objectForKey:@"buttonProperties"];
                        if ([ame230_subs isKindOfClass:[NSArray class]]) {
                            for (id ame230_sub in ame230_subs) ame230_walk(ame230_sub);
                        }
                    } else {
                    NSString *ame230_nm = [node objectForKey:@"name"];
                    NSArray *ame230_kc = [node objectForKey:@"keycodes"];
                    if ([ame230_nm isKindOfClass:[NSString class]] &&
                        ([ame230_nm containsString:@"常用"] || [ame230_nm containsString:@"奔跑"]) &&
                        [ame230_kc isKindOfClass:[NSArray class]] && ame230_kc.count >= 1) {
                        BOOL ame230_allZero = YES;
                        for (id k in ame230_kc) {
                            if ([k isKindOfClass:[NSNumber class]] && [k intValue] != 0) { ame230_allZero = NO; break; }
                        }
                        if (ame230_allZero) {
                            NSMutableArray *ame230_new = [ame230_kc mutableCopy];
                            ame230_new[0] = @341;
                            [node setValue:ame230_new forKey:@"keycodes"];
                            ame230_changed = YES;
                        }
                    }
                    for (NSString *ame230_k in [node allKeys]) ame230_walk([node objectForKey:ame230_k]);
                    }
                } else if ([node isKindOfClass:[NSArray class]]) {
                    for (id v in (NSArray *)node) ame230_walk(v);
                }
            };
            ame230_walk(ame230_obj);
            if (ame230_changed) {
                NSData *ame230_out = [NSJSONSerialization dataWithJSONObject:ame230_obj
                                                                    options:NSJSONWritingPrettyPrinted error:nil];
                if (ame230_out != nil && [ame230_out writeToFile:ame230_p options:NSDataWritingAtomic error:nil]) {
                    NSLog(@"[Pre-init] Task230: sprint dead-button migrated to Left Control 341 in %@", ame230_fn);
                }
            }
        }
    } @catch (NSException *ame230_e) {
        NSLog(@"[Pre-init] Task230: layout migration exception (%@)", ame230_e);
    }
}

void init_setupMultiDir() {
    NSString *multidir = getPrefObject(@"general.game_directory");
    if (multidir.length == 0) {
        multidir = @"default";
        setPrefObject(@"general.game_directory", multidir);
        NSLog(@"[Pre-init] Game directory was not set. Defaulting to %@ for future use.\n", multidir);
    } else {
        NSLog(@"[Pre-init] Restored game directory preference (%@)\n", multidir);
    }

    const char *home = getenv("POJAV_HOME");
    NSString *lasmPath = [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", home];
    NSString *multidirPath = [NSString stringWithFormat:@"%s/instances/%@", home, multidir];


    NSArray *dirsToCreate = @[
        [NSString stringWithFormat:@"%s/.demo", home],
        [NSString stringWithFormat:@"%s/java_runtimes", home],
        lasmPath.stringByDeletingLastPathComponent,
        multidirPath
    ];
    for (NSString *dir in dirsToCreate) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    // ★ Task316（文件层桌面/安卓同构）：一次性布局迁移——共享核心去重
    // （instances/*/{versions,libraries,assets} → shared_core 符号链接回指）
    // + 整合包实例扁平化（custom_gamedir/<id> → 顶层 instances/<id>，
    // profile gameDir 绝对路径锚定）。marker 幂等，先于 ame226 软链块执行。
    [FileLayoutService ame316_migrateIfNeeded];
    // ★ Task226（反馈 #5：上游软件更新到本软件，数据要能正常识别）：
    // 旧代码无条件 removeItemAtPath:lasmPath——若这里是【真实目录】
    //（上游老版本 / 更新前残留的游戏数据：saves/mods/config 等全在里面），
    // 整目录被永久删除 = 用户数据无声蒸发。改为三态：
    //   ① 已是符号链接 → 原样保留（幂等重指也不做，目标一致性由下面保证）；
    //   ② 真实目录且有内容 → 先把内容【迁移】进 instances/<multidir>
    //     （仅补缺失条目、绝不覆盖；PCL VER-ISOLATE 哲学：只挪不删），
    //     迁移完成后才把原目录改名归档（.lasm-legacy-backup）再建链接；
    //   ③ 空目录 → 删除建链接（旧行为）。
    // 迁移清单与隔离向导（ProfileSettings ame217_items）同口径：游戏读写
    // 的用户数据，排除共享层（assets/libraries/versions 由安装器管理）。
    BOOL ame226_isSymlink = NO;
    NSDictionary *lasmAttrs = [fm attributesOfItemAtPath:lasmPath error:nil];
    if (lasmAttrs && [lasmAttrs fileType] == NSFileTypeSymbolicLink) {
        ame226_isSymlink = YES;
    }
    if (!ame226_isSymlink && lasmAttrs) {
        // 真实目录：数内容判空
        NSArray *lasmEntries = [fm contentsOfDirectoryAtPath:lasmPath error:nil];
        NSUInteger ame226_legacyCount = lasmEntries.count;
        if (ame226_legacyCount > 0) {
            NSLog(@"[Pre-init] Task226 legacy real game dir detected at %@ (%lu entries) -- migrating into instances/%@ (no data loss)", lasmPath, (unsigned long)ame226_legacyCount, multidir);
            NSArray *ame226_items = @[
                @"saves", @"mods", @"config", @"resourcepacks", @"shaderpacks",
                @"options.txt", @"servers.dat", @"servers.dat_old", @"usercache.json",
                @"screenshots", @"crash-reports", @"logs", @"hotbar.nbt",
                @"options~", @"realms_persistence.json"
            ];
            NSUInteger ame226_moved = 0;
            for (NSString *ame226_item in ame226_items) {
                NSString *src = [lasmPath stringByAppendingPathComponent:ame226_item];
                if (![fm fileExistsAtPath:src]) continue;
                NSString *dst = [multidirPath stringByAppendingPathComponent:ame226_item];
                if ([fm fileExistsAtPath:dst]) continue;  // 目标已有 → 绝不覆盖
                if ([fm moveItemAtPath:src toPath:dst error:nil]) {
                    ame226_moved++;
                }
            }
            // 剩余未识别条目也一并搬走（上游可能带插件数据等）；versions/
            // assets/libraries 等共享层保留原位（链接后经 instances 访问）。
            for (NSString *ame226_left in [fm contentsOfDirectoryAtPath:lasmPath error:nil]) {
                NSString *src = [lasmPath stringByAppendingPathComponent:ame226_left];
                NSString *dst = [multidirPath stringByAppendingPathComponent:ame226_left];
                if ([fm fileExistsAtPath:dst]) continue;
                [fm moveItemAtPath:src toPath:dst error:nil];
            }
            NSLog(@"[Pre-init] Task226 legacy migration done: %lu tracked + leftovers moved (watched-items=%lu)", (unsigned long)ame226_moved, (unsigned long)ame226_items.count);
            // 归档空壳（保名不保数据；万一还有残留条目则保留为备份目录）
            NSString *ame226_archive = [lasmPath stringByAppendingString:@"-lasm-legacy-backup"];
            [fm removeItemAtPath:ame226_archive error:nil];
            if (![fm moveItemAtPath:lasmPath toPath:ame226_archive error:nil]) {
                [fm removeItemAtPath:lasmPath error:nil];
            }
        } else {
            [fm removeItemAtPath:lasmPath error:nil];
        }
    }
    // 符号链接：重指到当前 multidir（实例切换后老链接可能指向旧实例）
    if (ame226_isSymlink) {
        NSString *curTarget = [fm destinationOfSymbolicLinkAtPath:lasmPath error:nil];
        BOOL sameTarget = NO;
        if (curTarget.length > 0) {
            NSString *resolvedCur = [[lasmPath.stringByDeletingLastPathComponent
                stringByAppendingPathComponent:curTarget]
                stringByResolvingSymlinksInPath];
            sameTarget = [resolvedCur isEqualToString:multidirPath.stringByResolvingSymlinksInPath];
        }
        if (!sameTarget) {
            [fm removeItemAtPath:lasmPath error:nil];
            [fm createSymbolicLinkAtPath:lasmPath withDestinationPath:multidirPath error:nil];
            NSLog(@"[Pre-init] Task226 game-dir symlink re-pointed to instances/%@", multidir);
        }
    } else {
        [fm removeItemAtPath:lasmPath error:nil];
        [fm createSymbolicLinkAtPath:lasmPath withDestinationPath:multidirPath error:nil];
    }
    // ★ Task318 → Task319/320 升级：原「minecraft 可见别名折中」（单条链接）已
    //   升级为完整 PCL 风格顶层布局三件套 —— .minecraft（游戏目录，桌面生态
    //   语义）+ Prisma2/（启动器数据：plugins/AI；Task319 曾定名 PCL，Task320
    //   用户拍板改名 Prisma2）+ minecraft（「文件」App 可见别名，iOS 隐藏点前缀
    //   的兜底），全部移交 init_setupPCLLayout() 统一管理（见下）。保留纪律：
    //   数据导出链对符号链接跳过（DataTransferService skip symlink），不会双份
    //   打包；Java 侧全走 POJAV_GAME_DIR 环境变量，零感知。
    [fm changeCurrentDirectoryPath:lasmPath];
    setenv("POJAV_GAME_DIR", lasmPath.UTF8String, 1);
}

// ★ Task319/320（PCL 风格文件布局）：Plain Craft Launcher 顶层观感 = 启动器本体
//   + <启动器数据目录> + .minecraft/（游戏目录）。iOS 侧映射：
//   · .minecraft → Task226 游戏目录链（随实例切换自动跟随，桌面工具链语义：
//     saves/mods/options.txt/resourcepacks 一眼可见；导出/整合包链本就写
//     .minecraft 前缀，命名对齐后内外一致）；
//   · minecraft → 可见别名（「文件」App 隐藏点前缀目录，Task318 折中保留），
//     重指 .minecraft 形成 minecraft → .minecraft → instances/<现役> 链；
//   · Prisma2/ → 启动器数据目录（Task319 曾定名 PCL，Task320 用户拍板改名
//     Prisma2）：plugins（Task317 插件系统根）+ AI（会话/待办/版本缓存）。
//     providers.json【绝不进 Prisma2/】——Task275 安全纪律（含 apiKey 的文件
//     不落「文件」App 可读层），继续住 Application Support/AI。
//   迁移纪律：真实目录整体 move 幂等（新位置已存在即跳过）；plugins 旧位留
//   符号链接防外部引用断链（改名后悬空自动重指）；providers.json 先摘后迁，
//   摘不动则整轮不迁（宁可保旧布局，不让密钥落可读层）；任何失败只打日志
//   不阻塞启动。
void init_setupPCLLayout() {
    NSString *home = @(getenv("POJAV_HOME") ?: "");
    if (home.length == 0) return;
    // ★ Task320（用户拍板「把 pcl 改成 Prisma2」）：启动器数据目录定名 Prisma2/
    //   （Task319 短暂窗口期曾名 PCL/）。
    NSString *prismaDir = [home stringByAppendingPathComponent:@"Prisma2"];
    NSString *legacyAIDir = [home stringByAppendingPathComponent:@"AI"];

    // —— 0) Task319 窗口期设备改名迁移：PCL/ → Prisma2/（真实目录整体 move
    //        幂等；Prisma2 已存在则不动 PCL 留查证——绝不覆盖用户数据）
    NSString *legacyPCL = [home stringByAppendingPathComponent:@"PCL"];
    if (![fm fileExistsAtPath:prismaDir]) {
        NSDictionary *pcAttrs = [fm attributesOfItemAtPath:legacyPCL error:nil];
        if (pcAttrs && [pcAttrs fileType] == NSFileTypeDirectory) {
            NSError *ame320_rErr = nil;
            if ([fm moveItemAtPath:legacyPCL toPath:prismaDir error:&ame320_rErr]) {
                NSLog(@"[Pre-init] Task320: PCL/ renamed to Prisma2/ (Task319 window-device migration)");
            } else {
                NSLog(@"[Pre-init] Task320: PCL->Prisma2 rename failed (%@) -- keeps Task319 layout this launch", ame320_rErr.localizedDescription);
            }
        }
    }
    // Task319 窗口期 plugins 旧位符号链接随改名悬空（→ $HOME/PCL/plugins 已
    //   整体搬走）→ 重指 Prisma2/plugins 延续防断链保险；真实目录/文件不动。
    {
        NSString *legacyPluginsLink = [home stringByAppendingPathComponent:@"plugins"];
        NSDictionary *lpAttrs = [fm attributesOfItemAtPath:legacyPluginsLink error:nil];
        if (lpAttrs && [lpAttrs fileType] == NSFileTypeSymbolicLink) {
            NSString *lpResolved = [legacyPluginsLink.stringByDeletingLastPathComponent
                stringByAppendingPathComponent:([fm destinationOfSymbolicLinkAtPath:legacyPluginsLink error:nil] ?: @"")];
            if (![fm fileExistsAtPath:lpResolved]) {
                [fm removeItemAtPath:legacyPluginsLink error:nil];
                [fm createSymbolicLinkAtPath:legacyPluginsLink
                          withDestinationPath:[prismaDir stringByAppendingPathComponent:@"plugins"] error:nil];
                NSLog(@"[Pre-init] Task320: dangling plugins symlink re-pointed to Prisma2/plugins");
            }
        }
    }

    // —— 1) providers.json 安全前摘（老设备 Task275 迁移未跑完就遇整体搬迁
    //        的竞态堵口）：Documents/AI/providers.json → Application Support/AI/
    NSString *legacyProviders = [legacyAIDir stringByAppendingPathComponent:@"providers.json"];
    if ([fm fileExistsAtPath:legacyProviders]) {
        NSString *asBase = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                NSUserDomainMask, YES) firstObject] ?: home;
        NSString *asAI = [asBase stringByAppendingPathComponent:@"AI"];
        [fm createDirectoryAtPath:asAI withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *modern = [asAI stringByAppendingPathComponent:@"providers.json"];
        if (![fm fileExistsAtPath:modern]) {
            NSError *ame319_pErr = nil;
            if ([fm moveItemAtPath:legacyProviders toPath:modern error:&ame319_pErr]) {
                NSLog(@"[Pre-init] Task319: providers.json routed to Application Support before Prisma2 migration (Task275 hardening kept)");
            } else {
                NSLog(@"[Pre-init] Task319: providers.json move failed (%@) -- AI dir NOT migrated this launch (apiKey never lands in file-sharing-visible Prisma2/)", ame319_pErr.localizedDescription);
                return; // 密钥文件未摘出：宁可整轮不迁
            }
        } else {
            [fm removeItemAtPath:legacyProviders error:nil]; // 外露副本清除（Task275 同语义）
        }
    }

    // —— 2) Prisma2/ 建目录
    [fm createDirectoryAtPath:prismaDir withIntermediateDirectories:YES attributes:nil error:nil];

    // —— 3) plugins → Prisma2/plugins（真实目录整体 move，旧位留符号链接防断链）
    NSString *legacyPlugins = [home stringByAppendingPathComponent:@"plugins"];
    NSString *prismaPlugins = [prismaDir stringByAppendingPathComponent:@"plugins"];
    if (![fm fileExistsAtPath:prismaPlugins]) {
        NSDictionary *pAttrs = [fm attributesOfItemAtPath:legacyPlugins error:nil];
        if (pAttrs && [pAttrs fileType] == NSFileTypeDirectory) {
            NSError *ame319_plErr = nil;
            if ([fm moveItemAtPath:legacyPlugins toPath:prismaPlugins error:&ame319_plErr]) {
                [fm createSymbolicLinkAtPath:legacyPlugins withDestinationPath:prismaPlugins error:nil];
                NSLog(@"[Pre-init] Task319: plugins/ migrated into Prisma2/plugins (legacy symlink left in place)");
            } else {
                NSLog(@"[Pre-init] Task319: plugins migration failed (%@) -- keeps legacy layout this launch", ame319_plErr.localizedDescription);
            }
        }
    }

    // —— 4) AI → Prisma2/AI（真实目录整体 move；App 内路径已全量切 Prisma2/AI，旧位不留链接）
    NSString *prismaAI = [prismaDir stringByAppendingPathComponent:@"AI"];
    if (![fm fileExistsAtPath:prismaAI]) {
        NSDictionary *aAttrs = [fm attributesOfItemAtPath:legacyAIDir error:nil];
        if (aAttrs && [aAttrs fileType] == NSFileTypeDirectory) {
            NSError *ame319_aiErr = nil;
            if ([fm moveItemAtPath:legacyAIDir toPath:prismaAI error:&ame319_aiErr]) {
                NSLog(@"[Pre-init] Task319: AI/ migrated into Prisma2/AI (sessions/todos/version cache)");
            } else {
                NSLog(@"[Pre-init] Task319: AI migration failed (%@) -- keeps legacy layout this launch", ame319_aiErr.localizedDescription);
            }
        }
    }

    // —— 5) .minecraft 顶层符号链接 → Task226 游戏目录链（三态保护：
    //        ① 符号链接 → 幂等重指；② 真实目录/文件（用户自建）→ 不动不删；
    //        ③ 缺失 → 创建）
    NSString *lasmPath = [NSString stringWithFormat:@"%s/Library/Application Support/minecraft",
                          getenv("POJAV_HOME") ?: ""];
    NSString *dotMC = [home stringByAppendingPathComponent:@".minecraft"];
    NSDictionary *dAttrs = [fm attributesOfItemAtPath:dotMC error:nil];
    if (dAttrs) {
        if ([dAttrs fileType] == NSFileTypeSymbolicLink) {
            NSString *cur = [fm destinationOfSymbolicLinkAtPath:dotMC error:nil] ?: @"";
            NSString *resolvedCur = cur.length
                ? [[dotMC.stringByDeletingLastPathComponent stringByAppendingPathComponent:cur]
                   stringByResolvingSymlinksInPath] : @"";
            if (![resolvedCur isEqualToString:lasmPath.stringByResolvingSymlinksInPath]) {
                [fm removeItemAtPath:dotMC error:nil];
                [fm createSymbolicLinkAtPath:dotMC withDestinationPath:lasmPath error:nil];
                NSLog(@"[Pre-init] Task319: .minecraft re-pointed to game dir");
            }
        }
        // 真实目录/文件：绝不覆盖用户数据
    } else {
        [fm createSymbolicLinkAtPath:dotMC withDestinationPath:lasmPath error:nil];
        NSLog(@"[Pre-init] Task319: .minecraft created -> game dir (PCL desktop semantics)");
    }

    // —— 6) minecraft 可见别名 → .minecraft（iOS「文件」App 隐藏点前缀的可见
    //        兜底；.minecraft 因用户真实目录保护未能接管时回退指游戏目录链）
    NSString *aliasLink = [home stringByAppendingPathComponent:@"minecraft"];
    NSDictionary *aliasAttrs = [fm attributesOfItemAtPath:aliasLink error:nil];
    if (aliasAttrs && [aliasAttrs fileType] != NSFileTypeSymbolicLink) return; // 用户自建：不动
    BOOL dotMCUsable = dAttrs && [dAttrs fileType] == NSFileTypeSymbolicLink;
    NSString *wantTarget = dotMCUsable ? @".minecraft" : lasmPath;
    NSString *curAlias = aliasAttrs
        ? ([fm destinationOfSymbolicLinkAtPath:aliasLink error:nil] ?: @"") : @"";
    if (![curAlias isEqualToString:wantTarget]) {
        if (aliasAttrs) [fm removeItemAtPath:aliasLink error:nil];
        [fm createSymbolicLinkAtPath:aliasLink withDestinationPath:wantTarget error:nil];
        NSLog(@"[Pre-init] Task319: minecraft alias -> %@ (Files-app visible entry)", wantTarget);
    }
}

void init_setupResolvConf() {
    // Write known DNS servers to the config
    NSString *path = [NSString stringWithFormat:@"%s/resolv.conf", getenv("POJAV_HOME")];
    if (![fm fileExistsAtPath:path]) {
        [@"nameserver 8.8.8.8\n"
         @"nameserver 8.8.4.4"
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void init_setupHomeDirectory() {
    setenv("HOME", [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path.stringByDeletingLastPathComponent.UTF8String, 1);
    NSString *homeDir;
    NSError *homeError;
    
    BOOL isNotSandboxed = [@(getenv("HOME")).lastPathComponent isEqualToString:NSUserName()];
    homeDir = [NSString stringWithFormat:@"%s/Documents%@", getenv("HOME"),
        isNotSandboxed ? @"/AngelAuraAmethyst":@""];

    if (![fm fileExistsAtPath:homeDir] ) {
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:NO attributes:nil error:&homeError];
    }
    
    if(homeError != nil) {
        // TODO: Persistent storage
        homeError = nil;
        homeDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&homeError];
    }
    
    setenv("POJAV_HOME", realpath(homeDir.UTF8String, NULL), 1);
}

int main(int argc, char *argv[]) {
    // ★ Task301：内置 JIT 自重拉起子进程分支（第三轨）。必须在【一切】初始化
    // 之前分支——含 shaderc 沙箱分支。装机 2c6458a latestlog 实锤：LC guest 内
    // posix_spawn appex 内嵌二进制被 AMFI 拒（errno=2），而主二进制自身 exec
    // 必合法（它正在跑）。协调器 posix_spawn 本体 + env PRISMA_JIT_HELPER_CHILD=1
    // + PRISMA_JIT_COORDINATOR_DYLIB；此处 dlopen 协调器 dylib，调
    // @_cdecl("prisma_jit_direct_main") 入口（StikJIT.enableJIT 全链：RSD 探测
    // → DDI 下载/挂载 → debugserver vAttach 父 PID → universal 脚本协议），
    // 返回码即进程退出码。dlopen/dlsym 失败也必须原子写回 RESULT_FILE（协调器
    // 轮询以文件存在+内容为准），否则宿主只能等 600s 超时。
    if (getenv("PRISMA_JIT_HELPER_CHILD") != NULL) {
        const char *ame301_dylibPath = getenv("PRISMA_JIT_COORDINATOR_DYLIB");
        const char *ame301_resultPath = getenv("PRISMA_JIT_RESULT_FILE");
        const char *ame301_failMsg = NULL;
        void *ame301_h = NULL;
        int ame301_rc = 3;
        if (ame301_dylibPath == NULL) {
            ame301_failMsg = "PRISMA_JIT_COORDINATOR_DYLIB missing in child env";
        } else {
            ame301_h = dlopen(ame301_dylibPath, RTLD_NOW | RTLD_LOCAL);
            if (ame301_h == NULL) {
                NSLog(@"[JIT] Task301 child dlopen(%s) failed: %s", ame301_dylibPath, dlerror());
                ame301_failMsg = "coordinator dylib dlopen failed in self-relaunch child";
            }
        }
        if (ame301_h != NULL) {
            typedef int (*ame301_entry_t)(void);
            ame301_entry_t ame301_entry = (ame301_entry_t)dlsym(ame301_h, "prisma_jit_direct_main");
            if (ame301_entry != NULL) {
                ame301_rc = ame301_entry();
                _exit(ame301_rc);
            }
            NSLog(@"[JIT] Task301 child dlsym(prisma_jit_direct_main) failed: %s", dlerror());
            ame301_failMsg = "prisma_jit_direct_main symbol missing in coordinator dylib";
        }
        if (ame301_resultPath != NULL && ame301_failMsg != NULL) {
            NSString *payload = [NSString stringWithFormat:@"0\t[self-relaunch] %s", ame301_failMsg];
            [payload writeToFile:@(ame301_resultPath) atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        _exit(3);
    }

    // Task 42：shaderc 编译沙箱 helper 子进程分支。必须在【一切】launcher/JVM/
    // hook 初始化之前分支（pJLI_Launch、ptrace JIT 分支都在其后）。父进程的
    // shaderc shim 通过 posix_spawn 以 AME_SHADERC_SANDBOX=1 + AME_SB_FD=3
    // 拉起本进程；此路径只有 dlopen(libshaderc_impl) + 32MB 栈编译循环，
    // 不触碰 UIKit/JavaLauncher/偏好设置。EOF（父退出）即干净返回。
    if (getenv("AME_SHADERC_SANDBOX") != NULL) {
        extern int ame_shaderc_sandbox_child_main(void);
        return ame_shaderc_sandbox_child_main();
    }

    if (pJLI_Launch) {
        return pJLI_Launch(argc, (const char **)argv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
    }

    if (!isJITEnabled(true) && argc == 2) {
        NSLog(@"calling ptrace(PT_TRACE_ME)");
        // Child process can call to PT_TRACE_ME
        // then both parent and child processes get CS_DEBUGGED
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    setenv("BUNDLE_PATH", dirname(argv[0]), 1);
    isJailbroken = init_checkForJailbreak();
    init_setupHomeDirectory();
    init_redirectStdio();
    // Task 43：在此 fork shaderc 编译服务器（不 exec）。位置选择的三个理由：
    //   1) stderr 已接 latestlog 管道——子进程取证（sb_clog raw write）直接
    //      经管道落 latestlog.txt（父进程的日志读取线程活着，跨进程收走）；
    //   2) 进程此刻只有主线程 + 日志读取线程（read() 阻塞中，不持 malloc/
    //      stdio/dyld 锁）——子进程可安全 dlopen impl + malloc；
    //   3) JVM/JIT/hook/ANGLE 均未诞生——进程内堆踩踏的“外部写入者”在子
    //      进程地址空间里从未运行，编译环境天然纯净。
    // 失败（沙盒禁 fork 等）只打日志，launcher 照常继续（shim 自动降级）。
    ame_sb_fork_server_early();
    init_logDeviceAndVer(argv[0]);

    loadPreferences(NO);
    init_hookFunctions();
    init_hookUIKitConstructor();

    debugLogEnabled = getPrefBool(@"general.debug_logging");
    NSLog(@"[Debugging] Debug log enabled: %@", debugLogEnabled ? @"YES" : @"NO");

    init_setupResolvConf();
    init_setupMultiDir();
    init_setupPCLLayout(); // Task319/320：PCL 风格顶层布局（.minecraft + Prisma2/ 数据目录）+ 数据迁移
    toggleIsolatedPref(NO);
    // Task 167：MobileGlues DSA 黑屏反向迁移的【常跑】调用点。原挂载点
    // application:configurationForConnectingSceneSession: 只在新建场景会话时
    // 触发（既有会话设备永不再调——60+ 份历史上传日志零出现该回调内日志，
    // Task166 迁移因此在装机设备上从未执行，DSA 存量 1 压制新默认，
    // GLES/4.0 黑屏修复失效）。本点位于 toggleIsolatedPref 之后（读到的是
    // 生效存储）、任何偏好消费者（JavaLauncher/设置页）之前；哨兵保证
    // 幂等，与 AppDelegate 的保留调用点互为冗余。装机锚点：
    // "[Preferences] Task167 MG DSA black-screen migration ran (stored=1, flipped=1)"。
    ame130_migrateMgPerfDefaults();
    // Task211：CF 源迁 Modrinth + 垃圾 Key 清理（同位置的幂等一次性迁移；
    // 装机锚点 "[Preferences] Task211: ..."，详见 LauncherPreferences.h）
    ame211_migrateCfSourceToModrinth();
    // Task212：holy gl4es 退役——存量渲染器值迁移到 ZL2 经典版（须在
    // updateCurrent 之前，profile 解析拿到的即迁移后的值）。
    ame212_migrateHolyGl4es();
    [PLProfiles updateCurrent];
    init_setupAccounts();
    init_setupCustomControls();
    init_exportJIT26Script();

    // If sandbox is disabled, W^X JIT can be enabled by Amethyst itself
    if (!isJITEnabled(true) && getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        NSLog(@"[Pre-init] no-sandbox: YES, trying to enable JIT");
        int pid;
        int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
        if (ret == 0) {
            // Cleanup child process
            waitpid(pid, NULL, WUNTRACED);
            ptrace(PT_DETACH, pid, NULL, 0);
            kill(pid, SIGTERM);
            wait(NULL);

            if (isJITEnabled(true)) {
                NSLog(@"[Pre-init] JIT has been enabled with PT_TRACE_ME");
            } else {
                NSLog(@"[Pre-init] Failed to enable JIT: unknown reason");
            }
        } else {
            NSLog(@"[Pre-init] Failed to enable JIT: posix_spawn() failed errno %d", errno);
        }
    }

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
