#!/usr/bin/env python3
"""verify_task263.py -- Task263 round verifier (mod search empty + mirror crash).

User report (2026-10-22 device log): "[ModrinthAPI] Task217: JSON parse
failure (未能读取数据，因为它的格式不正确。)" -- mod search list stays
empty, and using the mod mirror source (MCIM) crashes / hangs the app.

Root causes fixed:
  (1) ame217 recursive block captured its own nil value (missing __block):
      retry never ran, completion never fired, search page inFlight stuck.
  (2) MCIM mirror returns HTTP 503 + text/html during outages; the old code
      fed HTML straight into NSJSONSerialization and retried the SAME
      endpoint only -- no official<->mirror fallback at the API layer.
  (3) ModpackAPI.getEndpoint used dispatch_group_wait(FOREVER) with
      AFNetworking main-queue completion: watchdog-kill risk.
  (4) ModVersionViewController dep-detail hard-coded the official host.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASSED, FAILED = 0, []


def rd(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def check(name, ok, detail=""):
    global PASSED
    if ok:
        PASSED += 1
        print(f"  PASS  {name}")
    else:
        FAILED.append(name)
        print(f"  FAIL  {name}  -- {detail[:160]}")


def strip_strings_comments(code):
    out, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        if c == '"':
            i += 1
            while i < n:
                if code[i] == '\\':
                    i += 2
                    continue
                if code[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
        elif code.startswith('//', i):
            j = code.find('\n', i)
            i = n if j < 0 else j
        elif code.startswith('/*', i):
            j = code.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def balanced(path):
    s = strip_strings_comments(rd(path))
    for o, c in [('{', '}'), ('(', ')'), ('[', ']')]:
        if s.count(o) != s.count(c):
            return False, f"unbalanced {o}: {s.count(o)} vs {c}: {s.count(c)}"
    return True, ""


mma = rd("Natives/installer/modpack/ModrinthAPI.m")
mma_code = strip_strings_comments(mma)  # 代码级检查（避开 Task263 病历注释里的旧缺陷模式引文）
mpa = rd("Natives/installer/modpack/ModpackAPI.m")
mpa_code = strip_strings_comments(mpa)
mvv = rd("Natives/ModVersionViewController.m")
pmc = rd("Natives/PLMirrorCenter.m")

print("== A. ame263 候选链状态机（ModrinthAPI.m） ==")
check("A1 ame263_candidateChainForURL 存在且双向换算（官方→镜像 + 镜像→官方）",
      "ame263_candidateChainForURL" in mma
      and 'ame263_officialHost = @"https://api.modrinth.com/"' in mma
      and 'ame263_mirrorPrefix = [PLMirrorMCIMRootURL stringByAppendingString:@"/modrinth/"]' in mma)
check("A2 候选排序复用 Task218 统一判定（mirrorPreferredForType:AssetSearch）",
      "mirrorPreferredForType:PLMirrorResourceTypeAssetSearch" in mma)
check("A3 状态机为实例方法递归（无块自引用捕获陷阱；代码级检查）",
      "[ame263_sself ame263_fetchCandidate:" in mma_code
      and "void (^ame217_attempt)" not in mma_code
      and "ame217_attempt(1)" not in mma_code)
check("A4 HTTP 状态码检查（非 2xx 不进解析器，503 HTML 直接判失败）",
      "((NSHTTPURLResponse *)response).statusCode" in mma
      and "ame263_status < 200 || ame263_status >= 300" in mma)
check("A5 失败日志带 host + 状态码（诊断可辨）",
      "candidate %lu/%lu (%@) failed" in mma and "url.host" in mma)
check("A6 全链耗尽汇总错误（i18n_str_1192 官方源与镜像源均失败）",
      'i18n_str_1192' in mma and 'underlyingErrors' in mma)
check("A7 旧缺陷模式清零（代码级：ame217_attempt / one retry in 1.5s / JSON parse failure 日志）",
      "ame217_attempt" not in mma_code
      and "one retry in 1.5s" not in mma_code
      and "JSON parse failure" not in mma_code)
check("A8 ame217 兼容壳签名不变（九调用点零改动：搜索/版本列表/依赖反查/项目名/整合包详情/shader版本/server搜索/server详情）",
      "- (void)ame217_fetchJSONWithURL:(NSURL *)url" in mma
      and mma.count("ame217_fetchJSONWithURL:url completion:") == 9)
check("A9 每候选重试 1 次 + 候选间交错（1.2s / 0.3s）",
      "1.2 * NSEC_PER_SEC" in mma and "0.3 * NSEC_PER_SEC" in mma)

print("== B. ModpackAPI.getEndpoint 限时化 ==")
check("B1 永久等待清零（代码级：DISPATCH_TIME_FOREVER 不在 ModpackAPI.m）",
      "DISPATCH_TIME_FOREVER" not in mpa_code)
check("B2 20s 限时 + 超时返回 nil + lastError 落账",
      "20.0 * NSEC_PER_SEC" in mpa
      and "getEndpoint timed out" in mpa
      and 'code:-1001' in mpa)
check("B3 AFNetworking 请求超时收紧（15s）",
      "manager.requestSerializer.timeoutInterval = 15.0" in mpa)

print("== C. 依赖详情镜像感知（ModVersionViewController.m） ==")
check("C1 PLMirrorCenter 接入",
      '#import "PLMirrorCenter.h"' in mvv)
check("C2 详情 URL 走 modrinthAPIBaseURL（硬编码官方域名退役）",
      "[PLMirrorCenter modrinthAPIBaseURL], self->_pid" in mvv
      and 'https://api.modrinth.com/v2/project' not in mvv)

print("== D. PLMirrorCenter 常量依赖在位 ==")
check("D1 MCIM 根常量与 AssetSearch 策略判定存在（Task263 消费面）",
      "PLMirrorMCIMRootURL" in pmc and "mirrorPreferredForType" in pmc)

print("== E. 语法平衡（改动 ObjC 文件） ==")
for f in ["Natives/installer/modpack/ModrinthAPI.m",
          "Natives/installer/modpack/ModpackAPI.m",
          "Natives/ModVersionViewController.m"]:
    ok, detail = balanced(f)
    check(f"E-balanced {os.path.basename(f)}", ok, detail)

print(f"\n{'=' * 40}")
print(f"verify_task263: {PASSED} passed, {len(FAILED)} failed")
if FAILED:
    for f in FAILED:
        print(f"  FAILED: {f}")
    sys.exit(1)
print("ALL GREEN")
