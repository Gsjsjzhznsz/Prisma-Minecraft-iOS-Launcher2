#!/usr/bin/env python3
# ame365_prompt_upgrade.py -- Task365 提示词 v5→v6 原子升级
# ① defaultSystemPrompt 的【七】章替换为紧凑版（create_plugin 契约 + 20 项权限行
#    + get_plugin_docs 文档铁律），其余章节逐字节不动；
# ② 紧随其后插入 ame365_v5DefaultSystemPrompt 留档（迁移基线 = git HEAD v5
#    逐字节拼接行复用）；
# ③ 迁移链加 v5→v6 支（逐字一致删键回落；自定义保留）；版本号 setInteger:5→6；
# ④ 自证：留档产出串 == git HEAD v5 产出串（逐字节）；v6 含铁律/20 项/无巨型 API 块。
import io, re, subprocess, sys

REPO = "/home/z/my-project/repo-prisma2"
PATH = REPO + "/Natives/AI/AiSettings.m"
V5_BODY = io.open("/tmp/ame365_v5_archive.txt", encoding="utf-8").read()

FRAG = re.compile(r'@?"((?:[^"\\]|\\.)*)"')
def produced(src_text):
    return "".join(m.group(1) for m in FRAG.finditer(src_text))

head_v5 = subprocess.run(["git", "-C", REPO, "show", "HEAD:Natives/AI/AiSettings.m"],
                         capture_output=True, text=True, check=True).stdout.replace("\r\n", "\n")
h_start = head_v5.index("+ (NSString *)defaultSystemPrompt {")
h_marker = head_v5.index("/// ★ Task364：v4 默认提示词全文")
head_v5_method = head_v5[h_start:h_marker]
v5_expect = produced(head_v5_method)

src = io.open(PATH, encoding="utf-8").read().replace("\r\n", "\n")
assert "get_plugin_docs" not in src, "AiSettings.m 已升级过？防重复执行"

# ── ① 【七】章替换 ────────────────────────────────────────────
lines = src.split("\n")
# 注意：迁移注释行（"默认提示词新增【七、插件系统】章"）也含同字样，
# qi 必须锚到提示词字面量行本身（（AmePlugin） + 首字符 " 双重护栏）
qi = next(i for i, l in enumerate(lines)
          if "【七、插件系统（AmePlugin）" in l and l.lstrip().startswith('"'))
bi = next(i for i, l in enumerate(lines) if "【行为纪律】" in l)
assert bi > qi, "章节序异常"

V6_SEVEN = [
    '    "【七、插件系统（AmePlugin）——你可以为启动器写插件，插件能改到启动器整个门面，也是启动器出问题时的自修复通道】\\n"',
    '    "启动器支持 JavaScript 插件（manifest.json + main.js），装好即运行无需重启：效果出现在 设置 → 启动器 → 插件功能 区（主页「插件功能」入口可直达）；设置 → 插件管理 可启停/授权。当用户想给启动器加小功能（自定义统计、一键切换、主题美化、重排版、元素拖拽、界面修复、自动化提醒、JIT/游戏启动辅助等）时，主动提出可以用插件实现。\\n"',
    '    "1. create_plugin 参数：id（小写字母/数字/._-，3-64 字符，全局唯一）、name（显示名）、description（说明）、permissions（可选数组）、code（main.js 全文：纯 JS、无 require/import、顶层用 (function(){...})(); 包裹、≤200KB）、overwrite（覆盖同名插件）。\\n"',
    '    "2. 权限共 20 项：events / ui.dialog / ui.rows / ui.theme† / ui.views† / settings.read / settings.write† / renderer.read / renderer.write† / profile.read / profile.write† / storage / net† / ui.nav / files.game† / jit.read / jit.write† / game.launch† / logs.read（†=高危：安装后默认拒绝，需用户在 插件管理 → 插件详情页 手动开启；另有 ame.super 总权限=完全接管，同样默认拒绝）。\\n"',
    '    "3. ⚠️ 铁律——调用 create_plugin 之前，必须先调用 get_plugin_docs 工具获取插件全量 API 参考（ame.* 全部 API、主题令牌表、视图操纵与元素拖拽写法、JIT/游戏启动/日志自修复三件套、官方示例件）。API 名与签名一律以该文档为准，绝不允许凭记忆编造——写错一个 API 名，插件就会静默失效。一次会话拉一次即可。\\n"',
    '    "4. 用户问「插件怎么用/插件没效果」时：引导到 设置 → 启动器 → 插件功能 区点按插件贡献的行；功能开关与授权在 插件管理 页。\\n"',
    '    "\\n"',
]
lines[qi:bi] = V6_SEVEN
src = "\n".join(lines)

