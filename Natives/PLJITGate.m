//
// PLJITGate.m — 启动续链 JIT 门禁共享助手（Task323）
// 状态机 1:1 移植自 LauncherRightPanelViewController invokeAfterJITEnabled:
// （L1765-2251）+ ame185/ame169/ame172 三助手；差异仅为：
//   ① RightPanel 私有 UI（progressLabel/updateJITStatus）改为 onStage 回调
//   ② 弃启路径（task=nil/恢复交互/ReloadProfileList）改为 onAbandon 回调
//   ③ 弹窗宿主/popover 锚点改为入参 hostVC
//   ④ Task226 静默自动重拉标记改为进程级 static（单启动链语义等价）
//   ⑤ 日志标签 [RightPanel] → [Gate]
// Task134/169/172/176/181/182/185/223/226/267/281/294/295 病历修复全量保留。
//

#import "PLJITGate.h"
#import "utils.h"                    // isJITEnabled/getPref*/getEntitlementValue/
                                     // ame169_waitForJITCondition/ame185_dispatchToMainSelfHealing/
                                     // ame302_isLiveContainerGuest/ame322_stikjitBundleId/
                                     // JIT26*/DeviceHasJITFlags/CS_DEBUGGED
#import "ios_uikit_bridge.h"         // showDialog
#import "AmeNativeMenu.h"            // ame281_presentSystemAlert（Task281 玻璃镜像）
#import "StikDebugViewController.h"  // Task294 内置 JIT 轨
#import "ALTServerConnection.h"      // ALTServerManager stopDiscovering
#import "LauncherPreferences.h"      // getPrefObject/getPrefBool/getEntitlementValue/setPrefString/setPrefInt

// Task226 静默自动重拉标记（旧 RP 为 per-VC ivar；本助手无状态化，启动链
// 进程内单实例语义下 static 等价：第一轮超时静默重拉，第二轮才弹重试框）
static BOOL gPL323JITAutoRetried = NO;

// ★ Task355（一代议题 #20 根修）：门禁单飞（single-flight）护栏。
//   病历（#20 装机 crash.txt）：等待环期间门禁被二次进入（下载完成自动续链
//   与手动启动链并发，或完成回调重入），两套等待环/双“等待 JIT”弹窗/双
//   后台断言并行（心跳日志每 10s 成对出现），JIT 开启后双 handler 二次
//   进 JVM——用户侧表现即 "startgame -> don't loading game" 永久等待，
//   最终只能菜单里 force-close 杀进程（latestlog 终局 exit(0) 实锤）。
//   语义：等待在飞时，后续进入一律视为重复链——留痕后走 onAbandon 恢复
//   启动器交互态，不产生第二套等待。清位时机：主等待完成块与重挂完成块
//   入口处先清位再分支，保证 Task226 自动重拉 / Task169 手动重试的合法
//   再进入不被误拦；快速路径（JIT 已开/跳过等待）不置位。全程主队列访问
//   （入口与完成块均 main），无锁。
static BOOL gPL355GateInFlight = NO;

@implementation PLJITGate

