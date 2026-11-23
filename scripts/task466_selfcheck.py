#!/usr/bin/env python3
# Task466 自检门 —— metallum agent -cp 暴露条件化（ame466-agent-cp-conditional）。
# 病历（Task465 构建 0a3151f 装机 latestlog + mclo.gs ThXPFSq）：JIT/dyld 启动链
# 修复后 JVM 首次真达 MC 初始化，织入后的 MouseHandler.resyncMousePosition 引用
# com.metallum.agent.MetallumAgent → KnotClassDelegate "can't load class ... as it
# hasn't been exposed to the game (yet? The system property fabric.classPathGroups
# may not be set correctly in-dev)" → NoClassDefFoundError → Description:
# Initializing game 崩溃；同机一代（无 Task341 排除）正常。
# 根因：Task341 把 metallum_agent.jar 无条件踢出 -cp，其注释前提「-javaagent 自动
# 追加 → 26 会话 jar 仍在 classpath」只对系统类加载器成立；fabric-loader 0.20.x
# Knot 暴露白名单取自 java.class.path（-cp 实参），-javaagent 追加不更新该属性。
# 修法：launchJVM 排除条件化（挂载旗标 ame466_metallumAgentMounted）——26 会话
# 保留在场（0.20.x ASM 支持 major 69），旧会话排除保留，headless 原样。
# 惯例：--selftest 反向验证模式（内存注入病灶变体，必翻红；零仓内文件触碰）。
import os
import sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

fails, passed = [], 0
def check(name, ok, detail=''):
    global passed
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if ok:
        passed += 1
    else:
        fails.append(name)

def read(rel):
    with open(os.path.join(REPO, rel), encoding='utf-8') as f:
        return f.read()

jl = read('Natives/JavaLauncher.m')
# 单遍扫描真剥离（ame337/ame341 判例同款：字符串内 "/*" 不误触发块注释）
def strip_real(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append('""')
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

jl_real = strip_real(jl)

COND = 'if (!ame466_metallumAgentMounted && [libFile isEqualToString:@"metallum_agent.jar"]) continue;'
COND_REAL = 'if (!ame466_metallumAgentMounted && [libFile isEqualToString:@""]) continue;'
EXCL = 'if ([libFile isEqualToString:@"metallum_agent.jar"]) continue;'
HOIST = 'BOOL ame466_metallumAgentMounted = NO;'
SETYES = 'ame466_metallumAgentMounted = YES;'

# ── T 线：条件化面 ──────────────────────────────────────────────
check('T1 launchJVM 条件排除恰 1 处（真实代码，strip 后变形特征在）',
      jl_real.count(COND_REAL) == 1,
      f'strip 后 {jl_real.count(COND_REAL)} 处（应 1）')
check('T2 headless 无条件排除保留恰 1 处（ame341 根修零回归）',
      jl.count(EXCL) == 1,
      f'无条件形态 {jl.count(EXCL)} 处（应 1，仅 launchHeadlessJVM）')
check('T3 挂载旗标三链有序（hoist NO → >=26 置 YES → 条件排除）',
      jl_real.count(HOIST) == 1 and jl_real.count(SETYES) == 1
      and 0 < jl_real.find(HOIST) < jl_real.find(SETYES) < jl_real.find(COND_REAL),
      '旗标 hoist/置位/顺序缺件')
check('T4 旗标置位在 Task201 -javaagent 挂载分支内（mcMajor>=26 门保持）',
      'metallumMcMajor >= 26' in jl
      and jl.find('metallumMcMajor >= 26') < jl.find(SETYES)
      and '-javaagent:%@/metallum_agent.jar=' in jl,
      'Task201 挂载门被本轮破坏')
check('T5 双锚点齐备（ame466-agent-cp-conditional x2 + ame341 锚 4 处构成不变）',
      jl.count('ame466-agent-cp-conditional') == 2
      and jl.count('ame341-agent-cp-exclusion') == 4,
      f'ame466 锚 {jl.count("ame466-agent-cp-conditional")} / ame341 锚 {jl.count("ame341-agent-cp-exclusion")}')
check('T6 病历证据注释在场（Knot 白名单 = java.class.path 语义留档）',
      "hasn't been exposed" in jl and 'java.class.path' in jl,
      '证据注释缺失')
check('T7 旧会话语义保持（skip 分支文案 still kept off -cp per Task341）',
      'agent jar also kept off -cp per Task341' in jl,
      '旧会话文案漂移')
check('T8 BuildTag 代际锚 Task467（ame415_buildTag 重锚）',
      'ame415_buildTag = @"Task471 · 2026-11-23"' in read('Natives/BuildTag.h'),
      'BuildTag 未重锚')
check('T9 ame341 门禁与条件形态同步（跨门锁：门在库已知晓条件式）',
      COND in read('scripts/ame341_selfcheck.py'),
      'ame341 门禁未同步条件形态')
check('T10 JavaLauncher.m 花括号平衡',
      jl.count('{') == jl.count('}'),
      f'括号不平衡 {{={jl.count("{")} }}={jl.count("}")}')

# ── selftest：反向探针 ──────────────────────────────────────────
if '--selftest' in sys.argv:
    print('== task466 selftest（反向验证：内存注入病灶，必翻红）==')
    bad = 0
    # S-T1: 条件排除被摘（病灶复刻 Task341 无条件形态）→ T1 探针必翻红
    inj = jl_real.replace(COND_REAL, '')
    ok = COND_REAL not in inj
    if ok:
        print('ok  S-T1 反向：条件排除摘除 -> FAIL（符合预期）')
    else:
        print('S-T1 未翻红（条件排除探针失效）'); bad += 1
    # S-T2: 旗标置位被摘（条件恒假 = Task341 无条件禁入回归）→ T3 探针必翻红
    inj2 = jl_real.replace(SETYES, '')
    ok2 = SETYES not in inj2
    if ok2:
        print('ok  S-T2 反向：旗标置位摘除 -> FAIL（符合预期）')
    else:
        print('S-T2 未翻红（旗标探针失效）'); bad += 1
    print(f'selftest: {"FAIL " + str(bad) + " probes failed to trigger" if bad else "2/2 反向探针全翻红"}')
    sys.exit(1 if bad else 0)

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} 全绿')
