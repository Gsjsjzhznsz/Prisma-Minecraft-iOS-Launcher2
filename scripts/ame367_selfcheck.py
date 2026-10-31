#!/usr/bin/env python3
# ame367_selfcheck.py -- Task 367 门禁（AI 回复不可见根修 + 插件运行时定时器 + 插件文档权限/定时器纪律）
# 用户实录："为什么 ai 执行完成之后看不到 ai 的回复呢。" + latestlog 实锤
# ui.free.drag 抛 ReferenceError: Can't find variable: setTimeout / 权限拒绝: notify
# A 流尾修复（AiAPIClient）：回调快照先于清空 / 三条完成路径快照 flush / message 形态兼容
# B 权威回填（AiAgent）：fullResponse.content 择长回填 / 空回复不留泡 / 位置序（错误检查后、工具分支前）
# C 定时器（AmePluginRuntime）：四全局注册 / 每插件注册表 / 卸载清表 / liveness 双闸 / 防失控钳制
# D 文档：铁律区定时器行 + 权限声明纪律行 + writer 同步 + 无 ame.setTimeout 漂移名
# S 病灶反向：didCompleteWithError 体内不再有裸 flushPendingDelta / 节流路径保留旧入口
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

api = read("Natives/AI/AiAPIClient.m")
agent = read("Natives/AI/AiAgent.m")
rt = read("Natives/AmePluginRuntime.m")
dtool = read("Natives/AI/AiPluginDocsTool.m")
ptool = read("Natives/AI/AiPluginWriterTool.m")

# ══ A 流尾修复（AiAPIClient） ═══════════════════════════════
m = re.search(r"- \(void\)URLSession:\(NSURLSession \*\)session task:\(NSURLSessionTask \*\)task didCompleteWithError:\(NSError \*\)error \{(.*?)\n\}", api, re.S)
check('A1 didCompleteWithError 方法体可定位', m is not None)
if m:
    body = m.group(1)
    cap_pos = body.find('void (^chunk)(NSString *, NSDictionary *) = self.onChunk;')
    nil_pos = body.find('self.onChunk = nil;')
    check('A2 回调快照捕获先于 onChunk 清空（根修次序铁律）',
          cap_pos != -1 and nil_pos != -1 and cap_pos < nil_pos)
    n_snapshot_flush = body.count('ame367_flushPendingDeltaWithChunk:chunk')
    check('A3 三条完成路径（错误/非200/成功）均用快照 flush', n_snapshot_flush >= 3, f"got {n_snapshot_flush}")
    check('S1 完成方法体内不再有裸 flushPendingDelta（旧病灶清零）',
          '[self flushPendingDelta];' not in body)
check('A4 flushPendingDelta 节流路径保留（委托快照入口）',
      '[self ame367_flushPendingDeltaWithChunk:self.onChunk];' in api)
check('A5 快照 flush 实现存在且派发主队列',
      '- (void)ame367_flushPendingDeltaWithChunk:(void (^)(NSString *, NSDictionary *))chunk {' in api
      and 'dispatch_async(dispatch_get_main_queue(), ^{ chunk(safeDelta, nil); });' in api)
check('A6 message 形态兼容（choices[].message 整包回退）',
      'NSDictionary *ame367_message = choice[@"message"];' in api and 'delta = ame367_message;' in api)

# ══ B 权威回填（AiAgent） ═══════════════════════════════════
rec_pos = agent.find('ame367_fullText.length > assistantMessage.content.length')
err_pos = agent.find('if (error) {')
tool_pos = agent.find('if (accToolCalls.count > 0) {')
check('B1 权威回填块存在（fullResponse.content 择长回填）', rec_pos != -1)
check('B2 回填位置序：错误检查之后、工具分支之前（回填覆盖两条分支）',
      err_pos != -1 and rec_pos != -1 and tool_pos != -1 and err_pos < rec_pos < tool_pos)
empty_ok = agent.find('// ★ Task367：真·空回复不留在会话里') != -1 and \
    re.search(r"// 无工具调用，正常结束\s*\n\s*if \(assistantMessage\.content\.length == 0\) \{\s*\n\s*// ★ Task367", agent)
check('B3 成功空回复移除占位（不留空气泡）', empty_ok is not None)
check('B4 回填仅择长不回退（防非流式路径覆盖流式累积）',
      'ame367_fullText.length > assistantMessage.content.length' in agent)

# ══ C 定时器（AmePluginRuntime） ═════════════════════════════
check('C1 四个定时器全局注册（下标赋值注入，CI r1 实锤 valueWithBlock:inContext: 不存在）',
      all(f'ctx[@"{g}"] = ' in rt for g in
          ("setTimeout", "setInterval", "clearTimeout", "clearInterval")))
check('C2 每插件注册表（装载建表 + 卸载清表）',
      'self.timerRegistries[pluginId] = timers;' in rt and
      '[self.timerRegistries removeObjectForKey:pluginId];' in rt)
check('C3 liveness 双闸（contexts 查活 + 句柄 active 查活）',
      'strongRuntime.contexts[pluginId] != ctx' in rt and
      '![timers[handle] boolValue]' in rt)
check('C4 防失控钳制（单次/周期 ≤300000ms，周期下限 10ms）',
      'ms > 300000) ms = 300000;' in rt and '!(ms >= 10)) ms = 10;' in rt)
check('C5 调度器主队列 + 周期自续约 + 单次出表',
      'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, deltaNs), dispatch_get_main_queue(),' in rt
      and '[strongRuntime ame367_scheduleTimer:fn ms:ms repeat:YES' in rt
      and '[timers removeObjectForKey:handle];' in rt)
check('C6 注册表属性与初始化在位',
      '@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *timerRegistries;' in rt
      and '_timerRegistries = [NSMutableDictionary dictionary];' in rt)

# ══ D 文档（docs + writer 同步） ═════════════════════════════
check('D1 文档铁律区定时器行（四全局 + 浏览器同语义）',
      '运行环境全局可用：setTimeout/setInterval/clearTimeout/clearInterval' in dtool)
check('D2 文档权限声明纪律行（漏声明=运行时权限拒绝异常）',
      'permissions 必须覆盖代码实际调用的全部 ame.* 域' in dtool)
check('D3 writer 工具摘要同步（权限纪律 + 定时器全局）',
      'permissions 必须覆盖代码实际调用的全部 ame.* 域' in ptool and
      'setTimeout/setInterval/clearTimeout/clearInterval' in ptool)
check('S2 文档不含 ame.setTimeout 漂移名（定时器是全局非桥面，防 E 探针误报）',
      'ame.setTimeout' not in dtool and 'ame.setInterval' not in dtool)
check('D4 提示词 v7 现役默认未受扰（本轮不动 AiSettings）',
      'ame366_v6DefaultSystemPrompt' in read("Natives/AI/AiSettings.m"))

print(f"\name367: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print(f"  FAILED: {f}")
    sys.exit(1)
