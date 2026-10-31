#!/usr/bin/env python3
# ame364_prompt_upgrade.py -- Task364 系统提示词 v4→v5 原子升级脚本
# ① 把现役 defaultSystemPrompt（v4）方法体逐字节提取，克隆为
#    ame364_v4DefaultSystemPrompt 留档（迁移比对基线，ame363 同口径）
# ② v5 三处修订：【七】章视图操纵家族 + 权限 14→15 + 自修复兜底句
# ③ 迁移链：ver 4→5（v4 默认逐字一致即自动升级，自定义保留）
# ④ 自证：留档方法体与 git HEAD 的 defaultSystemPrompt 逐字节一致
import io, subprocess, sys

P = "Natives/AI/AiSettings.m"

def read(p):
    with io.open(p, encoding="utf-8", newline="") as f:
        return f.read()

def write(p, t):
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(t)

text = read(P)
head = subprocess.run(["git", "show", f"HEAD:{P}"], capture_output=True, text=True).stdout
assert head, "git show failed"

def extract_default(src):
    """提取 defaultSystemPrompt 完整方法（从方法签名到下一段 /// 注释前）"""
    start = src.index("+ (NSString *)defaultSystemPrompt {")
    end = src.index("/// ★ Task363：v3 默认提示词全文", start)
    return src[start:end].rstrip() + "\n"

v4_body_head = extract_default(head)
v4_body_now = extract_default(text)
assert v4_body_head == v4_body_now, "工作区 defaultSystemPrompt 与 HEAD 不一致，中止"

# ① 构造留档方法（改名 + Task364 注释头）
archive = (
    "/// ★ Task364：v4 默认提示词全文（仅作 v4→v5 迁移逐字比对基线，不对用户\n"
    "///   展示/下发；与 ame363_v3DefaultSystemPrompt 同款留档口径。正文与 v5\n"
    "///   唯三差异 = 【七】章权限 14→15 项 + 视图操纵家族 bullet + 演示件\n"
    "///   四件→五件句）。\n"
    + v4_body_head.replace(
        "+ (NSString *)defaultSystemPrompt {",
        "+ (NSString *)ame364_v4DefaultSystemPrompt {", 1)
)

# 插入位置：v3 留档注释块之前
anchor = "/// ★ Task363：v3 默认提示词全文"
idx = text.index(anchor)
text = text[:idx] + archive + "\n" + text[idx:]

# ② E1：【七】章首段——演示件四件→五件 + 视图操纵兜底能力句
e1_old = "插件仓库内置四件示例（启动统计/Modrinth 热门榜/渲染器快切/日落主题包），其中 fluent-ui 是主题类插件的全家族参考实现。\\n"
e1_new = ("插件仓库内置五件示例（启动统计/Modrinth 热门榜/渲染器快切/日落主题包/元素拖拽），"
          "其中 fluent-ui 是主题类插件的全家族参考实现，元素拖拽是视图操纵家族的参考实现。\\n"
          "    \\\"插件能改到启动器的整个门面\\\"落在两根支柱上：主题四家族改观感，视图操纵家族（下第 3 条）改结构——"
          "直接查询并操纵界面上的任意原生元素（移动/缩放/隐藏/改文字/挂手势）。这也是启动器卡壳时的自修复通道："
          "界面遮挡/错位/按钮点不到等启动器自身小毛病，可以直接写一个 ui.views 插件现场修复，不必等启动器更新。\\n")
assert e1_old in text, "E1 anchor not found"
text = text.replace(e1_old, e1_new, 1)

# ③ E2：权限行 14→15 + ui.views†
e2_old = "2. 权限（permissions 数组，共 14 项）：events / ui.dialog / ui.rows / ui.theme† / settings.read"
e2_new = "2. 权限（permissions 数组，共 15 项）：events / ui.dialog / ui.rows / ui.theme† / ui.views† / settings.read"
assert e2_old in text, "E2 anchor not found"
text = text.replace(e2_old, e2_new, 1)

