#!/usr/bin/env python3
# ci_fetch_artifacts_415.py -- 装机包唯一命名归档下载（Task410 判例重建：GitHub
# artifacts 端点 302 → Azure 签名 URL；urllib 自动跟随会带上 Bearer = 401，
# 须 NoRedirect 拆两段、对 Location 裸下）+ DNS 瞬断重试。
# 用法: python3 ci_fetch_artifacts_415.py <run_id> <outdir_prefix>
#       例: python3 ci_fetch_artifacts_415.py 42664451622 Task414
import json, os, sys, time, urllib.request, urllib.error

REPO = "Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2"
TOKEN = open("/home/z/my-project/.gh_token").read().strip()
OUT_ROOT = "/home/z/my-project/download"

def api(url):
    req = urllib.request.Request(url, headers={
        "Authorization": "token " + TOKEN,
        "Accept": "application/vnd.github+json",
        "User-Agent": "ci-fetch-415",
    })
    return urllib.request.urlopen(req, timeout=60).read()

def fetch_artifact(artifact_id, dest, tries=5):
    api_url = "https://api.github.com/repos/%s/actions/artifacts/%d/zip" % (REPO, artifact_id)
    for attempt in range(tries):
        try:
            req = urllib.request.Request(api_url, headers={
                "Authorization": "token " + TOKEN, "User-Agent": "ci-fetch-415"})
            opener = urllib.request.build_opener(_NoRedirect)
            try:
                resp = opener.open(req, timeout=60)
                loc = None
            except urllib.error.HTTPError as e:
                if e.code in (301, 302, 303, 307):
                    loc = e.headers.get("Location")
                else:
                    raise
            if not loc:
                raise RuntimeError("no redirect Location (unexpected 200 with auth)")
            r2 = urllib.request.Request(loc, headers={"User-Agent": "ci-fetch-415"})  # 裸下：不带鉴权
            data = urllib.request.urlopen(r2, timeout=600).read()
            with open(dest, "wb") as f:
                f.write(data)
            return len(data)
        except Exception as exc:
            print("  retry %d for %s: %s" % (attempt + 1, os.path.basename(dest), exc))
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("artifact %d download failed after retries" % artifact_id)

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    run_id = sys.argv[1]
    tag = sys.argv[2]
    outdir = os.path.join(OUT_ROOT, "%s_build_%s" % (tag, run_id))
    os.makedirs(outdir, exist_ok=True)
    runs = json.loads(api("https://api.github.com/repos/%s/actions/runs/%s" % (REPO, run_id)))
    print("run %s conclusion=%s head=%s" % (run_id, runs.get("conclusion"), runs.get("head_sha", "")[:8]))
    arts = json.loads(api("https://api.github.com/repos/%s/actions/runs/%s/artifacts?per_page=100" % (REPO, run_id)))["artifacts"]
    for a in arts:
        name = a["name"]
        ext = ".zip" if name.endswith(".zip") else ""
        dest = os.path.join(outdir, "%s__%s__%s%s" % (name, tag, run_id, ext)) if False else os.path.join(outdir, name + ext)
        if not ext:
            dest = os.path.join(outdir, "%s__%s__%s" % (name, tag, run_id))
        if os.path.exists(dest) and os.path.getsize(dest) == a["size_in_bytes"]:
            print("skip %s (already complete)" % os.path.basename(dest))
            continue
        print("fetching %s (%d bytes) -> %s" % (name, a["size_in_bytes"], os.path.basename(dest)))
        n = fetch_artifact(a["id"], dest)
        print("  ok %d bytes" % n)
    print("ARCHIVE DONE:", outdir)

if __name__ == "__main__":
    main()
