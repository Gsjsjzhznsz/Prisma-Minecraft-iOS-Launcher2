#!/usr/bin/env python3
# Task333 插件仓库打包器 —— plugin-repo/src/<id>/ → plugin-repo/plugins/<id>.zip
# + plugin-repo/index.json（sha256/size 单一事实源）。
# zip 布局与 AmePluginManager.installFromZip 对齐：manifest.json 在 zip 根
# （与 ame318_zipBuiltinPlugin 的目录打包语义逐字节一致）。
# 官方仓库件（official=true）= 启动器侧首方信任自愈的授权面（与 bundle
# 内置件同信任根：同一 GitHub 仓库、同一发布者）。
import hashlib
import json
import os
import zipfile

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SRC = os.path.join(REPO, 'plugin-repo', 'src')
OUT = os.path.join(REPO, 'plugin-repo', 'plugins')
INDEX = os.path.join(REPO, 'plugin-repo', 'index.json')

def main():
    os.makedirs(OUT, exist_ok=True)
    entries = []
    for pid in sorted(d for d in os.listdir(SRC) if not d.startswith('.')):
        sdir = os.path.join(SRC, pid)
        mpath = os.path.join(sdir, 'manifest.json')
        if not os.path.isfile(mpath):
            print(f'SKIP {pid} (no manifest.json)')
            continue
        manifest = json.load(open(mpath, encoding='utf-8'))
        if manifest.get('id') != pid:
            raise SystemExit(f'FATAL {pid}: manifest id mismatch: {manifest.get("id")}')
        zpath = os.path.join(OUT, f'{pid}.zip')
        names = []
        for root, _dirs, files in os.walk(sdir):
            for f in sorted(files):
                if f.startswith('.'):
                    continue
                abs_p = os.path.join(root, f)
                rel = os.path.relpath(abs_p, sdir).replace(os.sep, '/')
                names.append((abs_p, rel))
        names.sort(key=lambda t: t[1])
        with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
            for abs_p, rel in names:
                z.write(abs_p, rel)
        data = open(zpath, 'rb').read()
        sha = hashlib.sha256(data).hexdigest()
        entries.append({
            'id': pid,
            'name': manifest.get('name', pid),
            'version': manifest.get('version', '0.0.0'),
            'author': manifest.get('author', ''),
            'summary': manifest.get('description', ''),
            'file': f'plugins/{pid}.zip',
            'size': len(data),
            'sha256': sha,
            'official': True,
        })
        print(f'PACK {pid}.zip size={len(data)} sha256={sha[:16]}... version={manifest.get("version")}')
    index = {
        'schema': 1,
        'repo': 'Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2',
        # Task341：updated 动态生成（此前写死 '2026-10-26' 随轮次漂移失真）
        'updated': __import__('datetime').date.today().isoformat(),
        'plugins': entries,
    }
    with open(INDEX, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'INDEX {INDEX} ({len(entries)} plugins)')

if __name__ == '__main__':
    main()
