"""Replace torrents that the private trackers have taken down.

The French trackers regularly remove a release, usually because a lighter
encode of the same film replaced it ("removed as a duplicate, kept release:
..."). The torrent then sits in qBittorrent announcing to nobody, and Radarr
or Sonarr never notice: a replacement of the same quality and score is not an
upgrade to them. For each such torrent in a *arr category:

  - the library file no longer comes from it (left over from an upgrade):
    delete the torrent and its data
  - the library file is still seeded by another live torrent (cross-seed on
    the other tracker): delete the dead torrent only
  - otherwise: grab the best replacement from the allowed trackers, and delete
    the dead torrent once the replacement has been imported

Two more sweeps, on any torrent of the *arr and cross-seed categories:

  - dead cross-seeds go: they only ever hold a second hardlink
  - live torrents whose files are no longer in the library (the film was
    upgraded, or removed from the library) go once they have seeded
    MIN_SEED_DAYS, so a recent download is never a hit and run

Library files are hardlinks, so deleting a torrent never removes what is in
the library: Radarr/Sonarr swap that file themselves when the replacement is
imported.

Dry run by default, --apply to act. State lives in STATE (JSON).
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ARR_HOST = os.environ.get("ARR_HOST", "127.0.0.1")
ARR_ROOT = os.environ.get("ARR_ROOT", "/opt/arr-stack")
QBIT = os.environ["QBIT_URL"]
DOWNLOADS = os.environ.get("DOWNLOADS", "/mnt/hdd/downloads")
MEDIA = os.environ.get("MEDIA", "/mnt/hdd/media")
CROSS_SEED_CATEGORY = os.environ.get("CROSS_SEED_CATEGORY", "cross-seed-link")
MIN_SEED_DAYS = float(os.environ.get("MIN_SEED_DAYS", "7"))
STATE = os.environ.get("STATE", "/var/lib/tracker-replace/state.json")
SSH = os.environ.get("SSH_HOST", "")  # empty = run stat/find locally
TRACKERS = re.compile(os.environ.get("TRACKERS", "c411|v3x"), re.I)
MAX_SEARCHES = int(os.environ.get("MAX_SEARCHES", "10"))
RETRY_AFTER = timedelta(hours=int(os.environ.get("RETRY_HOURS", "24")))
GIVE_UP_AFTER = timedelta(days=3)
# a replacement may not be more than this much bigger than what it replaces
MAX_GROWTH = float(os.environ.get("MAX_GROWTH", "1.5"))
# the old copy is only freed after the import, so a grab needs room of its own
MIN_FREE = float(os.environ.get("MIN_FREE_GB", "100")) * 1e9
APPLY = "--apply" in sys.argv

APPS = {
    "radarr": {"port": 7878, "category": "movies-radarr"},
    "sonarr": {"port": 8989, "category": "tv-sonarr"},
}
UNREGISTERED = re.compile(r"not registered|unregistered|removed|introuvable", re.I)
KEPT = re.compile(r"kept release:\s*(\S+)", re.I)
# rejections a replacement is allowed to carry: they are only about the file in place
UPGRADE_REJECTIONS = re.compile(r"upgrade|cutoff|existing file|already|meets|equal", re.I)
QBIT_TRACKER_WORKING = 2


def now():
    return datetime.now(timezone.utc)


def http(url, method="GET", body=None, headers=None, form=False):
    data = None
    headers = dict(headers or {})
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=180) as r:
        raw = r.read()
        try:
            return json.loads(raw) if raw else None
        except ValueError:
            return raw.decode()


def sh(cmd):
    if not SSH:
        return subprocess.check_output(["sh", "-c", cmd], text=True)
    return subprocess.check_output(["ssh", "-n", SSH, cmd], text=True)


class Arr:
    def __init__(self, name):
        self.name = name
        self.base = f"http://{ARR_HOST}:{APPS[name]['port']}/api/v3"
        key = sh(f"sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' {ARR_ROOT}/{name}/config/config.xml").strip()
        self.h = {"X-Api-Key": key}

    def get(self, path, **params):
        q = f"?{urllib.parse.urlencode(params)}" if params else ""
        return http(f"{self.base}/{path}{q}", headers=self.h)

    def post(self, path, body):
        return http(f"{self.base}/{path}", "POST", body, self.h)

    def history(self, download_id):
        return self.get("history", downloadId=download_id.upper(), pageSize=100)["records"]

    def library_files(self, target):
        if self.name == "radarr":
            return self.get("moviefile", movieId=target["movieId"])
        files = self.get("episodefile", seriesId=target["seriesId"])
        eps = {e["id"]: e for e in self.get("episode", seriesId=target["seriesId"])}
        wanted = {eps[i]["episodeFileId"] for i in target["episodeIds"] if i in eps}
        return [f for f in files if f["id"] in wanted]

    def releases(self, target):
        if self.name == "radarr":
            return self.get("release", movieId=target["movieId"])
        if len(target["episodeIds"]) > 1:
            rel = self.get("release", seriesId=target["seriesId"], seasonNumber=target["seasonNumber"])
            return [r for r in rel if r.get("fullSeason")]
        return self.get("release", episodeId=target["episodeIds"][0])

    def label(self, target):
        if self.name == "radarr":
            m = self.get(f"movie/{target['movieId']}")
            return f"{m['title']} ({m.get('year')})"
        s = self.get(f"series/{target['seriesId']}")
        return f"{s['title']} S{target['seasonNumber']:02d}" + (
            "" if len(target["episodeIds"]) > 1 else " (1 episode)")


def target_from_history(app, records):
    rec = [r for r in records if r["eventType"] in ("downloadFolderImported", "grabbed")]
    if not rec:
        return None
    if app.name == "radarr":
        return {"movieId": rec[0]["movieId"]}
    imported = [r for r in rec if r["eventType"] == "downloadFolderImported"] or rec
    return {"seriesId": imported[0]["seriesId"],
            "episodeIds": sorted({r["episodeId"] for r in imported}),
            "seasonNumber": app.get(f"episode/{imported[0]['episodeId']}")["seasonNumber"]}


def inodes(paths):
    if not paths:
        return set()
    quoted = " ".join("'" + p.replace("'", "'\\''") + "'" for p in paths)
    return set(sh(f"stat -c %i {quoted} 2>/dev/null || true").split())


def download_inodes(root=DOWNLOADS):
    by_inode = {}
    for line in sh(f"find {root} -type f -printf '%i\\t%p\\n'").splitlines():
        ino, _, path = line.partition("\t")
        by_inode.setdefault(ino, []).append(path)
    return by_inode


def norm(title):
    return re.sub(r"[^a-z0-9]", "", re.sub(r"\.(mkv|mp4|avi)$", "", title.lower()))


def torrent_files(t):
    files = http(f"{QBIT}/api/v2/torrents/files?hash={t['hash']}")
    return [os.path.join(t["save_path"], f["name"]) for f in files]


def tracker_msgs(t):
    return [tr.get("msg", "") for tr in t.get("trackers", []) if tr["url"].startswith("http")]


def is_dead(t):
    trackers = [tr for tr in t.get("trackers", []) if tr["url"].startswith("http")]
    return (t["progress"] >= 1
            and any(UNREGISTERED.search(tr.get("msg", "")) for tr in trackers)
            and not any(tr["status"] == QBIT_TRACKER_WORKING for tr in trackers))


def pick(app, t, target, kept):
    scores = [f.get("customFormatScore", 0) for f in app.library_files(target)]
    cur = min(scores) if scores else None
    cands = []
    for r in app.releases(target):
        # the same release on the other tracker is handled by the "still seeded" rule
        if not TRACKERS.search(r.get("indexer", "")) or norm(r["title"]) == norm(t["name"]):
            continue
        if r.get("protocol") != "torrent" or (r.get("seeders") or 0) < 1:
            continue
        if any(not UPGRADE_REJECTIONS.search(x) for x in r.get("rejections", [])):
            continue
        cands.append(r)
    if kept:
        exact = [r for r in cands if norm(r["title"]) == norm(kept)]
        if exact:
            return exact[0], cur
    cands = [r for r in cands if (cur is None or r.get("customFormatScore", 0) >= cur)
             and r["size"] <= t["size"] * MAX_GROWTH]
    # same score: the biggest that is not bigger than the old one, else the smallest above it
    cands.sort(key=lambda r: (-r.get("customFormatScore", 0), r["size"] > t["size"],
                              -r["size"] if r["size"] <= t["size"] else r["size"]))
    return (cands[0] if cands else None), cur


def free_bytes():
    if not SSH:
        st = os.statvfs(DOWNLOADS)
        return st.f_bavail * st.f_frsize
    return int(sh(f"df -B1 --output=avail {DOWNLOADS} | tail -1"))


def queued(apps):
    ids = set()
    for app in apps.values():
        ids |= {r.get("downloadId", "").lower() for r in app.get("queue", pageSize=1000)["records"]}
    return ids


def sweep(torrents, dead, by_inode, apps, report):
    path_ino = {p: ino for ino, paths in by_inode.items() for p in paths}
    media = set(download_inodes(MEDIA))
    busy = queued(apps)
    cats = {a["category"] for a in APPS.values()} | {CROSS_SEED_CATEGORY}
    for t in torrents:
        if t["category"] not in cats or t["progress"] < 1 or t["hash"] in busy:
            continue
        if t["hash"] in dead:
            if t["category"] == CROSS_SEED_CATEGORY:
                delete_torrent(t["hash"])
                report["dead cross-seed deleted"].append(t["name"])
            continue
        if t["seeding_time"] < MIN_SEED_DAYS * 86400:
            continue
        files = torrent_files(t)
        inos = {path_ino.get(p) for p in files}
        # a file not found under DOWNLOADS means the scan cannot vouch for it
        if None in inos or inos & media:
            continue
        delete_torrent(t["hash"])
        report["no longer in the library, deleted"].append(
            f"{t['name']} ({t['size'] / 1e9:.1f} GB, seeded {t['seeding_time'] / 86400:.0f} days, ratio {t['ratio']:.2f})")


def delete_torrent(h):
    if APPLY:
        http(f"{QBIT}/api/v2/torrents/delete", "POST", {"hashes": h, "deleteFiles": "true"}, form=True)


def main():
    state = json.load(open(STATE)) if os.path.exists(STATE) else {}
    torrents = http(f"{QBIT}/api/v2/torrents/info?includeTrackers=true")
    by_hash = {t["hash"]: t for t in torrents}
    dead = {t["hash"] for t in torrents if is_dead(t)}
    live_paths = [t["content_path"] for t in torrents if t["hash"] not in dead]
    by_inode = download_inodes()
    apps = {n: Arr(n) for n in APPS}
    searches = 0
    handled = set()
    free = free_bytes() - sum(st.get("size", 0) for st in state.values() if st["status"] == "grabbed")
    report = {"orphan deleted": [], "still seeded elsewhere, dead one deleted": [],
              "replacement grabbed": [], "imported, old one deleted": [],
              "dead cross-seed deleted": [], "no longer in the library, deleted": [],
              "waiting": [], "given up": [], "unknown": []}

    # 1. follow up on replacements already grabbed
    for h, st in list(state.items()):
        if h not in by_hash:
            state.pop(h)
            continue
        if st["status"] != "grabbed":
            continue
        app = apps[st["app"]]
        if not st.get("newId"):
            hist = app.get("history", pageSize=200, sortKey="date", sortDirection="descending", eventType=1)
            for r in hist["records"]:
                if r["sourceTitle"] == st["new"] and r.get("downloadId"):
                    st["newId"] = r["downloadId"]
        imported = st.get("newId") and any(
            r["eventType"] == "downloadFolderImported" for r in app.history(st["newId"]))
        if imported:
            delete_torrent(h)
            handled.add(h)
            report["imported, old one deleted"].append(f"{st['label']}: {by_hash[h]['name']} -> {st['new']}")
            state.pop(h)
        elif now() - datetime.fromisoformat(st["at"]) > GIVE_UP_AFTER:
            st["status"] = "failed"
            report["given up"].append(f"{st['label']}: {st['new']} never imported")

    # 2. newly dead torrents
    for t in torrents:
        cat = next((n for n, a in APPS.items() if a["category"] == t["category"]), None)
        if not cat or t["hash"] not in dead or t["hash"] in handled:
            continue
        st = state.get(t["hash"])
        if st and (st["status"] in ("grabbed", "failed") or now() - datetime.fromisoformat(st["at"]) < RETRY_AFTER):
            if st["status"] == "waiting":
                report["waiting"].append(f"{st['label']}: {t['name']}")
            continue
        app = apps[cat]
        target = target_from_history(app, app.history(t["hash"]))
        if not target:
            report["unknown"].append(f"[{cat}] {t['name']} (not in history)")
            continue
        label = app.label(target)
        lib = [f["path"] for f in app.library_files(target)]
        mine = torrent_files(t)
        in_use = inodes(lib) & inodes(mine)
        if lib and not in_use:
            delete_torrent(t["hash"])
            report["orphan deleted"].append(f"{label}: {t['name']}")
            continue
        others = [p for ino in in_use for p in by_inode.get(ino, []) if p not in mine]
        if others and all(any(p == lp or p.startswith(lp + "/") for lp in live_paths) for p in others):
            delete_torrent(t["hash"])
            report["still seeded elsewhere, dead one deleted"].append(f"{label}: {t['name']}")
            continue
        if searches >= MAX_SEARCHES:
            continue
        searches += 1
        kept = next((m.group(1) for m in map(KEPT.search, tracker_msgs(t)) if m), None)
        rel, cur = pick(app, t, target, kept)
        if not rel:
            state[t["hash"]] = {"status": "waiting", "app": cat, "target": target, "label": label,
                                "at": now().isoformat()}
            report["waiting"].append(f"{label}: {t['name']} (nothing scoring >= {cur})")
            continue
        if free - rel["size"] < MIN_FREE:
            report["waiting"].append(f"{label}: {rel['title']} ({rel['size'] / 1e9:.1f} GB, disk full)")
            continue
        free -= rel["size"]
        if APPLY:
            app.post("release", {"guid": rel["guid"], "indexerId": rel["indexerId"]})
            time.sleep(2)
        state[t["hash"]] = {"status": "grabbed", "app": cat, "target": target, "label": label,
                            "new": rel["title"], "size": rel["size"], "at": now().isoformat()}
        report["replacement grabbed"].append(
            f"{label}: {t['name']} [{cur}] -> {rel['title']} [{rel.get('customFormatScore')}] "
            f"{rel['size'] / 1e9:.1f} GB via {rel['indexer']}")

    # 3. torrents the library no longer needs
    sweep([t for t in torrents if t["hash"] not in handled], dead, by_inode, apps, report)

    if APPLY:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        json.dump(state, open(STATE, "w"), indent=1, ensure_ascii=False)
    print(("APPLIED" if APPLY else "DRY RUN") + f" {now():%Y-%m-%d %H:%M} searches={searches}")
    for k, items in report.items():
        if items:
            print(f"\n## {k} ({len(items)})")
            print("\n".join(f"- {i}" for i in items))


if __name__ == "__main__":
    main()