+ (void)invokeAfterJITEnabledWithHandler:(void (^)(void))handler
                                  hostVC:(UIViewController *)hostVC
                               onAbandon:(void (^)(void))onAbandon
                                 onStage:(void (^)(NSString *))onStage {
    // ★ Task355：单飞护栏（见 gPL355GateInFlight 注释）。置位点在下方等待
    //   环入口（快速路径不置位不挡道）；完成块入口先清位再分支。
    if (gPL355GateInFlight) {
        NSLog(@"[JIT] [Gate] Task355: duplicate gate entry while a JIT wait is already in flight -- suppressing and abandoning this chain");
        if (onAbandon) onAbandon();
        return;
    }

    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];

    // ★ Task297-ci（run#914 编译热修）：等待环取消语义双通道的两个 __block 位
    //   必须活在方法作用域（Task295 首版放 else 块内的雷已入档）。
    __block BOOL ame267_cancelled = NO;
    __block BOOL ame267_builtinDialogShowing = NO;

    // Task91：entitlement AND 磁盘标记双确认（防普通侧载包预写标记把流程
    // 导入 apple-magnifier:// 死路）
    BOOL hasTrollStoreJIT = getEntitlementValue(@"jb.pmap_cs.custom_trust") && isTrollStoreInstall();

    // Diagnostic: full JIT state at decision time
    {
        BOOL hasDynamicCS = getEntitlementValue(@"dynamic-codesigning");
        int diagCsFlags = 0;
        csops(getpid(), 0, &diagCsFlags, sizeof(diagCsFlags));
        NSLog(@"[JIT] [Gate] invokeAfterJITEnabled: dynamicCS=%d trollStore=%d CS_DEBUGGED=%d ppid=%d traced=%d exn=%d JIT_FLAGS=0x%X",
              hasDynamicCS, hasTrollStoreJIT, (diagCsFlags & CS_DEBUGGED) != 0, getppid(), JIT26DebuggerAttachedViaPtrace(), JIT26DebuggerViaExceptionPorts(), DeviceGetJITFlags(NO));
    }

    if (isJITEnabled(false)) {
        [ALTServerManager.sharedManager stopDiscovering];
        // iPadOS 26+ TXM devices: CS_DEBUGGED 只证明 JIT 曾开启过——JIT26
        // 调试器平时早已退场（ppid==1, P_TRACED==0, 无任务异常端口）。
        // launchJVM 的 JIT26CreateRegionLegacy brk #0x69 在无活调试器时瞬时
        // 致命，故需要重挂时先走 stikjit:// 再启动。
        // NOTE: 有意不复用 isJITEnabled()——那是持久 CS_DEBUGGED 态，不是
        // 调试器存活性。
        if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) &&
            !JIT26IsLikelyDebuggerKeepAttached() &&
            // Task294：本会话内置轨已完成 universal 祝福（祝福完即脱）无需再附；
            // 仅 stikjit:// 中断式半附加才需重挂。
            ![StikDebugViewController ame294_scriptCompletedThisSession] &&
            !getPrefBool(@"debug.jit26_script_disable")) {
            NSLog(@"[JIT] [Gate] CS_DEBUGGED set but no live JIT26 debugger (ppid=%d traced=%d exn=%d) — re-attaching script via stikjit://",
                  getppid(), JIT26DebuggerAttachedViaPtrace(), JIT26DebuggerViaExceptionPorts());
            [self ame323_reattachJIT26ThenLaunch:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
            return;
        }
        NSLog(@"[JIT] [Gate] JIT enabled with live JIT26 debugger, launching game directly");
        handler();
        return;
    } else if (hasTrollStoreJIT) {
        // ★ Task322：深链 bundle-id 单一口径（LC guest → 宿主 id，非 LC 零变化）
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", ame322_stikjitBundleId()]];
        // Task185：TrollStore 分支回执检查（apple-magnifier:// 无人处理时
        // 完全静默只能盲等 120s 超时——失败即时弹指引）。
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:^(BOOL ame185_ok) {
            NSLog(@"[JIT] [Gate] Task185 openURL apple-magnifier:// -> %d", ame185_ok);
            if (!ame185_ok) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showDialog(localize(@"Error", nil), @"apple-magnifier:// 无响应（TrollStore JIT 助手未接管，常见于 TrollStore 版本过旧）。请更新 TrollStore，或在设置的 JIT 开启工具改用 stikjit / SideStore / StosDebug 后重试。\napple-magnifier:// not handled. Update TrollStore or switch the JIT enabler in Settings.");
                });
            }
        }];
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else {
        // ---- Task 134：JIT 开启工具分发（LiveContainer 多工具方案） ----
        // 按 debug.jit_enabler 偏好分发；auto = 原自动判定（TrollStore 检测
        // → apple-magnifier；iOS>=17.4 → stikjit；16.7-17.3.1 → sidestore）。
        // ★ Task294：选项 builtin（启动器自带）——LC guest 结构性全死自动
        //   降级深链（Task322）；auto 在非巨魔环境内置轨可用时优先。
        NSString *ame134_enabler = getPrefObject(@"debug.jit_enabler");
        if (![ame134_enabler isKindOfClass:NSString.class] || ame134_enabler.length == 0) {
            ame134_enabler = @"auto";
        }
        BOOL ame134_noScript = getPrefBool(@"debug.jit26_script_disable");
        // ★ Task322：深链 bundle-id 单一口径（LC guest → 宿主 id，非 LC 零变化）
        NSString *ame134_bundleId = ame322_stikjitBundleId();
        BOOL ame294_builtinAvail = [StikDebugViewController ame294_builtinTrackAvailable];
        BOOL ame134_isTrollStore = getEntitlementValue(@"jb.pmap_cs.custom_trust") && isTrollStoreInstall();
        BOOL ame294_useBuiltin = NO;
        if ([ame134_enabler isEqualToString:@"builtin"]) {
            // ★ Task322：LC guest 下显式 builtin 同样降级深链（Task302 结构性
            //   全死，显式留守 = 门禁弹窗 + 120s 空等，游戏起不来）
            ame294_useBuiltin = !ame302_isLiveContainerGuest();
            if (!ame294_useBuiltin) {
                NSLog(@"[JIT] [Gate] Task322: explicit builtin under LC guest structurally dead -- degrading to deep link");
            }
        } else if ([ame134_enabler isEqualToString:@"auto"] && !ame134_isTrollStore) {
            ame294_useBuiltin = ame294_builtinAvail;
        }
        NSLog(@"[JIT] [Gate] Task134 enabler=%@ noScript=%d builtin=%d (avail=%d ts=%d)",
              ame134_enabler, ame134_noScript, ame294_useBuiltin, ame294_builtinAvail, ame134_isTrollStore);

        // ★ Task295：等待环取消语义双通道（失败弹窗级联 dismiss 会误触等待框
        //   cancel——builtinDialogShowing 见位即忽略；真取消置 cancelled）。
        void (^ame294_fireStikjitFallback)(void) = ^{
            if (@available(iOS 17.4, *)) {
                NSString *scriptPart = @"";
                if (!ame134_noScript) {
                    NSData *script = [NSData dataWithContentsOfFile:
                        [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
                    if (script) {
                        scriptPart = [@"&script-data=" stringByAppendingString:[script base64EncodedStringWithOptions:0]];
                    }
                }
                NSURL *fallbackURL = [NSURL URLWithString:[NSString stringWithFormat:
                    @"stikjit://enable-jit?bundle-id=%@&pid=%d%@", ame134_bundleId, getpid(), scriptPart]];
                [UIApplication.sharedApplication openURL:fallbackURL options:@{} completionHandler:^(BOOL ok) {
                    NSLog(@"[JIT] [Gate] Task294 fallback openURL stikjit:// -> %d", ok);
                }];
            }
        };
        void (^ame294_builtinFailure)(NSString *) = ^(NSString *failureMessage) {
            NSString *detail = failureMessage.length ? failureMessage
                : localize(@"ame293.jit.builtin_fail_title", nil);
            if ([detail localizedCaseInsensitiveContainsString:@"Timed out connecting"] ||
                [detail localizedCaseInsensitiveContainsString:@"not ready for JIT"]) {
                detail = [detail stringByAppendingFormat:@"\n\n%@", localize(@"ame294.jit.localdevvpn_hint", nil)];
            }
            // ★ Task295：置位必须同步在弹窗 dispatch 之前（Ex 内部才 async）。
            ame267_builtinDialogShowing = YES;
            ame294_showJITActionDialogEx(localize(@"ame293.jit.builtin_fail_title", nil), detail,
                localize(@"ame293.jit.fallback_ok", nil), ame294_fireStikjitFallback,
                ^{ ame267_cancelled = YES; });
        };

        if (ame294_useBuiltin) {
            [StikDebugViewController ame294_enableBuiltinJITWithCompletion:^(BOOL success, NSString *message) {
                if (success || isJITEnabled(YES)) {
                    NSLog(@"[JIT] [Gate] Task294 builtin track OK -- wait loop will proceed");
                    return;
                }
                NSLog(@"[JIT] [Gate] Task294 builtin track failed: %@", message);
                ame294_builtinFailure(message);
            }];
            // 不 return——继续走下方 isJITEnabled 等待环（内置轨成功即启动）
        } else if ([ame134_enabler isEqualToString:@"manual"]) {
            // 手动：不跳任何工具，等用户自己附加调试器（显示等待弹窗）
        } else if ([ame134_enabler isEqualToString:@"trollstore"]
                   || ([ame134_enabler isEqualToString:@"auto"] && ame134_isTrollStore)) {
            [self ame323_openJITEnablerURL:[NSURL URLWithString:
                [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", ame134_bundleId]]
                toolLabel:@"apple-magnifier://"];
        } else if ([ame134_enabler isEqualToString:@"sidestore"]) {
            [self ame323_openJITEnablerURL:[NSURL URLWithString:
                [NSString stringWithFormat:@"sidestore://enable-jit?bundle-id=%@", ame134_bundleId]]
                toolLabel:@"sidestore://"];
        } else if ([ame134_enabler isEqualToString:@"stosdebug"]) {
            NSString *ame134_appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"Amethyst";
            NSMutableString *ame134_url = [NSMutableString stringWithFormat:
                @"stosdebug://enableJIT?bundleId=%@&appName=%@", ame134_bundleId, ame134_appName];
            if (!ame134_noScript) {
                NSData *ame134_script = [NSData dataWithContentsOfFile:
                    [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
                if (ame134_script) {
                    [ame134_url appendFormat:@"&script=%@", [ame134_script base64EncodedStringWithOptions:0]];
                }
            }
            [self ame323_openJITEnablerURL:[NSURL URLWithString:ame134_url] toolLabel:@"stosdebug://"];
        } else if ([ame134_enabler isEqualToString:@"jitstreamer"]) {
            // JitStreamer-EB：默认 WireGuard 本地地址（LiveContainer 同款）
            [self ame323_openJITEnablerURL:[NSURL URLWithString:
                [NSString stringWithFormat:@"http://[fd00::]:9172/launch_app/%@", ame134_bundleId]]
                toolLabel:@"jitstreamer"];
        } else if (@available(iOS 17.4, *)) {
            // auto（内置轨不可用/巨魔） / stikjit 共用 stikjit://
            NSString *scriptDataString = @"";
            if (!ame134_noScript &&
                ([ame134_enabler isEqualToString:@"stikjit"] ||
                 DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM))) {
                NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
                scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
            }
            // Task176：openURL 结果取证 + 无处理器即时指引（不盲等 120s）
            NSURL *ame176_jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", ame322_stikjitBundleId(), getpid(), scriptDataString]];
            [UIApplication.sharedApplication openURL:ame176_jitURL options:@{} completionHandler:^(BOOL ame176_ok) {
                NSLog(@"[JIT] [Gate] Task176 openURL stikjit:// -> %d", ame176_ok);
                if (!ame176_ok) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        showDialog(localize(@"Error", nil), localize(@"launcher.jit.stikjit_unhandled", nil));
                    });
                }
            }];
        } else {
            // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing.
            [self ame323_openJITEnablerURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]]
                toolLabel:@"sidestore://sidejit-enable"];
        }
    }

    // ★ Task355：从这里起进入等待环（hasTrollStoreJIT / enabler 分支都会落到
    //   此），置位单飞标记；完成块统一清位。
    gPL355GateInFlight = YES;
    if (onStage) onStage(localize(@"i18n_str_436", nil));

    // Task267：等待期可取消弹窗（120s 心跳 10s；取消/超时语义见下）
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_437", nil)
                                                                   message:hasTrollStoreJIT ? localize(@"i18n_str_2054", nil) : localize(@"i18n_str_439", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * _Nonnull action) {
        // ★ Task295：失败弹窗呈现引发的本弹窗程序性 dismiss 也会回调这里——
        //   弹窗在场期间见位即忽略，非用户意图。
        if (ame267_builtinDialogShowing) {
            NSLog(@"[JIT] [Gate] Task295: waiting-alert cancel fired by builtin-dialog cascade -- ignored");
            return;
        }
        ame267_cancelled = YES;
        NSLog(@"[JIT] [Gate] Task267: user cancelled JIT wait (main)");
    }]];
    // ★ Task223：进度型弹窗无动画呈现（stikjit:// 切后台转场瞬间的 animated
    //   present 是主线程楔死头号嫌疑类）。
    // ★ Task281：玻璃档改走磨砂玻璃面板镜像接管，镜像拒收回退原生。
    [AmeNativeMenu ame281_presentSystemAlert:alert fromHost:hostVC];

    // Task172：后台任务断言——stikjit:// 必然切后台，无断言时 iOS 立即挂起
    // 本进程（等待循环被冻结，760c07c 装机日志实锤）。
    __block UIBackgroundTaskIdentifier ame172_bgt = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"ame172-jit-wait" expirationHandler:^{
        // 宽限期到由系统挂起；恢复后循环按剩余预算继续。
    }];
    double ame181_bgTime = [UIApplication.sharedApplication backgroundTimeRemaining];
    NSLog(@"[JIT] [Gate] Task179 background task assertion: id=%lu valid=%d (remaining bg time %@)",
          (unsigned long)ame172_bgt, ame172_bgt != UIBackgroundTaskInvalid,
          (ame181_bgTime > 1e300) ? @"fg(n/a)" : [NSString stringWithFormat:@"%.0fs", ame181_bgTime]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Task169：有界等待（120s）+ 每 10s 心跳日志。
        BOOL ok = ame169_waitForJITCondition(^{ return (BOOL)(ame267_cancelled || isJITEnabled(false)); }, 120.0, @"isJITEnabled");
        // Task185：自愈式派发（condition satisfied 后主队列续接块在被楔死的
        // 主队列上永不执行的主治——见 utils.h ame185_dispatchToMainSelfHealing）。
        ame185_dispatchToMainSelfHealing(^{
            NSLog(@"[JIT] [Gate] Task183 wait-completed block entered on main (ok=%d)", ok);
            gPL355GateInFlight = NO;   // ★ Task355：先清位再分支（重试再进入合法）
            if (ame172_bgt != UIBackgroundTaskInvalid) {
                [UIApplication.sharedApplication endBackgroundTask:ame172_bgt];
                ame172_bgt = UIBackgroundTaskInvalid;
            }
            if (ame267_cancelled) {
                // Task267：用户主动取消——不启动游戏，恢复启动器交互态
                NSLog(@"[JIT] [Gate] Task267: JIT wait cancelled -- abandoning launch");
                if (onAbandon) onAbandon();
                return;
            }
            if (ok) {
                // Task182：成功路径不依赖 dismiss completion（后台态 present
                // 动画未完成时 dismiss completion 永不回调——completion:nil）。
                [alert dismissViewControllerAnimated:YES completion:nil];
                // Task172：等待成功 ≠ 能安全启动。StikJIT 附加后又死亡时
                // CS_DEBUGGED 已置而 JIT26 调试器无人服务 brk #0x69——与入口
                // CS_DEBUGGED 分支同款存活性复查。
                if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) &&
                    !JIT26IsLikelyDebuggerKeepAttached() &&
                    ![StikDebugViewController ame294_scriptCompletedThisSession] &&
                    !getPrefBool(@"debug.jit26_script_disable")) {
                    NSLog(@"[JIT] [Gate] Task172 wait satisfied but JIT26 debugger is gone — re-attaching before launch");
                    [self ame323_reattachJIT26ThenLaunch:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
                } else {
                    NSLog(@"[JIT] [Gate] Task183 invoking launch handler");
                    handler();
                }
            } else {
                [alert dismissViewControllerAnimated:YES completion:nil];
                // ★ Task226：间歇性失败（StikJIT 冷启动 URL 无人接住）形态——
                // 静默自动重拉一次 enabler URL + 续一轮等待预算，第二轮也
                // 超时才真正打扰用户。
                if (!gPL323JITAutoRetried) {
                    gPL323JITAutoRetried = YES;
                    NSLog(@"[JIT] [Gate] Task226 wait timed out -- AUTO-RETRY: re-firing enabler URL once before alerting");
                    [self invokeAfterJITEnabledWithHandler:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
                    return;
                }
                gPL323JITAutoRetried = NO;
                [self ame323_showJITTimeoutAlertWithRetry:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
            }
        }, @"Gate main wait");
    });
}

