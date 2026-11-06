#!/usr/bin/env python3
"""
把 `docker save` 导出的 OCI layout 重新打包：
  1) 只保留指定平台（可选多平台）
  2) 把每层的 gzip 压缩换成更强的 zstd 压缩（体积可省 ~25%）
  3) 重新生成 index.json / manifest.json / oci-layout

用法:
  docker save IMG:tag | tar -x -C oci_dir
  python3 repack.py oci_dir out.tar --platform linux/amd64 --tag IMG:tag
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

LAYER_GZ = "application/vnd.oci.image.layer.v1.tar+gzip"
LAYER_ZSTD = "application/vnd.oci.image.layer.v1.tar+zstd"
MANIFEST = "application/vnd.oci.image.manifest.v1+json"
INDEX = "application/vnd.oci.image.index.v1+json"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path):
    with open(path) as f:
        return json.load(f)


def save_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"))


def compress_layer(src, dst, level, codec="zstd"):
    """把 gzip 层重压为 zstd / xz 层"""
    if codec == "xz":
        cmd = ["xz", "-9e", "-T0", "-c"]
    else:
        cmd = ["zstd", f"-{level}", "--long=27", "-T0", "-q", "-c"]
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        p1 = subprocess.Popen(["gzip", "-dc"], stdin=fin, stdout=subprocess.PIPE)
        p2 = subprocess.Popen(cmd, stdin=p1.stdout, stdout=fout)
        p1.stdout.close()
        if p2.wait() != 0 or p1.wait() != 0:
            raise RuntimeError(f"压缩失败: {src}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("oci_dir")
    ap.add_argument("out")
    ap.add_argument("--platform", action="append", default=[],
                    help="目标平台，可重复，如 linux/amd64；不填则保留全部")
    ap.add_argument("--tag", default="", help="导入后显示的镜像名，如 dexidp/dex:latest")
    ap.add_argument("--level", type=int, default=19)
    ap.add_argument("--keep-gzip", action="store_true", help="不重新压缩，只裁剪平台")
    ap.add_argument("--force", action="store_true", help="源目录层缺失时仍然继续")
    ap.add_argument("--codec", default="zstd", choices=["zstd", "xz"], help="层压缩算法")
    args = ap.parse_args()

    src = os.path.abspath(args.oci_dir)
    blobs = os.path.join(src, "blobs", "sha256")
    work = tempfile.mkdtemp(prefix="repack-")
    outblobs = os.path.join(work, "blobs", "sha256")
    os.makedirs(outblobs)

    # ---- 找到顶层 index ----
    top = load_json(os.path.join(src, "index.json"))
    entry = top["manifests"][0]
    digest = entry["digest"].split(":")[1]
    node = load_json(os.path.join(blobs, digest))

    # 展开嵌套 index，找到各平台 manifest
    if node.get("mediaType") == INDEX or "manifests" in node:
        candidates = node["manifests"]
    else:
        candidates = [{"digest": entry["digest"], "mediaType": node.get("mediaType", MANIFEST),
                       "platform": {}}]

    wanted = set(args.platform)
    selected = []
    for c in candidates:
        h = c["digest"].split(":")[1]
        if not os.path.exists(os.path.join(blobs, h)):
            continue  # 悬空引用（本机没有该平台层）
        plat = c.get("platform") or {}
        key = f"{plat.get('os')}/{plat.get('architecture')}"
        if wanted and key not in wanted:
            continue
        selected.append((c, h, key))

    if not selected:
        sys.exit("没有匹配到可用平台的层")

    # ---- 完整性自检: manifest 引用的每个层 blob 都必须在目录里 ----
    # Docker 的 containerd 内容库可能已 GC 掉某些平台的压缩层 blob,
    # 但快照还在 -> 镜像能跑、docker save 却导出不完整的包。必须在这里拦住。
    broken = False
    for c, h, key in selected:
        man = load_json(os.path.join(blobs, h))
        miss = [l["digest"][7:19] for l in man["layers"]
                if not os.path.exists(os.path.join(blobs, l["digest"].split(":")[1]))]
        if miss:
            broken = True
            print(f"[!] 平台 {key} 缺少 {len(miss)}/{len(man['layers'])} 个层 blob: {miss[:5]}",
                  file=sys.stderr)
            print(f"    原因通常是 docker 内容库 GC 掉了压缩层 blob（镜像仍能跑，save 却导不全）。",
                  file=sys.stderr)
            print(f"    修复: 重新 pull 该平台并确认内容库完整，例如\n"
                  f"      docker pull --platform {key} {args.tag or 'IMG:TAG'}\n"
                  f"      # 若内容库已残留 manifest 而层缺失，可先 docker save 一个完整包再 docker load 回来，"
                  f"或用 skopeo/crane 从 registry 直接拉取。", file=sys.stderr)
    if broken and not args.force:
        sys.exit("源目录不完整，已中止（如需强推请加 --force）")

    # ---- 逐个平台重写 manifest ----
    out_manifests = []
    man_jsons = []
    layer_paths = []
    for c, h, key in selected:
        man = load_json(os.path.join(blobs, h))
        new_layers = []
        for layer in man["layers"]:
            lh = layer["digest"].split(":")[1]
            lp = os.path.join(blobs, lh)
            if args.keep_gzip:
                newdigest, newsize, media = lh, os.path.getsize(lp), LAYER_GZ
                shutil.copy2(lp, os.path.join(outblobs, lh))
            else:
                tmp = os.path.join(outblobs, "_tmp")
                compress_layer(lp, tmp, args.level, args.codec)
                newdigest = sha256(tmp)
                newsize = os.path.getsize(tmp)
                os.rename(tmp, os.path.join(outblobs, newdigest))
                media = LAYER_ZSTD if args.codec == "zstd" else "application/vnd.oci.image.layer.v1.tar+xz"
            new_layers.append({"mediaType": media, "digest": "sha256:" + newdigest, "size": newsize})
            layer_paths.append(os.path.join(outblobs, newdigest))
        man["layers"] = new_layers
        man["mediaType"] = MANIFEST
        # config blob 原样拷贝
        ch = man["config"]["digest"].split(":")[1]
        if not os.path.exists(os.path.join(outblobs, ch)):
            shutil.copy2(os.path.join(blobs, ch), os.path.join(outblobs, ch))
        raw = json.dumps(man, separators=(",", ":")).encode()
        mh = hashlib.sha256(raw).hexdigest()
        with open(os.path.join(outblobs, mh), "wb") as f:
            f.write(raw)
        plat = c.get("platform") or {}
        entry = {"mediaType": MANIFEST, "digest": "sha256:" + mh,
                 "size": len(raw), "platform": plat}
        out_manifests.append(entry)
        man_jsons.append(man)
        print(f"[{key}] manifest {h[:12]} -> {mh[:12]}  层数 {len(new_layers)}", file=sys.stderr)

    # 镜像名 annotation: containerd 镜像存储靠它决定 load 后的镜像名,
    # 否则 load 出来就是 <none>。多平台时必须放在**外层 index**上,
    # 内层每个平台 manifest 共用同一个名字会被当成互相覆盖。
    name_ann = {}
    if args.tag:
        name_ann = {
            "io.containerd.image.name": args.tag if args.tag.startswith("docker.io/")
            else "docker.io/" + args.tag,
            "org.opencontainers.image.ref.name": args.tag.split(":")[-1],
            "containerd.io/distribution.source.docker.io": args.tag.split(":")[0],
        }

    # ---- index.json ----
    if len(out_manifests) == 1:
        entry = dict(out_manifests[0])
        entry["annotations"] = name_ann
        index = {"schemaVersion": 2, "mediaType": INDEX, "manifests": [entry]}
    else:
        # 多平台: 构造嵌套 index（与上游多架构镜像一致），外层带命名 annotation
        inner = {"schemaVersion": 2, "mediaType": INDEX, "manifests": out_manifests}
        raw = json.dumps(inner, separators=(",", ":")).encode()
        ih = hashlib.sha256(raw).hexdigest()
        with open(os.path.join(outblobs, ih), "wb") as f:
            f.write(raw)
        index = {"schemaVersion": 2, "mediaType": INDEX,
                 "manifests": [{"mediaType": INDEX, "digest": "sha256:" + ih,
                                "size": len(raw), "annotations": name_ann}]}
    save_json(os.path.join(work, "index.json"), index)

    # ---- manifest.json (docker 传统格式, 供旧版 loader 打标签) ----
    if args.tag:
        man = man_jsons[0]
        dj = [{"Config": "blobs/sha256/" + man["config"]["digest"].split(":")[1],
               "RepoTags": [args.tag],
               "Layers": ["blobs/sha256/" + l["digest"].split(":")[1] for l in man["layers"]]}]
        save_json(os.path.join(work, "manifest.json"), dj)

    with open(os.path.join(work, "oci-layout"), "w") as f:
        f.write('{"imageLayoutVersion":"1.0.0"}')

    # ---- 打包成 tar ----
    with tarfile.open(args.out, "w") as tf:
        for name in sorted(os.listdir(work)):
            path = os.path.join(work, name)
            tf.add(path, arcname=name, recursive=True)

    # ---- 产出物自检: tar 里必须包含所有被引用的 blob ----
    with tarfile.open(args.out) as tf:
        names = set(tf.getnames())
    need = set()

    def collect(digest):
        need.add("blobs/sha256/" + digest.split(":")[1])
        raw = json.load(open(os.path.join(outblobs, digest.split(":")[1])))
        if raw.get("mediaType") == INDEX or "manifests" in raw:
            for m in raw["manifests"]:
                collect(m["digest"])
        else:
            need.add("blobs/sha256/" + raw["config"]["digest"].split(":")[1])
            for l in raw["layers"]:
                need.add("blobs/sha256/" + l["digest"].split(":")[1])

    for e in index["manifests"]:
        collect(e["digest"])
    lack = need - names
    if lack:
        sys.exit(f"产出包不完整，缺少 {len(lack)} 个 blob: {sorted(lack)[:5]}")

    shutil.rmtree(work, ignore_errors=True)
    print(f"完成: {args.out}  {os.path.getsize(args.out)/1048576:.2f} MB  (已自检 {len(need)} 个 blob 完整)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
