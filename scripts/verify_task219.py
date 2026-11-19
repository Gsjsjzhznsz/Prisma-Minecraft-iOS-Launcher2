import re
#!/usr/bin/env python3
# verify_task219.py -- Task219 eleven-item round verifier.
# Evidence base: 6cd2cbfb device logs (latestlog.old.txt VirGL session +
# latestlog.txt ANGLE 26.2 FO session), both on the 2f82e61 build (run 622).
import json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.abspath(__file__)) + "/.."
os.chdir(REPO)
PASSED, FAILED = 0, []

def rd(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

def check(name, ok, detail=""):
    global PASSED
    print(("PASS " if ok else "FAIL ") + name + ((" -- " + detail) if (detail and not ok) else ""))
    if ok:
        PASSED += 1
    else:
        FAILED.append(name)

vs = rd("Natives/ctxbridges/virgl_server.m")
eb = rd("Natives/egl_bridge.m")
tg = rd("Natives/external/gl4es/tinygl4angle.c")
# ★Task440 退役重锚：Welcome 向导链 Task436 A3 断链后成死代码，本体本轮物理删除
#   ——原 C/D/E 三段（向导布局/LC 检测/关于页收尾）断言随页离场，收敛为退役断言
wv_retired = (not os.path.exists("Natives/WelcomeViewController.m")
              and not os.path.exists("Natives/WelcomeViewController.h"))
ab = rd("Natives/AboutViewController.m")
dt = rd("Natives/DataTransferService.m")
# ★Task440 退役重锚：ProfileSettings 本体删除——G 段 TC/Sodium 组件安装链
#   （唯一宿主即旧页）随页退役，收敛为退役断言（ZL2 下载页资源轨接棒）
ps_retired = not os.path.exists("Natives/ProfileSettingsViewController.m")
ms = rd("Natives/ModService.m")
mh = rd("Natives/ModService.h")
# ★Task436 退役批次二：ModsManagerViewController 已物理删除（批次二③五管理页整链退役），mm 读取摘除（Task432「退役门不复活」判例同款）
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
cml = rd("Natives/CMakeLists.txt")
ann = json.load(open("announcements.json", encoding="utf-8"))["announcements"]

print("== A. VirGL 崩溃根治（①：vtest 引导失败 → guest abort） ==")
check("A1 诊断盲区修复：virgl_server.m import utils.h（NSLog 宏重定义走 latestlog 管道）",
      '#import "utils.h"' in vs
      and "check [VirGL] logs above" not in eb)
check("A2 socket 路径缩短 + pid 唯一化（旧 $POJAV_HOME/.virgl_test ~170 字节超 sun_path 104 上限）",
      "ame219_compute_socket_path" in vs
      and "sun_path" in vs and "ame_virgl_%d.sock" in vs
      and '"%s/.virgl_test"' not in vs)
check("A3 dlopen 候选链（libEGL + libvtestserver，@executable_path 优先——LiveContainer 的 @rpath 解析落宿主）",
      "ame219_dlopen_first" in vs
      and '"@executable_path/Frameworks/libEGL.framework/libEGL"' in vs
      and '"@executable_path/Frameworks/" AME_VIRGL_VTEST_SERVER_LIB' in vs)
check("A4 eglChooseConfig 回退链（ES3_BIT 优先 → ES2_BIT 兜底，逐档日志）",
      "ame219_configOk" in vs and "EGL_OPENGL_ES3_BIT" in vs
      and vs.count("eglChooseConfig pass#") >= 1)
check("A5 引导后验证 = socket 文件 + S_ISSOCK，且【无 connect 探针】（单发服务名额保护）",
      "S_ISSOCK" in vs and "post-bootstrap check" in vs
      and "connect(ame219_probe" not in vs)
check("A6 egl_bridge 引导失败 → Zink 改道（guest 加载前换 AMETHYST_RENDERER/GALLIUM_DRIVER，abort 不再可达）",
      "diverting renderer to Zink" in eb
      and 'setenv("AMETHYST_RENDERER", RENDERER_NAME_VK_ZINK, 1)' in eb
      and 'setenv("GALLIUM_DRIVER", "zink", 1)' in eb)
check("A7 回退弹窗走 ame219.virgl.fallback 键（l10n 四语言在位）",
      'localize(@"ame219.virgl.fallback.title"' in eb
      and all('ame219.virgl.fallback.title' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
              for l in ["en", "zh-Hans", "zh-Hant", "zh-CN"]))

print("== B. ANGLE 非 26.3 黑屏根治（⑦：桌面 GLSL 直传无 ES300 转换） ==")
_tg_code = re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", tg, flags=re.S))
check("B1 桌面头重写块在位（#version 300 es + 精度组；Task223 起移除 image 三行）",
      "Task219" in _tg_code and "kAme219EsHead" in _tg_code
      and '"#version 300 es\\n"' in _tg_code
      and "precision highp float;" in _tg_code
      and "precision highp usampler3D;" in _tg_code
      and "precision highp image2D;" not in _tg_code)
check("B2 触发门 = 桌面 >=130（26.2 的 #version 330 命中；ES 源不受影响）",
      "ame219_ver >= 130" in tg)
check("B3 重写后走 ES 直传路径（早退分支语义，跳过 gl4es 时代 outColor0/扩展注入）",
      "gles_glShaderSource(shader, 1, (const GLchar * const *)(&ame219_es), NULL)" in tg)
check("B4 取证日志锚点（Task219 desktop->ES300 head rewrite）",
      "[tinygl4angle] Task219 desktop->ES300 head rewrite" in tg)
check("B5 Task183 漏网监测器保留（回归哨兵不退役）",
      "Task183 DESKTOP source reached GLES upload" in tg)
check("B6 旧 1xx 转换路径保留（低版本形态行为不变）",
      "converted[9] == '1'" in tg)

print("== C/D/E. Welcome 向导链退役（★Task440 终局：Task436 A3 断链 + 本体删除） ==")
check("C+D+E Welcome 本体缺席 + 旧向导链断言收敛",
      wv_retired
      and not os.path.exists("Natives/WelcomeViewController.h"))

print("== F. 数据导出增强（⑨） ==")
check("F1 导出前预检（文件数 + 总量 + 预检日志）",
      "ame219_files" in dt and "export preflight" in dt)
check("F2 压缩等级三选（UZK None/Default/Best 透传）",
      "ame219_showExportLevelSheetWithFiles" in dt
      and "UZKCompressionMethodNone" in dt and "UZKCompressionMethodDefault" in dt
      and "UZKCompressionMethodBest" in dt
      and "compressionMethod:method" in dt)
check("F3 进度条 + 文件级详情（UIProgressView + i/N + 当前文件 + 已写字节，150ms 节流）",
      "UIProgressView" in dt and "ame219.export.progress_file" in dt
      and "timeIntervalSinceDate:ame219_lastUi] > 0.15" in dt)
check("F4 导出目录选择保留（Files 落点选择器 + move 语义）",
      "initForExportingURLs" in dt and "asCopy:NO" in dt)
check("F5 跳过项不递归（latestlog/hs_err 目录整棵剪枝）",
      "skipDescendants" in dt)
check("F6 空数据兜底（ame219.export.empty）",
      'localize(@"ame219.export.empty"' in dt)

print("== G. TC/Sodium 组件安装链退役（★Task440 终局：唯一宿主 ProfileSettings 随页离场） ==")
check("G 全段收敛：旧页缺席（组件安装功能由 ZL2 下载页资源轨接棒，component.* 键四表按家法留档）",
      ps_retired)

print("== H. 版本隔离自动识别（⑪） ==")
check("H1 隔离优先解析器（下载 + 扫描共用；隔离目录缺即建，不落共享目录）",
      "ame219_isolationFirstModsFolderForProfile" in ms
      and ms.count("ame219_isolationFirstModsFolderForProfile") >= 3)
check("H2 downloadMod 与 scanMods 都已切到隔离优先",
      all(x in ms for x in re.findall(r"NSString \*modsFolder = \[self (ame219_isolationFirst\w+)", ms))
      and "[self existingModsFolderForProfile:profileName];" not in ms.split("// ---------- 下载")[1].split("// ---------- PLDownloadClient")[0])
check("H3 隔离态类方法 + 头文件声明（ModsManager 徽标数据源）",
      "+ (NSInteger)ame219_isolationStateForProfile" in mh
      and "+ (NSInteger)ame219_isolationStateForProfile" in ms)
# ★Task436 H4 摘除：模组管理页（ModsManagerViewController）已随退役批次二物理删除，隔离徽标随页退役；
# 隔离态类方法 H3（ModService 侧）继续在位承载该语义（退役不复活判例，编号留空洞）。

print("== I. VGPU 更名（④） ==")
for lang, expect in [("en", "VGPU (≤1.17)"), ("zh-Hans", "VGPU（≤1.17）"),
                     ("zh-Hant", "VGPU（≤1.17）"), ("zh-CN", "VGPU（≤1.17）")]:
    check(f"I-{lang} VGPU 显示名 = {expect}",
          f'= "{expect}";' in rd(f"Natives/resources/{lang}.lproj/Localizable.strings"))

print("== J. l10n + 公告 ==")
for lang in ["en", "zh-Hans", "zh-Hant", "zh-CN"]:
    keys = set(re.findall(r'^"([^"]+)"\s*=',
                          rd(f"Natives/resources/{lang}.lproj/Localizable.strings"), re.M))
    # ★ Task365 重锚：Task343 3319 → …351 +2 = 3329 → 364 +2（ui.views 权限 name/desc）= 3331 → 365 +8（jit.read/jit.write/game.launch/logs.read 权限 name/desc×4）= 3339
    # ★ Task367 重锚：Task366 权限 20→33 组（+13 组 name/desc×4 表 = 66 键）+ ame317.common.cancel 补键 = 3366（task191 同步锚）
    # ★ Task369 重锚：i18n 恢复——451 处硬编码中文 UI 字符串改写 localize()（19 文件 393 站点），四表新增 336 个 ame369.* 键（复用 ame193.misc.1/3 两键不入表）= 3702
    # ★ Task419 补锚（继承欠账实测：Task418 头 75/81，+13 键增量四表同步无失衡（task191 同锚 3715））= 3715
    # ★ Task424 重锚：+8 键增量四表同步（ame424 姿态四段/复位/光位圆盘/亮度/自定义提示 = task191 同锚 3723）= 3723
    # ★ Task425 重锚：+9 键增量四表同步（ame425 gear/panel.title/done/contrast/scale/bg 四世界 = task191 同锚 3732）= 3732
    # ★ Task426 重锚：+9 键增量四表同步（ame426 dial.caption/time 四态/weather 三段 = task191 同锚 3741）= 3741
    # ★ Task427 重锚：+5 键增量四表同步（ame427 fs 双态/占位/维度固定光照/姿态 a11y = task191 同锚 3746）= 3746
    # ★ Task428 重锚：+79 键增量四表同步（PDF v5 P0 批次：聚合搜索 4/完整性校验 17/关于页+设置行 46/节日彩蛋与 logshare 上传 11/游戏内菜单入口 1 = task191 同锚 3825）= 3825
    # ★ Task431 重锚：+2 = 4099 → ★ Task432 重锚：+72 = 4171（第 8 期整改批四工位：导入文件夹 6/布局卡 25/主题拆行+色板 5/许可证 2/修改版本页 20/数据包子页 9/SearchId 闭环 3/设置尾行 2） → ★ Task434 重锚：+2 = 4173（A1 应用图标导入 launch.ui.icon.import{,.subtitle} 四表同步） → ★ Task436 重锚：+58 = 4231（批次二/三四工位：SC 编辑器闭环 40 / SD 取色器+陀螺仪浮层 13 / SB 版本列表新页+收藏筛选 5） → ★ Task441 重锚：+40 = 4271（编辑器五件 ame441.* 四表同步） → ★ Task444 重锚：+1 = 4348（ame444.vers.derived_toggle 五表同步） → ★ Task449 重锚：+76 = 4348（清扫+折叠组名） → ★ Task451 重锚：+1 = 4349（i18n_str_ame451_preflight 54 表同步）
    check(f"J-{lang} 唯一键 4349（★Task436 重锚 4231 → ★Task441 编辑器五件 +40 = 4271 → ★Task444 派生展开钮 +1 = 4272 → ★Task449 硬编码清扫+折叠组名 +76 = 4348 → ★Task451 JIT26 预检指引键 +1 = 4349）", len(keys) == 4349, f"got {len(keys)}")
check("J-公告 6 条（★Task419 补锚：repo2 实态——Task413-r3 起 6 条，region-notice 为 repo1 专有从未入 repo2；pin 语义保持）",
      len(ann) == 6
      and any(a["id"] == "server-recommend-2026-09-24" for a in ann)
      and any(a["id"] == "v6-0-0-release-2026-09-21" for a in ann))
check("J-公告内容覆盖本轮主题（★Task419 补锚：服务器推荐/6.5.0 修复/v6.0.0 发布；服务地区条目 repo2 无，不虚构）",
      len(ann) >= 5 and any("mysv.dpdns.org" in a["content"] for a in ann)
      and any("6.5.0" in a["title"] for a in ann)
      and any("v6.0.0" in a["title"] for a in ann))
check("J-JSON 可解析 + id 唯一",
      len(set(a["id"] for a in ann)) == len(ann))

print("== K. 身份与基线 ==")
plist = rd("Natives/Info.plist")
check("K1 身份已迁移（Task259 com.prisma-devs.prisma——262 重锚）",
      "<string>com.prisma-devs.prisma</string>" in plist)
check("K2 REVISION 保持 22 + Task219 附录在位（无 identity 变更不 bump）",
      "#define REVISION 22" in vh and "Task 219, no bump" in vh)
mk = open("Makefile", "rb").read()
check("K3 Makefile TAB 基线 808（Task315 同步重锚：6.5.5 终态实测 808——Task300 jit_helper/Task309 退役后净变化，字节级无损已验）",
      sum(1 for line in mk.split(b"\n") if line.startswith(b"\t")) == 808)
yml = open(".github/workflows/development.yml", "rb").read()
check("K4 工作流 CRLF 完整", yml.count(b"\r\n") == yml.count(b"\n"))

print("== L. 括号平衡（本轮 10 个改动源文件，状态机口径） ==")
def balance(path):
    src = rd(path)
    stack, pairs = [], {")": "(", "]": "[", "}": "{"}
    i, n, state = 0, len(src), "code"
    while i < n:
        c = src[i]; nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/": state = "lc"; i += 2; continue
            if c == "/" and nxt == "*": state = "bc"; i += 2; continue
            if c == '"': state = "st"; i += 1; continue
            if c == "'": state = "ch"; i += 1; continue
            if c in "([{": stack.append(c)
            elif c in ")]}":
                if not stack or stack[-1] != pairs[c]: return False
                stack.pop()
        elif state == "lc":
            if c == "\n": state = "code"
        elif state == "bc":
            if c == "*" and nxt == "/": state = "code"; i += 2; continue
        elif state == "st":
            if c == "\\": i += 2; continue
            if c == '"': state = "code"
        elif state == "ch":
            if c == "\\": i += 2; continue
            if c == "'": state = "code"
        i += 1
    return not stack
for p in ["Natives/ctxbridges/virgl_server.m", "Natives/egl_bridge.m",
          "Natives/external/gl4es/tinygl4angle.c",
          "Natives/AboutViewController.m", "Natives/DataTransferService.m",
          # ★Task440：Welcome/ProfileSettings 随死代码六件退役摘括号审计
          "Natives/ModService.m",
          "Natives/external/MobileGlues/MobileGlues-cpp/version.h"]:
    check(f"L-balance {p.split('/')[-1]}", balance(p))

print("== M. 舰队重锚（计数与尾窗顺延） ==")
spot = {
    # ★Task441 重锚：218 公告区随 A1 收编瘦身 43→6（pin 头锚 + task223 尾锚），
    #   向导六步/EnvJitStep/2715 旧锚随退役降级摘除——M1 锚随新现实重锚。
    "scripts/verify_task218.py": ["len(ann) == 6", "ann[0].get(\"pin\") is True",
                                  'ann[-1]["id"].startswith("task223")'],
    "scripts/verify_task217.py": ["len(ann) == 43", "task219-virgl-angle-welcome-rebuild"],
    "scripts/verify_task216.py": ["== 43", "ids[-6] == \"task216-ui"],
    "scripts/verify_task214.py": ["ids[-6] == \"task216-ui", "'== 43' in v207"],
    "scripts/verify_task213.py": ["'== 43' in v207"],
    "scripts/verify_task211.py": ["== 43"],
    "scripts/verify_task210.py": ["== 43"],
    "scripts/verify_task206.py": ["ann[-7][\"id\"] == \"task206-nggl4es"],
    "scripts/verify_task207.py": ["ann[-5][\"id\"] == \"task217-download-fixes"],
}
g_ok, g_detail = True, []
for path, needles in spot.items():
    src = rd(path)
    for n in needles:
        if n not in src:
            g_ok = False
            g_detail.append(f"{path} missing {n!r}")
check("M1 重锚族抽查（9 验证器：计数 41 / 尾窗顺延 / 向导六步）", g_ok, "; ".join(g_detail[:3]))
check("M2 舰队 2520 旧值扫荡干净（除 task219 自身）",
      all("2482" not in rd(f) for f in
          ["scripts/verify_task217.py", "scripts/verify_task216.py", "scripts/verify_task214.py",
           "scripts/verify_task211.py", "scripts/verify_task210.py", "scripts/verify_task206.py"])
      and all("2482" not in rd("scripts/" + f) for f in os.listdir("scripts")
              if f.startswith("verify_task") and f != "verify_task219.py"))

print("== N. 上游死亡救治：khanhduytran0 两个子模块树内置入（CI 37188369741 根因） ==")
# 病历：run 37188369741（0a54f2f4）与 37181806916（6cd2cbfb，早于本提交）都在
# "Checkout repository submodules" 步骤死于 "could not read Username"——
# khanhduytran0 账号已删（user API 404），DBNumberedSlider 与 fishhook 两个
# 子模块上游 404。救治：两棵钉住树（4eddc68b / 27bedb2ab）经各自 fork 网络
# （immago/DBNumberedSlider、facebook/fishhook——fork 网络共享对象存储，
# codeload 对钉住 SHA 仍返回 200）完整取回，去子模块化后树内置入。
gm = rd(".gitmodules")
check("N1 .gitmodules 不再引用已死上游 khanhduytran0",
      "khanhduytran0" not in gm
      and 'submodule "Natives/external/fishhook"' not in gm
      and 'submodule "Natives/external/DBNumberedSlider"' not in gm
      and gm.count("[submodule") == 6)
check("N2 fishhook 树内在位（fishhook.c/h + LICENSE，路径与 CMakeLists 消费点一致）",
      os.path.exists("Natives/external/fishhook/fishhook.c")
      and os.path.exists("Natives/external/fishhook/fishhook.h")
      and os.path.exists("Natives/external/fishhook/LICENSE")
      and "external/fishhook/fishhook.c" in cml)
check("N3 恢复的是 fork 版内容（arm64e ptrauth __auth_got 重签名补丁在位——facebook 上游没有这段）",
      "ptrauth_strip" in rd("Natives/external/fishhook/fishhook.c")
      and "__auth_got" in rd("Natives/external/fishhook/fishhook.c"))
check("N4 DBNumberedSlider 树内在位（Classes/DBNumberedSlider.m + LICENSE）",
      os.path.exists("Natives/external/DBNumberedSlider/Classes/DBNumberedSlider.m")
      and os.path.exists("Natives/external/DBNumberedSlider/Classes/DBNumberedSlider.h")
      and os.path.exists("Natives/external/DBNumberedSlider/LICENSE")
      and "external/DBNumberedSlider/Classes/DBNumberedSlider.m" in cml)
check("N5 消费方零改动（main_hook.m include 路径 + CMakeLists include 目录原样）",
      '#include "external/fishhook/fishhook.h"' in rd("Natives/main_hook.m")
      and '"external/DBNumberedSlider/Classes"' in cml
      and '"external/fishhook"' in cml)
gitlinks = subprocess.run(["git", "ls-files", "-s"], capture_output=True, text=True).stdout
check("N6 两处 gitlink（160000）已除名，树内为普通文件",
      "160000" not in "\n".join(l for l in gitlinks.splitlines()
                                if "external/fishhook" in l or "DBNumberedSlider" in l))

print()
print("=" * 40)
print(f"verify_task219: {PASSED} passed, {len(FAILED)} failed")
if FAILED:
    print("FAILED:", FAILED)
    sys.exit(1)
print("ALL GREEN")
