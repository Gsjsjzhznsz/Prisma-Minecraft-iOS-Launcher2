#!/usr/bin/env python3
# ame353_selfcheck.py -- Task353 门禁（装机 29f8b67 "该版本无效"latestlog 终局线）
# A 启动期版本根对齐（PLProfiles ame353_versionRootForProfileName 纯读探测
#   + ZL2Home launchGame 对齐 POJAV_GAME_DIR + [Ame353] 日志锚）
# B 注册表失守护栏（last-known-good 锚：读成功才记 / 失守回读零写入）
# C ZL2VersionIndex 实例树兜底扫描（②' 层，hook 顺序 ②→②'→③）
# S 反向探针（病灶变体注入比对必翻红，零仓内触碰）
# 断言纪律：含字符串字面量的断言用原文（raw）；strip 后文本仅用于纯结构检查
# （strip_keep_str 事故判例：字符串内容剥离会让字面量断言全假红）。
import os, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
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

def strip_code(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

plp = read("Natives/PLProfiles.m")
plp_code = strip_code(plp)
plph = read("Natives/PLProfiles.h")
home = read("Natives/ZL2HomeViewController.m")
home_code = strip_code(home)
idx = read("Natives/ZL2VersionIndex.m")
idx_code = strip_code(idx)
idxh = read("Natives/ZL2VersionIndex.h")

# ══ A 启动期版本根对齐 ═══════════════════════════════════════
check('A1 PLProfiles 版本根探测（.h 声明 + .m 实现签名 + <vid>/<vid>.json 真实文件探针）',
      "+ (NSString *)ame353_versionRootForProfileName:(NSString *)profileName;" in plph
      and "+ (NSString *)ame353_versionRootForProfileName:(NSString *)profileName {" in plp_code
      and 'stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame353_vid]' in plp)

check('A2 探测卫哨（latest-* 别名短路 / 空 vid 短路 / POJAV_HOME 缺失短路）',
      'if ([ame353_vid hasPrefix:@"latest-"]) return nil;' in plp
      and 'if (![ame353_vid isKindOfClass:[NSString class]] || ame353_vid.length == 0) return nil;' in plp_code
      and 'if (ame353_home.length == 0) return nil;' in plp_code)

check('A3 gameDir 展开 Task275 同口径（绝对原样 / 相对 instances/<偏好目录>/ 拼接）',
      'if ([ame353_gd isAbsolutePath]) {' in plp_code
      and '/instances/%@/%@' in plp
      and 'getPrefObject(@"general.game_directory")' in plp)

check('A4 祖先链近→远探测 + POJAV_HOME 必停 + GAME_DIR 锚兜底（深度 6 上限）',
      'ame353_depth < 6' in plp_code
      and 'if ([ame353_cur isEqualToString:ame353_home]) break;' in plp_code
      and 'NSString *ame353_envRoot = @(getenv("POJAV_GAME_DIR") ?: "");' in plp
      and 'NSString *(^ame353_jsonFor)(NSString *)' in plp_code)

check('A5 ZL2Home launchGame 对齐落位（发 FindVersionInRemoteList 前 setenv + 对齐日志锚）',
      '[PLProfiles ame353_versionRootForProfileName:selectedProfile]' in home_code
      and 'setenv("POJAV_GAME_DIR", ame353_root.UTF8String, 1);' in home
      and '"[Ame353] launch version-root aligned: %@ -> %@ (profile=%@, vid=%@)"' in home
      and home.index("[PLProfiles ame353_versionRootForProfileName:selectedProfile]")
          < home.index('postNotificationName:@"FindVersionInRemoteList"'))

# ══ B 注册表失守护栏 ═══════════════════════════════════════
check('B1 last-known-good 锚（静态存在 + 读成功才记锚 + 失守回读）',
      "static NSString *_ame353_registryLastGoodPath = nil;" in plp
      and "_ame353_registryLastGoodPath = [self.profilePath copy];" in plp_code
      and 'parseJSONFromFile(_ame353_registryLastGoodPath)' in plp_code)

fallback_at = home_code.find("ame353") if False else plp.find("[Ame353] registry fallback")
check('B2 回读命中提前 return（defaultProfiles+[self save] 不执行 = 实例根绝不被误写）',
      fallback_at > 0
      and "return self;" in plp[fallback_at:fallback_at + 500]
      and plp_code.index("ame353_rescued = parseJSONFromFile")
          < plp_code.index("self.profileDict = PLProfiles.defaultProfiles;")
      and plp_code.index("self.profileDict = PLProfiles.defaultProfiles;")
          < plp_code.index("_ame353_registryLastGoodPath = [self.profilePath copy];"))

# ══ C ZL2VersionIndex 实例树兜底 ═══════════════════════════
check('C1 实例树扫描实现（instances/*/versions/<id> 目录级 + 隐藏目录跳过）',
      "- (NSDictionary *)ame_scanInstancesTreeForVersionId:(NSString *)versionId {" in idx_code
      and 'stringByAppendingPathComponent:@"instances"' in idx
      and '[inst hasPrefix:@"."]' in idx)

check('C2 hook 顺序 ②→②\'→③（实例树在本地扫描后、Task72 磁盘兜底前）',
      idx_code.index("ame_scanInstancesTreeForVersionId:versionId")
          > idx_code.index("ame_scanLocalVersionId:versionId")
      and idx_code.index("ame_scanInstancesTreeForVersionId:versionId")
          < idx_code.index("ame_versionJsonOnDisk:versionId")
      and "resolved '%@' from instances tree scan (Task353)" in idx)

check('C3 .h 契约注释同步（②\' 层语义可 grep）',
      "实例树兜底扫描命中" in idxh and "Task353" in idxh)

# ══ S 反向探针（病灶变体注入比对，零仓内触碰） ═════════════
# S-A 对齐链摘除必须翻红
check('S-A1 摘除 setenv 对齐行 → 变体可检出',
      'setenv("POJAV_GAME_DIR", ame353_root.UTF8String, 1);' in home
      and 'setenv("POJAV_GAME_DIR", ame353_root.UTF8String, 1);'
          not in home.replace('setenv("POJAV_GAME_DIR", ame353_root.UTF8String, 1);', ""))
check('S-A2 摘除版本 JSON 探针 → 变体可检出',
      'stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame353_vid]' in plp
      and 'stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame353_vid]'
          not in plp.replace('stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", ame353_vid]', ""))
# S-B 护栏退化（失守直落出厂重置）必须翻红
check('S-B1 回读锚禁用变体可检出',
      "if (_ame353_registryLastGoodPath.length > 0" in plp_code
      and "if (_ame353_registryLastGoodPath.length > 0"
          not in plp_code.replace("if (_ame353_registryLastGoodPath.length > 0",
                                  "if (NO && _ame353_registryLastGoodPath.length > 0"))
# S-C 实例树扫描摘除必须翻红
check('S-C1 实例树 hook 摘除 → 变体可检出',
      "ame_scanInstancesTreeForVersionId:versionId" in idx_code
      and "ame_scanInstancesTreeForVersionId:versionId"
          not in idx_code.replace("ame_scanInstancesTreeForVersionId:versionId", "ame353_DISABLED"))

print()
if fails:
    print(f"ame353_selfcheck: {len(fails)} FAIL / {passed} PASS")
    for f in fails:
        print(f"  - {f}")
    sys.exit(1)
print(f"ame353_selfcheck: ALL GREEN ({passed} assertions)")