# ── ② v5 留档插入（defaultSystemPrompt 收尾 } 之后、Task364 留档注释之前）──
close_marker = "\n\n/// ★ Task364：v4 默认提示词全文"
assert close_marker in src
archive = (
    "\n\n/// ★ Task365：v5 默认提示词全文（仅作 v5→v6 迁移逐字比对基线，不对用户\n"
    "///   展示/下发；与 ame364_v4/ame363_v3 留档同口径。v5 与 v6 唯一差异 =\n"
    "///   【七】章全量 API 块移出至 get_plugin_docs 工具（插件提示词独立化\n"
    "///   按需加载，用户拍板\u201c单独开个插件提示词，用户说要生成插件 AI 才会看\n"
    "///   另一个提示词，避免太消耗 token\u201d），基础提示词留 create_plugin 契约\n"
    "///   + 20 项权限行 + 文档铁律；其余章节与 v5 逐字节一致。）\n"
    "+ (NSString *)ame365_v5DefaultSystemPrompt {\n"
    + V5_BODY.rstrip("\n")
    + "\n}"
)
src = src.replace(close_marker, archive + close_marker, 1)

# ── ③ 迁移链 v5→v6 + 版本号 ───────────────────────────────────
final_key = '    [ame267_d setInteger:5 forKey:kSystemPromptVersionKey];'
assert final_key in src
LEG = '''    // ★ Task365：ver 5 → 6——插件提示词独立化（用户拍板"单独开个插件提示词，
    //   用户说要生成插件 AI 才会看另一个提示词，避免太消耗 token"）：【七】章
    //   全量 API 块移出至 get_plugin_docs 工具按需加载，基础提示词瘦身省
    //   token。存量 v5 默认（与 ame365_v5DefaultSystemPrompt 逐字一致 =
    //   用户从未改过）自动删除回落 v6 新默认；用户自定义过的原样保留。
    //   幂等：版本号只写一次。
    if (ame267_saved.length > 0 &&
        [ame267_saved isEqualToString:[self ame365_v5DefaultSystemPrompt]]) {
        [ame267_d removeObjectForKey:kSystemPromptKey];
        NSLog(@"[AiSettings] Task365: v5 default system prompt auto-upgraded to v6 (plugin API docs moved to get_plugin_docs, on-demand loading)");
    } else if (ame267_saved.length > 0 && ame267_ver < 6) {
        NSLog(@"[AiSettings] Task365: custom system prompt preserved (v6 bump, no rewrite)");
    }
    [ame267_d setInteger:6 forKey:kSystemPromptVersionKey];'''
src = src.replace(final_key, LEG, 1)

io.open(PATH, "w", encoding="utf-8", newline="").write(src)

# ── ④ 自证 ────────────────────────────────────────────────────
ok = True
def check(name, cond, detail=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" -- {detail}"))
    ok = ok and cond

arc_start = src.index("+ (NSString *)ame365_v5DefaultSystemPrompt {")
arc_end = src.index("/// ★ Task364：v4 默认提示词全文")
arc_zone = src[arc_start:arc_end]
v6_start = src.index("+ (NSString *)defaultSystemPrompt {")
v6_zone = src[v6_start:src.index("+ (NSString *)ame365_v5DefaultSystemPrompt {")]

check("留档产出串 == git HEAD v5 产出串（逐字节）", produced(arc_zone) == v5_expect,
      f"archive={len(produced(arc_zone))} expect={len(v5_expect)}")
v6p = produced(v6_zone)
check("v6 含 get_plugin_docs 铁律", "get_plugin_docs" in v6p and "铁律" in v6p)
check("v6 权限行 20 项", "共 20 项" in v6p and "jit.write†" in v6p and "game.launch†" in v6p and "logs.read" in v6p)
check("v6 不再内联巨型 API 块（四族令牌/视图操纵已移出）",
      "setThemeToken(色令牌表)" not in v6p and "ame.views.find" not in v6p and "元素拖拽标准写法" not in v6p)
check("v6 create_plugin 契约保留", "create_plugin 参数" in v6p and "(function(){...})();" in v6p)
check("v6 其余章节不动（安装章/行为纪律仍在）",
      "【一、用户想安装 Minecraft 时" in v6p and "【行为纪律】" in v6p)
check("迁移链 v5→v6 支 + 版本号 6", "[ame267_saved isEqualToString:[self ame365_v5DefaultSystemPrompt]]" in src
      and "setInteger:6 forKey:kSystemPromptVersionKey" in src and "setInteger:5 forKey" not in src)
check("v4/v3 留档未受波及", "+ (NSString *)ame364_v4DefaultSystemPrompt {" in src
      and "+ (NSString *)ame328_v2DefaultSystemPrompt {" in src)

sys.exit(0 if ok else 1)
