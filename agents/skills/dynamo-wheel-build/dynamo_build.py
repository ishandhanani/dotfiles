"""Ultra-fast Dynamo wheel builds on Modal using a pre-baked target image + delta RPC + shared sccache.

Architecture:
    1. Modal Image bakes `/src/dynamo` (clamped to mtime T_BASE=1700000000), `/root/.cargo` (CARGO_HOME),
       `/build/target` (CARGO_TARGET_DIR with all 810 crates pre-compiled), and `/build/base_hashes.json`
       onto local container NVMe. Zero FUSE reads for CARGO_HOME or CARGO_TARGET_DIR!
    2. Local entrypoint hashes the worktree on host disk in ~35ms against `base_hashes.json` and sends
       ONLY modified/added file bytes (~KB) + deleted paths over the Modal RPC call (no `add_local_dir`
       upload delay).
    3. Container writes the delta onto `/src/dynamo` (leaving all unchanged files at T_BASE), runs
       `maturin build --release` on local NVMe (with `/cache/sccache` Volume backing any recompiled
       crates across branches/machines), and streams the `.whl` bytes directly back to `./wheels/`.

Usage:
    modal run ~/modal/dynamo_build.py                  # build ~/dynamo & write wheel to ./wheels/
    DYNAMO_SRC=/path/to/worktree modal run ~/modal/dynamo_build.py
    DYNAMO_OUT_DIR=/tmp/wheels modal run ~/modal/dynamo_build.py
    DYNAMO_CGU=1 modal run ~/modal/dynamo_build.py     # max-perf build (codegen-units=1)
"""
import base64
import glob
import hashlib
import json
import os
import pathlib
import subprocess
import time

import modal

SRC = os.path.abspath(os.path.expanduser(os.environ.get("DYNAMO_SRC", "~/dynamo")))
OUT_DIR = os.path.abspath(os.path.expanduser(os.environ.get("DYNAMO_OUT_DIR", "./wheels")))
LOCAL_CACHE_DIR = os.path.expanduser("~/.cache/dynamo-modal-build")
T_BASE = 1700000000
IMAGE_REV = "v1-ubuntu2204-rust1961-cgu16"

app = modal.App("dynamo-wheel-build")

cache_vol = modal.Volume.from_name("dynamo-build-cache", create_if_missing=True)
wheel_vol = modal.Volume.from_name("dynamo-wheels", create_if_missing=True)

SKIP_TOP_DIRS = {
    ".git",
    "target",
    ".venv",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
    "bench",
    "recipes",
    "docs",
    "components",
    "tests",
    "benchmarks",
    "container",
    "gyms",
    "agent-docs",
    "dev",
    "scripts",
}
SKIP_SUB_DIRS = {"target", "__pycache__", ".git", ".venv", "node_modules", ".pytest_cache"}
SKIP_SUFFIXES = (".so", ".whl", ".pyc", ".pyo")

PREP_BASE_SCRIPT = f"""
import hashlib, json, os

root = "/src/dynamo"
t_base = {T_BASE}
hashes = {{}}
files = []
dirs = []
for dirpath, dirnames, filenames in os.walk(root):
    dirs.append(dirpath)
    for f in filenames:
        p = os.path.join(dirpath, f)
        if os.path.islink(p):
            continue
        rel = os.path.relpath(p, root)
        files.append((rel, p))
files.sort()
for idx, (rel, p) in enumerate(files):
    with open(p, "rb") as fp:
        hashes[rel] = hashlib.sha256(fp.read()).hexdigest()
    ts = t_base + idx
    os.utime(p, (ts, ts))
for d in dirs:
    os.utime(d, (t_base, t_base))
os.makedirs("/build", exist_ok=True)
with open("/build/base_hashes.json", "w") as fp:
    json.dump(hashes, fp)
print(f"Prepared {{len(hashes)}} baseline files with unique mtimes")
"""
OLD_PREP_SCRIPT = f"""
import hashlib, json, os

root = "/src/dynamo"
t_base = {T_BASE}
hashes = {{}}
for dirpath, dirnames, filenames in os.walk(root):
    for f in filenames:
        p = os.path.join(dirpath, f)
        if os.path.islink(p):
            continue
        rel = os.path.relpath(p, root)
        with open(p, "rb") as fp:
            hashes[rel] = hashlib.sha256(fp.read()).hexdigest()
        os.utime(p, (t_base, t_base))
    os.utime(dirpath, (t_base, t_base))
os.makedirs("/build", exist_ok=True)
with open("/build/base_hashes.json", "w") as fp:
    json.dump(hashes, fp)
print(f"Prepared {{len(hashes)}} baseline files at mtime={{t_base}}")
"""
OLD_PREP_B64 = base64.b64encode(OLD_PREP_SCRIPT.encode()).decode()
PREP_BASE_B64 = base64.b64encode(PREP_BASE_SCRIPT.encode()).decode()

