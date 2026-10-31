#!/usr/bin/env python3
# ame366_facade_smoke.py -- Task 366 门面 JS 语法/接线冒烟（node 实跑）
# 病历：Task332 装机实锤 —— CI node 桩冒烟从不 evaluate 门面源 = 门面侧断链
# CI 不可见。本冒烟把 ame317_facadeSource 的字面量拼接提取为真 JS，在 node
# 里以 Proxy 桩执行，逐一断言 21 命名空间 + 全部成员 + 顶层函数可调用。
# Task366 实战战果：ame.net 未建对象点赋值（TypeError 必炸全门面）+
# ame.dialog 对象字面量覆盖顶层函数（四内置件兼容性回归）双雷均由此拦下。
import io, re, subprocess, sys

REPO = "/home/z/my-project/repo-prisma2"
rt = io.open(REPO + "/Natives/AmePluginRuntime.m", encoding="utf-8").read()
start = rt.index("static NSString *ame317_facadeSource(void)")
end = rt.index("#pragma mark - 装载 / 卸载", start)
zone = rt[start:end]
zone = zone[zone.index("return"):]

out_lines = []
for line in zone.splitlines():
    in_str = False; cut = len(line); i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i-1] != "\\"):
            in_str = not in_str
        elif c == "/" and not in_str and i + 1 < len(line) and line[i+1] == "/":
            cut = i; break
        i += 1
    out_lines.append(line[:cut])
frags = re.findall(r'"((?:[^"\\]|\\.)*)"', "\n".join(out_lines))
js = "".join(f.replace('\\"', '"').replace("\\\\", "\\") for f in frags)
open("/tmp/facade_smoke.js", "w", encoding="utf-8").write(js)

test = r"""
const raw = new Proxy({}, { get: (t, k) => (...a) => ({k}) });
global.ameRaw = raw;
const fs = require('fs');
eval(fs.readFileSync('/tmp/facade_smoke.js', 'utf8'));
const ns = ['app','views','notify','clipboard','theme','settings','profiles','game','jit','logs','mods','shaders','worlds','accounts','downloads','ai','controls','fs','crash','net','storage'];
let missing = ns.filter(n => typeof ame[n] !== 'object');
if (typeof ame.dialog !== 'function') missing.push('dialog(not-func)');
['prompt','sheet','dismissAll'].forEach(m => { if (typeof ame.dialog[m] !== 'function') missing.push('dialog.' + m); });
const fns = ['log','toast','on','off','addLauncherRow','setThemeToken','setThemeShape','setThemeLayout','setThemeStructure','getPref','setPref','getRenderer','setRenderer','getProfiles','fetch','openPage','createProfile','deleteProfile','listFiles','readFile','writeFile','removeFile','launchGame','readLog'];
missing = missing.concat(fns.filter(f => typeof ame[f] !== 'function'));
const members = ['views.find','views.apply','views.on','views.reset','views.describe','views.children','views.parent','views.tap','views.scroll','views.animate','views.applyStyle','views.readStyle','views.batch','views.release','jit.state','jit.enable','jit.setScheme','jit.schemes','notify.send','notify.haptic','notify.share','notify.openURL','notify.copy','clipboard.get','clipboard.set','theme.getTokens','theme.setToken','settings.keys','settings.getMulti','settings.setMulti','settings.remove','settings.describe','profiles.list','profiles.current','profiles.select','profiles.describe','profiles.create','profiles.remove','profiles.rename','profiles.getKey','profiles.setKey','profiles.getServerIp','profiles.setServerIp','game.state','game.lastExit','game.memory','game.setMemory','game.controlLayout','game.setControlLayout','logs.read','logs.list','logs.search','mods.list','mods.toggle','mods.remove','mods.folder','shaders.list','shaders.toggle','shaders.remove','worlds.list','worlds.describe','worlds.rename','worlds.remove','accounts.list','accounts.current','downloads.history','ai.ask','ai.status','controls.list','controls.read','controls.write','controls.remove','fs.list','fs.read','fs.write','fs.remove','fs.exists','fs.mkdir','fs.move','fs.copy','fs.size','crash.analyzeLatest','crash.list','net.download','storage.get','storage.set','storage.remove','storage.keys'];
missing = missing.concat(members.filter(p => { const [a,b] = p.split('.'); return typeof ame[a] !== 'object' || typeof ame[a][b] !== 'function'; }));
console.log(missing.length === 0 ? 'FACADE SMOKE OK (' + ns.length + ' ns + ' + members.length + ' ns-members + ' + fns.length + ' top-level + dialog dual-form)' : 'MISSING: ' + missing.join(','));
process.exit(missing.length === 0 ? 0 : 1);
"""
open("/tmp/facade_smoke_test.js", "w", encoding="utf-8").write(test)
r = subprocess.run(["node", "/tmp/facade_smoke_test.js"], capture_output=True, text=True)
print(r.stdout.strip())
if r.returncode != 0:
    print("STDERR:", r.stderr[:600])
    sys.exit(1)
