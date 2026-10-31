#!/usr/bin/env python3
# ame368_selfcheck.py -- Task 368 门禁（AI 聊天请求未发送根修：全链观测面 + busy 僵死自愈 + 呈现兜底 + 键盘发送键）
# 用户实录："为什么ai请求没有发送，而测试却发送了。"（装机 9b6e33d latestlog：20:53:26 测试"连接成功"弹窗在案，
# 此后聊天尝试零日志零弹窗零请求——AI 页是壳 childCache 缓存常驻页，错误弹窗固定从 self present，
# 不在窗口层级时 UIKit 静默拒绝 = 全部错误路径对用户集体哑火；Agent 单例 running 卡死则 busy 拒绝也看不见）
# A 观测面：4 文件 [Ame368] 日志锚（ui send-tap/rejected/accepted/error-present/漂移/清扫 +
#           agent accept/busy-gate/stall-break/round# /round-end + net dispatch/done/serialize/abort）
# B 修复面：B1 provider 前置校验 / B2 stall 自愈四件套+挂点 / B3 呈现兜底 topmost /
#           B4 viewDidAppear 漂移对齐+残泡清扫 / B5 isRunning 访问器 / B6 输入栏 enabled 同步
# C i18n：零新增键（复用 ai.api.provider_incomplete；task191 锚不动）
# S 反向探针：老病灶"固定 self present"清零 / ame367 快照次序不受日志插入扰动 / 密钥零泄漏
import io, re, sys

REPO = "/home/z/my-project/repo-prisma2"