/// Task185：JIT 开启工具 URL 统一拉起（回执取证 + 失败即时指引）。
+ (void)ame323_openJITEnablerURL:(NSURL *)url toolLabel:(NSString *)tool {
    if (!url) {
        NSLog(@"[JIT] [Gate] Task185 openURL skipped: nil URL (tool=%@)", tool);
        return;
    }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL ok) {
        NSLog(@"[JIT] [Gate] Task185 openURL %@ -> %d", tool, ok);
        if (!ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showDialog(localize(@"Error", nil), [NSString stringWithFormat:localize(@"ame193.misc.jit_not_handled", @"%@ 未接管启动请求（未安装或版本过旧？）。请在设置的 JIT 开启工具中换用其它工具后重试。"), tool]);
            });
        }
    }];
}

/// Task169：JIT 等待超时后的出路弹窗（重试 = 重新走一轮门禁；取消 = 回启动器）。
+ (void)ame323_showJITTimeoutAlertWithRetry:(void (^)(void))handler
                                     hostVC:(UIViewController *)hostVC
                                  onAbandon:(void (^)(void))onAbandon
                                    onStage:(void (^)(NSString *))onStage {
    NSLog(@"[JIT] [Gate] Task169 JIT wait timed out, showing retry alert");
    UIAlertController *retry = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_437", nil)
                                                                   message:localize(@"ame189.jit.timeout_msg", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [retry addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        // ★ Task355（#20 配套）：超时弹窗取消 = 放弃本次启动——恢复启动器
        //   交互态。旧实现 handler:nil：取消后启动链交互态悬挂（启动钮不可
        //   用/等待残留），用户只能杀 App 重开——与 #20 装机 latestlog 终局
        //   force-close 同款病历。
        NSLog(@"[JIT] [Gate] Task355: JIT timeout alert cancelled -- abandoning launch");
        if (onAbandon) onAbandon();
    }]];
    [retry addAction:[UIAlertAction actionWithTitle:localize(@"ame189.jit.retry", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self invokeAfterJITEnabledWithHandler:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
    }]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && hostVC.view) {
        retry.popoverPresentationController.sourceView = hostVC.view;
        retry.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(hostVC.view.bounds), CGRectGetMidY(hostVC.view.bounds), 0, 0);
    }
    [AmeNativeMenu ame281_presentSystemAlert:retry fromHost:hostVC];   // ★ Task281：玻璃档镜像接管
}