toolchain_img = (
    modal.Image.from_registry("ubuntu:22.04", add_python="3.12")
    .apt_install(
        "build-essential",
        "ca-certificates",
        "clang",
        "cmake",
        "curl",
        "git",
        "libclang-dev",
        "libnuma-dev",
        "libssl-dev",
        "libudev-dev",
        "mold",
        "patchelf",
        "pkg-config",
        "unzip",
        "zstd",
    )
    .run_commands(
        "curl -LsSf https://astral.sh/uv/install.sh | sh",
        "curl --proto '=https' -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.96.1 --profile minimal",
        "curl -L https://github.com/mozilla/sccache/releases/download/v0.14.0/sccache-v0.14.0-x86_64-unknown-linux-musl.tar.gz | tar xz --strip-components=1 -C /usr/local/bin --wildcards '*/sccache'",
        "curl -L -o /tmp/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v25.8/protoc-25.8-linux-x86_64.zip && unzip -o /tmp/protoc.zip -d /usr/local && rm /tmp/protoc.zip",
        "/root/.local/bin/uv tool install maturin",
    )
    .env(
        {
            "PATH": "/root/.cargo/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "SCCACHE_DIR": "/cache/sccache",
            "SCCACHE_CACHE_SIZE": "200G",
            "SCCACHE_IDLE_TIMEOUT": "0",
            "CARGO_HOME": "/build/cargo",
            "CARGO_REGISTRIES_CRATES_IO_PROTOCOL": "sparse",
            "RUSTC_WRAPPER": "sccache",
            "CARGO_INCREMENTAL": "0",
            "CARGO_PROFILE_RELEASE_CODEGEN_UNITS": os.environ.get("DYNAMO_CGU", "16"),
            "CARGO_TARGET_DIR": "/build/target",
            "RUSTFLAGS": "-C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3 -C force-frame-pointers=yes --cfg tokio_unstable",
        }
    )
)

img = (
    toolchain_img.run_commands(
        f"tar -I zstd -xf /cache/warm_layer.tar.zst -C / && "
        f"echo {OLD_PREP_B64} | base64 -d | python3",
        volumes={"/cache": cache_vol},
    )
    .run_commands(
        f"echo {PREP_BASE_B64} | base64 -d | python3 && "
        f"cd /src/dynamo/lib/bindings/python && "
        f"maturin build --release --offline --out /tmp/w && rm -rf /tmp/w && "
        f"sccache --show-stats",
        volumes={"/cache": cache_vol},
    )
)


@app.function(
    image=toolchain_img,
    volumes={"/cache": cache_vol},
    cpu=32,
    memory=65536,
    timeout=3600,
)
def seed_warm_cache(base_src_zst: bytes) -> dict[str, str]:
    """Bootstrap /cache/base_src.tar.zst, /cache/warm_layer.tar.zst, and /cache/base_hashes.json."""
    pathlib.Path("/cache/base_src.tar.zst").write_bytes(base_src_zst)
    subprocess.run(
        [
            "bash",
            "-c",
            f"set -euo pipefail; "
            f"rm -rf /src/dynamo /build && mkdir -p /src/dynamo /build/cargo /build/target && "
            f"tar --zstd -xf /cache/base_src.tar.zst -C /src/dynamo && "
            f"echo {PREP_BASE_B64} | base64 -d | python3 && "
            f"cp /build/base_hashes.json /cache/base_hashes.json && "
            f"cd /src/dynamo/lib/bindings/python && "
            f"maturin build --release --out /tmp/warm-out && rm -rf /tmp/warm-out && "
            f"tar -I 'zstd -1 -T0' -cf /cache/warm_layer.tar.zst /src/dynamo /build",
        ],
        check=True,
    )
    cache_vol.commit()
    with open("/build/base_hashes.json") as f:
        return json.load(f)


@app.function(
    image=img,
    volumes={"/cache": cache_vol},
    cpu=32,
    memory=65536,
    timeout=3600,
)
def get_base_hashes() -> dict[str, str]:
    with open("/build/base_hashes.json") as f:
        return json.load(f)