def read(p):
    with io.open(REPO + "/" + p, encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

vc = read("Natives/AI/AIViewController.m")
bar = read("Natives/AI/AIInputBarView.m")
agent = read("Natives/AI/AiAgent.m")
api = read("Natives/AI/AiAPIClient.m")
agenth = read("Natives/AI/AiAgent.h")
zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings")

# ══ A 观测面 ═════════════════════════════════════════════════
check('A1 UI 发送链五锚（tap 拒绝/无服务商/不完整/接受/空输入）',
      '[Ame368] ui send-tap -> send' in bar and '[Ame368] ui send-tap -> stop' in bar
      and '[Ame368] ui send-tap dropped (empty)' in bar
      and '[Ame368] ui send rejected reason=no_provider' in vc
      and '[Ame368] ui send rejected reason=provider_incomplete' in vc
      and '[Ame368] ui send accepted provider=' in vc
      and '[Ame368] ui send dropped reason=empty' in vc)
check('A2 UI 错误呈现锚（error-present + FAILED 兜底 + configure-hint FAILED）',
      '[Ame368] ui error-present' in vc and '[Ame368] ui error-present FAILED' in vc
      and '[Ame368] ui configure-hint FAILED' in vc)
check('A3 Agent 全轮次锚（accept/busy-gate/stall-break/round#/round-end 三态/cap/terminalErr/stop）',
      '[Ame368] agent accept len=' in agent and '[Ame368] agent busy-gate' in agent
      and '[Ame368] agent stall-break' in agent and '[Ame368] agent round#' in agent
      and '[Ame368] agent round-end err=' in agent and '[Ame368] agent round-end toolCalls=' in agent
      and '[Ame368] agent round-end done contentLen=' in agent
      and '[Ame368] agent round-end terminalErr=' in agent
      and '[Ame368] agent round-end cap' in agent and '[Ame368] agent stop-current' in agent)
check('A4 网络层锚（dispatch=请求离 App 首锚/done/serialize-fail/abort 两门）',
      '[Ame368] net dispatch ' in api and '[Ame368] net done status=' in api
      and '[Ame368] net serialize-fail' in api
      and '[Ame368] net abort provider-incomplete' in api
      and '[Ame368] net abort invalid-url' in api)
check('A5 密钥零泄漏（全部 [Ame368] 日志行不含 apiKey 字样）',
      all('apiKey' not in ln for ln in (vc + bar + agent + api).splitlines() if '[Ame368]' in ln))

# ══ B 修复面 ═════════════════════════════════════════════════
check('B1 provider 完整性前置校验（baseURL/model 点名 + 复用既有键）',
      'provider.baseURL.length == 0 || provider.model.length == 0' in vc
      and vc.count('ai.api.provider_incomplete') >= 1)
check('B2 stall 自愈四件套（在途属性/inFlightKind/noteActivity/resetInFlight）',
      all(p in agent for p in (
          'ame368_streamInFlight', 'ame368_activeToolCount', 'ame368_confirmInFlight',
          'ame368_gapSince', 'ame368_flowStartAt',
          '- (NSString *)ame368_inFlightKind', '- (void)ame368_noteActivity',
          '- (void)ame368_resetInFlight'))
      and 'kAme368StallTimeout' in agent)
check('B2b 在途挂点覆盖（流出入/工具出入/确认出入/终态归零/停止归零）',
      agent.count('[self ame368_noteActivity]') + agent.count('[strongSelf ame368_noteActivity]')
      + agent.count('[ss2 ame368_noteActivity]') + agent.count('[ss3 ame368_noteActivity]')
      + agent.count('[ss4 ame368_noteActivity]') >= 7
      and agent.count('ame368_resetInFlight]') >= 6)
check('B2c stall-break 落地序（强拆=running=NO 后 resetInFlight，然后走正常接受路径）',
      re.search(r'stall-break[^\n]*\n[^\n]*\n\s*self\.running = NO;\s*\n\s*\[self ame368_resetInFlight\];', agent) is not None)
check('B3 呈现兜底（topmost 定位器 + showError/showConfigure 双消费）',
      '- (nullable UIViewController *)ame368_presentTarget {' in vc
      and vc.count('[ame368_host presentViewController:alert animated:YES') == 2
      and 'if ([self isViewLoaded] && self.view.window) return self;' in vc)
check('B3b 老病灶"固定 self present"清零（两处 alert 呈现不再直接走 self）',
      '[self presentViewController:alert animated:YES completion:nil];' not in vc)
check('B4 viewDidAppear 漂移对齐（双向）+ 残泡清扫（Agent 运行中跳过）',
      '[Ame368] ui drift-fix isSending YES->NO (agent idle)' in vc
      and '[Ame368] ui drift-fix isSending NO->YES (agent busy)' in vc
      and '- (void)ame368_sweepStaleStreaming {' in vc
      and re.search(r'ame368_sweepStaleStreaming \{\s*\n\s*if \(\[\[AiAgent sharedAgent\] isRunning\]\) return;', vc) is not None)
check('B5 isRunning 只读访问器（.h 声明 + .m 实现）',
      '- (BOOL)isRunning;' in agenth and '- (BOOL)isRunning {' in agent)
check('B6 输入栏 enabled 同步（退出发送态按文本框实况刷新可用性）+ 键盘发送键接线',
      re.search(r'if \(!isSending\) \{[\s\S]{0,200}self\.sendButton\.enabled = trimmed\.length > 0;', bar) is not None
      and bar.count('self.sendButton.enabled = trimmed.length > 0;') == 2
      and '<UITextFieldDelegate>' in bar and 'self.inputField.delegate = self;' in bar
      and '- (BOOL)textFieldShouldReturn:(UITextField *)textField {' in bar
      and re.search(r'textFieldShouldReturn:[\s\S]{0,120}\[self sendButtonTapped\];', bar) is not None)

# ══ C i18n 零新增键 ══════════════════════════════════════════
check('C1 零新增 i18n 键（zh-Hans 无 ame368 字样，task191 锚不动）', 'ame368' not in zh)
check('C2 复用键在案（ai.api.provider_incomplete / ame192.ai.request_failed）',
      '"ai.api.provider_incomplete"' in zh and '"ame192.ai.request_failed"' in zh)

# ══ S 反向探针 ═══════════════════════════════════════════════
m = re.search(r"- \(void\)URLSession:\(NSURLSession \*\)session task:\(NSURLSessionTask \*\)task didCompleteWithError:\(NSError \*\)error \{(.*?)\n\}", api, re.S)
check('S1 ame367 快照次序不受本轮日志插入扰动（A2/A3 语义复扫）',
      m is not None
      and m.group(1).find('void (^chunk)(NSString *, NSDictionary *) = self.onChunk;') <
          m.group(1).find('self.onChunk = nil;')
      and m.group(1).count('ame367_flushPendingDeltaWithChunk:chunk') >= 3
      and '[self flushPendingDelta];' not in m.group(1))
check('S2 busy 拒绝路径保留（非 stalled 时仍走 ai.agent.busy 拒绝，不误杀合法在途）',
      'ai.agent.busy' in agent and 'kAme368StallTimeout' in agent
      and re.search(r'if \(!ame368_stalled\) \{[\s\S]{0,400}ai\.agent\.busy', agent) is not None)
check('S3 键盘返回键不插换行（return NO，发送/停止同入口无旁路）',
      re.search(r'textFieldShouldReturn:\(UITextField \*\)textField \{[\s\S]{0,120}\[self sendButtonTapped\];\s*\n\s*return NO;', bar) is not None)

print(f"\name368: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print(f"  FAILED: {f}")
    sys.exit(1)