/// Task172：JIT26 调试器重挂统一助手（stikjit:// + 有界等待 + 前台等待 +
/// 后台任务断言）。三道防线：①App 非激活态先等前台（一次性监听 + 10s 兜底）；
/// ②拉起 stikjit://（附 UniversalJIT26.js）；③断言防挂起冻结 + 有界等调试器
/// 存活，超时走重试弹窗。
+ (void)ame323_reattachJIT26ThenLaunch:(void (^)(void))handler
                                hostVC:(UIViewController *)hostVC
                             onAbandon:(void (^)(void))onAbandon
                               onStage:(void (^)(NSString *))onStage {
    // ★ Task355：重挂链同样占单飞位（主等待完成块已清位，此处重占防在飞
    //   窗口内重复链插入）；完成块入口清位。
    gPL355GateInFlight = YES;
    if (onStage) onStage(localize(@"i18n_str_436", nil));
    // Task267：重挂等待同样可取消（同主等待语义）。
    __block BOOL ame267_cancelled = NO;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_437", nil)
                                                                   message:localize(@"i18n_str_439", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * _Nonnull action) {
        ame267_cancelled = YES;
        NSLog(@"[JIT] [Gate] Task267: user cancelled JIT wait (reattach)");
    }]];
    [AmeNativeMenu ame281_presentSystemAlert:alert fromHost:hostVC];   // ★ Task281（Task223 无动画契约在助手内保留）

    __block UIBackgroundTaskIdentifier ame172_bgt = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"ame172-jit26-reattach" expirationHandler:^{
        // 同上：宽限期到由系统挂起，恢复后继续。
    }];

    void (^ame172_fireURL)(void) = ^{
        NSString *scriptDataString = @"";
        NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
        if (scriptData) {
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", ame322_stikjitBundleId(), getpid(), scriptDataString]] options:@{} completionHandler:^(BOOL ame185_ok) { // Task322 口径
            NSLog(@"[JIT] [Gate] Task185 re-attach stikjit:// -> %d", ame185_ok);
        }];
        NSLog(@"[JIT] [Gate] Task172 stikjit:// re-attach fired (script=%lu bytes)",
              (unsigned long)scriptData.length);
    };

    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        // 后台态：openURL 无效，先等回前台再拉起（一次性监听 + 10s 兜底，
        // 双 nil 防护防双发）。
        __block id ame172_obs = nil;
        ame172_obs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *ame172_n) {
            [[NSNotificationCenter defaultCenter] removeObserver:ame172_obs];
            ame172_obs = nil;
            ame172_fireURL();
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (ame172_obs) {
                [[NSNotificationCenter defaultCenter] removeObserver:ame172_obs];
                ame172_obs = nil;
                ame172_fireURL();
            }
        });
    } else {
        ame172_fireURL();
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Wait for the JIT26 debugger to actually attach (P_TRACED /
        // exception ports / spawned-by-debugger), not for CS_DEBUGGED.
        // Task169：有界等待（120s）+ 心跳日志，超时走重试弹窗。
        BOOL ok = ame169_waitForJITCondition(^{ return (BOOL)(ame267_cancelled || JIT26IsLikelyDebuggerKeepAttached()); }, 120.0, @"JIT26 debugger attach");
        // Task185：自愈式派发（同主等待路径）。
        ame185_dispatchToMainSelfHealing(^{
            gPL355GateInFlight = NO;   // ★ Task355：先清位再分支（重试再进入合法）
            if (ame172_bgt != UIBackgroundTaskInvalid) {
                [UIApplication.sharedApplication endBackgroundTask:ame172_bgt];
                ame172_bgt = UIBackgroundTaskInvalid;
            }
            if (ame267_cancelled) {
                // Task267：用户主动取消——不启动游戏，恢复启动器交互态
                NSLog(@"[JIT] [Gate] Task267: JIT wait cancelled -- abandoning launch");
                if (onAbandon) onAbandon();
                return;
            }
            if (ok) {
                // Task182：completion:nil + 直接执行（reattach 场景 App 常在后台）。
                [alert dismissViewControllerAnimated:YES completion:nil];
                if (handler) handler();
            } else {
                [alert dismissViewControllerAnimated:YES completion:nil];
                [self ame323_showJITTimeoutAlertWithRetry:handler hostVC:hostVC onAbandon:onAbandon onStage:onStage];
            }
        }, @"Gate reattach wait");
    });
}

@end