# ④ E3：主题四家族后新增视图操纵 bullet
e3_old = "    \"     - ame.setThemeStructure({shellLayout:'topbar'|'navigationview'})：壳层导航骨架换蓝图（顶栏制 ↔ 左窗格制）。\\n\"\n"
assert e3_old in text, "E3 anchor not found"
e3_add = (
    "    \"   · 视图操纵（ui.views†）：ame.views.find({cls?,text?,ident?,tag?,limit?}) → [{handle,cls,text,frame:{x,y,w,h},alpha,hidden,enabled}]（cls/text 子串匹配；handle 本次装载会话内有效）。\\n\"\n"
    "    \"     - ame.views.apply(handle,{x?,y?,w?,h?,alpha?,hidden?,cornerRadius?,text?,bg?,enabled?})：移动/缩放/隐藏/改文字/染色（bg=#RRGGBB/#RRGGBBAA；坐标=父视图坐标 pt，数值有钳制）。\\n\"\n"
    "    \"     - ame.views.on(handle,'tap'|'pan'|'longpress'|'swipe',function(ev){})：挂手势。pan 事件 ev={state:'began/changed/ended/cancelled',dx,dy,tx,ty,frame:{x,y,w,h},x,y}，dx/dy=距上次事件位移、tx/ty=自按下累计位移（窗口坐标系，零漂移）。\\n\"\n"
    "    \"     - ame.views.reset(handle)：还原本插件对该元素的全部改动并摘除本插件手势；插件停用/卸载时自动全部还原。游戏渲染面子树（SurfaceView/GameSurfaceView/ScrollableSurfaceView）受保护禁查改。\\n\"\n"
    "    \"     - 元素拖拽标准写法：var h=ame.views.find({text:'启动'})[0].handle; var st=null; ame.views.on(h,'pan',function(ev){if(ev.state==='began'){st={x:ev.frame.x,y:ev.frame.y};}else if(ev.state==='changed'){ame.views.apply(h,{x:st.x+ev.tx,y:st.y+ev.ty});}});\\n\"\n"
    "    \"     - 布局改动建议用 ame.storage 持久化 {cls,text}→偏移 并在 app.launch 事件重放，做成随启动生效的布局插件。\\n\"\n"
)
text = text.replace(e3_old, e3_old + e3_add, 1)

# ⑤ 迁移链 ver 4→5
m_old = ("    if (ame267_saved.length > 0 &&\n"
         "        [ame267_saved isEqualToString:[self ame363_v3DefaultSystemPrompt]]) {\n"
         "        [ame267_d removeObjectForKey:kSystemPromptKey];\n"
         "        NSLog(@\"[AiSettings] Task363: v3 default system prompt auto-upgraded to v4 (plugin API surface fully documented)\");\n"
         "    } else if (ame267_saved.length > 0 && ame267_ver < 4) {\n"
         "        NSLog(@\"[AiSettings] Task363: custom system prompt preserved (v4 bump, no rewrite)\");\n"
         "    }\n"
         "    [ame267_d setInteger:4 forKey:kSystemPromptVersionKey];\n")
assert m_old in text, "migration anchor not found"
m_new = ("    if (ame267_saved.length > 0 &&\n"
         "        [ame267_saved isEqualToString:[self ame363_v3DefaultSystemPrompt]]) {\n"
         "        [ame267_d removeObjectForKey:kSystemPromptKey];\n"
         "        NSLog(@\"[AiSettings] Task363: v3 default system prompt auto-upgraded to v4 (plugin API surface fully documented)\");\n"
         "    } else if (ame267_saved.length > 0 && ame267_ver < 4) {\n"
         "        NSLog(@\"[AiSettings] Task363: custom system prompt preserved (v4 bump, no rewrite)\");\n"
         "    }\n"
         "    // ★ Task364：ver 4 → 5——【七、插件系统】章新增视图操纵家族（ui.views†：\n"
         "    //   ame.views.find/apply/on/reset + 元素拖拽标准写法 + 自修复通道），\n"
         "    //   权限面 14→15 项。存量 v4 默认（与 ame364_v4DefaultSystemPrompt\n"
         "    //   逐字一致 = 用户从未改过）自动删除回落 v5 新默认；用户自定义过的\n"
         "    //   原样保留。幂等：版本号只写一次。\n"
         "    if (ame267_saved.length > 0 &&\n"
         "        [ame267_saved isEqualToString:[self ame364_v4DefaultSystemPrompt]]) {\n"
         "        [ame267_d removeObjectForKey:kSystemPromptKey];\n"
         "        NSLog(@\"[AiSettings] Task364: v4 default system prompt auto-upgraded to v5 (ui.views view-manipulation family documented)\");\n"
         "    } else if (ame267_saved.length > 0 && ame267_ver < 5) {\n"
         "        NSLog(@\"[AiSettings] Task364: custom system prompt preserved (v5 bump, no rewrite)\");\n"
         "    }\n"
         "    [ame267_d setInteger:5 forKey:kSystemPromptVersionKey];\n")
text = text.replace(m_old, m_new, 1)

write(P, text)

# ⑥ 逐字节自证：新文件中留档方法体 == HEAD defaultSystemPrompt 方法体
new_text = read(P)
start = new_text.index("+ (NSString *)ame364_v4DefaultSystemPrompt {")
end = new_text.index("/// ★ Task363：v3 默认提示词全文", start)
archived = new_text[start:end].rstrip() + "\n"
archived_norm = archived.replace("+ (NSString *)ame364_v4DefaultSystemPrompt {",
                                 "+ (NSString *)defaultSystemPrompt {", 1)
assert archived_norm == v4_body_head, "留档与 HEAD v4 逐字节不一致！"
print("OK: v4 archive byte-identical to HEAD defaultSystemPrompt")
print("OK: v5 edits applied (E1 intro / E2 perms 15 / E3 views bullet / migration 4->5)")
