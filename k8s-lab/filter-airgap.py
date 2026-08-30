#!/usr/bin/env python3
"""k3s 에어갭 이미지 tar(docker-archive)에서 실제로 쓰는 이미지만 남긴다.

k3s 공식 airgap tar 는 544MB 인데, 그중 traefik(170MB)·klipper-helm(182MB)·metrics-server(65MB)·
klipper-lb(12MB) 는 우리 k3s.service 가 `--disable` 로 끄는 컴포넌트라 절대 쓰이지 않는다.
남길 이미지만 골라 새 tar 를 쓰면 118MB 로 줄어든다(학습자 파드 이미지가 그만큼 가벼워진다).

사용: filter-airgap.py <입력.tar> <출력.tar> <남길-repo> [<남길-repo> ...]
  남길-repo 는 태그를 뺀 이름(예: rancher/mirrored-coredns-coredns).

주의:
  - docker-archive 는 같은 레이어를 공유할 때 `<dir>/layer.tar` 를 **심볼릭 링크**로 둔다.
    링크 대상 디렉터리도 함께 남기지 않으면 import 시 깨진다.
  - manifest.json 과 repositories 파일도 남긴 이미지만 담도록 다시 쓴다.
"""
import io
import json
import sys
import tarfile


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    src_path, dst_path, keep_repos = sys.argv[1], sys.argv[2], set(sys.argv[3:])

    src = tarfile.open(src_path, "r")
    members = {m.name: m for m in src.getmembers()}

    manifest = json.load(src.extractfile("manifest.json"))
    kept, dropped = [], []
    for entry in manifest:
        tags = entry.get("RepoTags") or []
        if any(t.rsplit(":", 1)[0] in keep_repos for t in tags):
            kept.append(entry)
        else:
            dropped.append(tags[0] if tags else entry.get("Config"))
    if not kept:
        sys.exit(f"남길 이미지가 없다 — 요청: {sorted(keep_repos)}")

    # 남길 파일 경로 수집: config json + 레이어 디렉터리(심볼릭 링크 대상 포함)
    keep_paths = set()
    pending = []
    for entry in kept:
        keep_paths.add(entry["Config"])
        pending.extend(entry.get("Layers", []))
    while pending:
        layer = pending.pop()
        m = members.get(layer)
        if m is None:
            sys.exit(f"tar 안에 없는 레이어 참조: {layer}")
        d = layer.rsplit("/", 1)[0]
        for suffix in ("", "/VERSION", "/json", "/layer.tar"):
            name = d + suffix
            if name in members and name not in keep_paths:
                keep_paths.add(name)
        if m.issym() or m.islnk():
            # `<dir>/layer.tar -> ../<other>/layer.tar` — 대상 디렉터리도 남긴다
            target = m.linkname if m.islnk() else _resolve(layer, m.linkname)
            if target not in keep_paths:
                pending.append(target)

    repositories = None
    if "repositories" in members:
        repos = json.load(src.extractfile("repositories"))
        keep_names = {t.rsplit(":", 1)[0] for e in kept for t in (e.get("RepoTags") or [])}
        repositories = {k: v for k, v in repos.items() if k in keep_names}

    dst = tarfile.open(dst_path, "w")
    for name in sorted(keep_paths):
        m = members[name]
        dst.addfile(m, src.extractfile(m) if m.isreg() else None)
    _add_json(dst, "manifest.json", kept)
    if repositories is not None:
        _add_json(dst, "repositories", repositories)
    dst.close()
    src.close()

    print("남김:", ", ".join(t for e in kept for t in (e.get("RepoTags") or [])))
    print("제외:", ", ".join(map(str, dropped)))


def _resolve(path, link):
    parts = path.split("/")[:-1]
    for seg in link.split("/"):
        if seg == "..":
            parts.pop()
        elif seg not in (".", ""):
            parts.append(seg)
    return "/".join(parts)


def _add_json(tar, name, obj):
    data = json.dumps(obj).encode()
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


if __name__ == "__main__":
    main()