@app.function(
    image=img,
    volumes={"/cache": cache_vol, "/out": wheel_vol},
    cpu=32,
    memory=65536,
    timeout=3600,
)
def build_wheel(
    tag: str,
    changed_files: dict[str, bytes],
    deleted_files: list[str],
    save_to_volume: bool = False,
) -> tuple[str, bytes, float, float, str]:
    t0 = time.monotonic()
    root = pathlib.Path("/src/dynamo")
    dirty_marker = pathlib.Path("/build/dirty_files.json")
    now = time.time()

    # If this warm container previously applied a delta, reset those files first
    if dirty_marker.exists():
        base_archive = pathlib.Path("/cache/base_src.tar.zst")
        if not base_archive.exists():
            raise RuntimeError(
                "Missing /cache/base_src.tar.zst on volume 'dynamo-build-cache'. "
                "Run `modal run dynamo_build.py --seed-cache` to initialize the baseline archives."
            )
        prev_dirty = json.loads(dirty_marker.read_text())
        for rel in prev_dirty:
            p = root / rel
            if p.exists() or p.is_symlink():
                p.unlink()
        subprocess.run(
            ["tar", "--zstd", "-xf", str(base_archive), "-C", "/src/dynamo"],
            check=True,
        )
        subprocess.run(["python3", "-c", PREP_BASE_SCRIPT], check=True)
        for rel in prev_dirty:
            p = root / rel
            if p.exists():
                os.utime(p, (now, now))
        dirty_marker.unlink()

    if changed_files or deleted_files:
        dirty_marker.write_text(json.dumps(list(changed_files.keys()) + deleted_files))

    for rel in deleted_files:
        p = root / rel
        if p.exists():
            p.unlink()

    for rel, data in changed_files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        os.utime(p, (now, now))

    subprocess.run(["sccache", "--zero-stats"], check=False, capture_output=True)

    out_dir = "/tmp/wheel-out"
    proc = subprocess.run(
        [
            "bash",
            "-c",
            f"set -euo pipefail; rm -rf {out_dir} && mkdir -p {out_dir} && "
            f"cd /src/dynamo/lib/bindings/python && "
            f"maturin build --release --offline --compression-method stored --auditwheel skip --out {out_dir} || "
            f"maturin build --release --compression-method stored --auditwheel skip --out {out_dir}",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"maturin build failed (exit {proc.returncode})\n"
            f"--- stdout (tail) ---\n{proc.stdout[-4000:]}\n"
            f"--- stderr (tail) ---\n{proc.stderr[-8000:]}"
        )
    stats_out = subprocess.run(
        ["sccache", "--show-stats"], capture_output=True, text=True, check=False
    ).stdout
    build_secs = time.monotonic() - t0

    wheels = sorted(glob.glob(f"{out_dir}/*.whl"))
    if not wheels:
        raise RuntimeError(f"No wheel found in {out_dir}\n{proc.stdout}\n{proc.stderr}")
    whl_path = pathlib.Path(wheels[-1])
    zst_path = pathlib.Path(f"{whl_path}.zst")
    subprocess.run(["zstd", "-1", "-T0", "-q", "-f", str(whl_path), "-o", str(zst_path)], check=True)
    whl_zst_bytes = zst_path.read_bytes()

    t_commit0 = time.monotonic()
    # Only commit cache_vol if sccache actually wrote new cache entries
    wrote_sccache = False
    for line in stats_out.splitlines():
        if line.strip().startswith("Cache misses") and not line.strip().startswith("Cache misses ("):
            parts = line.split()
            if parts and parts[-1].isdigit() and int(parts[-1]) > 0:
                wrote_sccache = True
    if wrote_sccache:
        cache_vol.commit()
    if save_to_volume:
        vol_dir = pathlib.Path(f"/out/{tag}")
        vol_dir.mkdir(parents=True, exist_ok=True)
        (vol_dir / whl_path.name).write_bytes(whl_path.read_bytes())
        wheel_vol.commit()
    commit_secs = time.monotonic() - t_commit0

    return whl_path.name, whl_zst_bytes, build_secs, commit_secs, proc.stderr.strip()


def compute_local_delta(src_root: str, base_hashes: dict[str, str]) -> tuple[dict[str, bytes], list[str], str]:
    changed: dict[str, bytes] = {}
    seen: set[str] = set()
    hasher = hashlib.sha256()

    for dirpath, dirnames, filenames in os.walk(src_root):
        if dirpath == src_root:
            dirnames[:] = [
                d
                for d in sorted(dirnames)
                if d not in SKIP_TOP_DIRS
                and not d.startswith(".tmp-")
                and not d.startswith("compaction_")
            ]
        else:
            dirnames[:] = [d for d in sorted(dirnames) if d not in SKIP_SUB_DIRS]
        for fname in sorted(filenames):
            if fname.endswith(SKIP_SUFFIXES):
                continue
            full = os.path.join(dirpath, fname)
            if os.path.islink(full):
                continue
            rel = os.path.relpath(full, src_root)
            seen.add(rel)
            try:
                data = pathlib.Path(full).read_bytes()
            except OSError:
                continue
            h = hashlib.sha256(data).hexdigest()
            if base_hashes.get(rel) != h:
                changed[rel] = data
                hasher.update(rel.encode())
                hasher.update(h.encode())

    deleted = sorted(set(base_hashes.keys()) - seen)
    for rel in deleted:
        hasher.update(f"DEL:{rel}".encode())

    return changed, deleted, hasher.hexdigest()[:12]


def _pack_local_base_src(src_root: str) -> bytes:
    tmp_archive = f"/tmp/base_src_{os.getpid()}.tar.zst"
    excludes = [f"--exclude=./{d}" for d in sorted(SKIP_TOP_DIRS)] + [
        f"--exclude=*/{d}" for d in sorted(SKIP_SUB_DIRS)
    ] + [
        "--exclude=./.tmp-*",
        "--exclude=./compaction_*",
        "--exclude=*.so",
        "--exclude=*.whl",
        "--exclude=*.pyc",
    ]
    subprocess.run(
        ["tar", "--zstd", "--anchored", *excludes, "-cf", tmp_archive, "-C", src_root, "."],
        check=True,
    )
    try:
        return pathlib.Path(tmp_archive).read_bytes()
    finally:
        pathlib.Path(tmp_archive).unlink(missing_ok=True)


def _load_or_fetch_base_hashes(local_hashes_file: str) -> dict[str, str]:
    if os.path.exists(local_hashes_file):
        try:
            with open(local_hashes_file) as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            pathlib.Path(local_hashes_file).unlink(missing_ok=True)

    tmp_file = f"{local_hashes_file}.{os.getpid()}.tmp"
    try:
        subprocess.run(
            ["modal", "volume", "get", "dynamo-build-cache", "base_hashes.json", tmp_file, "--force"],
            check=True,
            capture_output=True,
        )
        with open(tmp_file) as f:
            hashes = json.load(f)
    except (subprocess.CalledProcessError, OSError, json.JSONDecodeError):
        hashes = get_base_hashes.remote()
        with open(tmp_file, "w") as f:
            json.dump(hashes, f)
    os.replace(tmp_file, local_hashes_file)
    return hashes


@app.local_entrypoint()
def main(seed_cache: bool = False) -> None:
    t0 = time.monotonic()
    os.makedirs(LOCAL_CACHE_DIR, exist_ok=True)
    local_hashes_file = os.path.join(LOCAL_CACHE_DIR, f"base_hashes_{IMAGE_REV}.json")

    if seed_cache:
        print(f"Seeding warm cache on volume 'dynamo-build-cache' from {SRC}...")
        hashes = seed_warm_cache.remote(_pack_local_base_src(SRC))
        tmp_file = f"{local_hashes_file}.{os.getpid()}.tmp"
        with open(tmp_file, "w") as f:
            json.dump(hashes, f)
        os.replace(tmp_file, local_hashes_file)
        print(f"Seeded {len(hashes)} baseline files in {time.monotonic() - t0:.1f}s")
        return

    base_hashes = _load_or_fetch_base_hashes(local_hashes_file)

    t_diff0 = time.monotonic()
    changed, deleted, delta_hash = compute_local_delta(SRC, base_hashes)
    diff_ms = (time.monotonic() - t_diff0) * 1000

    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=SRC
    ).stdout.strip() or "no-git"
    tag = f"{sha[:12]}-d{delta_hash}"
    delta_kb = sum(len(v) for v in changed.values()) / 1024
    print(
        f"Building {SRC} @ {sha[:12]} | local diff: {len(changed)} modified/added ({delta_kb:.1f} KiB), "
        f"{len(deleted)} deleted in {diff_ms:.0f}ms"
    )

    save_vol = os.environ.get("DYNAMO_SAVE_VOLUME", "0") == "1"
    whl_name, whl_zst_bytes, build_secs, commit_secs, cargo_log = build_wheel.remote(
        tag, changed, deleted, save_vol
    )

    os.makedirs(OUT_DIR, exist_ok=True)
    local_whl = os.path.join(OUT_DIR, whl_name)
    local_zst = f"{local_whl}.zst"
    with open(local_zst, "wb") as f:
        f.write(whl_zst_bytes)
    subprocess.run(["zstd", "-d", "-q", "-f", "--rm", local_zst, "-o", local_whl], check=True)

    total_secs = time.monotonic() - t0
    for line in cargo_log.splitlines()[-8:]:
        if line.strip():
            print(f"  {line}")
    print(
        f"\nTiming: remote_build={build_secs:.2f}s  vol_commit={commit_secs:.2f}s  "
        f"e2e_wall={total_secs:.2f}s  wire={len(whl_zst_bytes)/1e6:.1f}MB"
    )
    print(f"Wheel ready: {local_whl}")
