#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["modal>=1.6"]
# ///
"""Run cargo commands for a Dynamo worktree on Modal, warm, shared by many agents.

One deployed app, `dynamo-cargo`, serves every caller. Nothing is built on the host and
no app is created per run.

  shared by everyone  the volume `dynamo-build-cache`: sccache for registry dependencies,
                      the cargo registry, and a base snapshot of a built tree (sources plus
                      target dir) that new slots start from;
  per slot            one container that keeps /src/dynamo and /build/target on local NVMe
                      between calls. A slot is a name, by default the worktree directory
                      name, so each worktree keeps its own warm incremental build and
                      agents on different worktrees never undo each other's work.

Each call packs the worktree (tracked plus untracked non-ignored files, minus top-level
recipes/, docs/, benchmarks/, container/), syncs it by checksum so only files whose content
changed get a new mtime (files the build generates in the tree are left alone), and runs the
command with `bash -c` in /src/dynamo. Workspace crates build incrementally; cargo rebuilds only what changed.

Deploy (once, and after editing this file):
    modal deploy <skill-dir>/dynamo_cargo.py

Run:
    DYNAMO_SRC=/path/to/worktree <skill-dir>/dynamo_cargo.py "cargo test -p dynamo-llm"

Environment:
    DYNAMO_SRC          worktree to build (default ~/dynamo)
    DYNAMO_CARGO_SLOT   slot name (default: basename of DYNAMO_SRC)
    DYNAMO_CARGO_LOG    where the complete output is written (default /tmp/dynamo_cargo.<slot>.<random>.log, unique per call)

Maintenance:
    dynamo_cargo.py --save-base     snapshot this slot's tree, target dir and sync manifest as the
                                    shared base (do it from a slot that just built main; re-run it
                                    after deploying, older bases lack the manifest)
    dynamo_cargo.py --reset         delete this slot's source tree and target dir

The script's exit code is the remote command's exit code. Calls to one slot run one at a
time; calls to different slots run in parallel. A slot's container stops after 20 idle
minutes; the next call restores the shared base (or starts cold if there is none).
"""

import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

import modal

APP_NAME = "dynamo-cargo"
REGISTRY_TAR = "/cache/cargo_registry_dev.tar.zst"
BASE_TAR = "/cache/dev_base/base.tar.zst"
SKIP_TOP_DIRS = {"recipes", "docs", "benchmarks", "container"}
SRC_DIR = "/src/dynamo"
TARGET_DIR = "/build/target"
# Paths the last sync wrote. Kept outside the target dir so `cargo clean` cannot drop it;
# the base snapshot carries it.
MANIFEST = "/build/dynamo_sync_manifest"

app = modal.App(APP_NAME)
cache_vol = modal.Volume.from_name("dynamo-build-cache", create_if_missing=True)

img = (
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
        "/root/.cargo/bin/rustup component add clippy rustfmt",
    )
    .apt_install("rsync")
    .env(
        {
            "PATH": "/root/.cargo/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "SCCACHE_DIR": "/cache/sccache",
            "SCCACHE_CACHE_SIZE": "200G",
            "SCCACHE_IDLE_TIMEOUT": "0",
            "CARGO_HOME": "/build/cargo",
            "CARGO_REGISTRIES_CRATES_IO_PROTOCOL": "sparse",
            "RUSTC_WRAPPER": "sccache",
            # CARGO_INCREMENTAL is deliberately NOT set: sccache refuses to run when the
            # variable exists. The dev and test profiles already build workspace crates
            # incrementally (sccache passes those calls through uncached), and registry
            # dependencies are never incremental, so they stay cacheable.
            "CARGO_TARGET_DIR": TARGET_DIR,
            "CARGO_PROFILE_DEV_DEBUG": "line-tables-only",
            "CARGO_PROFILE_TEST_DEBUG": "line-tables-only",
            "CARGO_TERM_COLOR": "never",
            # Same flags as the repo's .cargo/config.toml plus mold; env RUSTFLAGS replaces the config's.
            "RUSTFLAGS": "-C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3 -C force-frame-pointers=yes --cfg tokio_unstable",
            "PCRE2_SYS_STATIC": "1",
        }
    )
)


def _count_files(path: str) -> int:
    total = 0
    for _, _, files in os.walk(path):
        total += len(files)
    return total


def _sh(script: str, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", "-c", script], **kwargs)


@app.cls(
    image=img,
    volumes={"/cache": cache_vol},
    cpu=32,
    memory=65536,
    timeout=4 * 3600,
    scaledown_window=1200,
    max_containers=1,
)
class Cargo:
    slot: str = modal.parameter(default="default")

    def _reload(self) -> None:
        try:
            cache_vol.reload()
        except Exception as exc:  # a stale view only costs cache hits
            print(f"[dynamo-cargo] volume reload skipped: {exc}", flush=True)

    @modal.method()
    def run(self, src_zst: bytes, cmd: str) -> tuple[int, bytes]:
        t0 = time.time()
        log_path = "/tmp/dynamo_cargo.log"
        self._reload()

        # A new container starts from the shared base snapshot when there is one.
        state = "warm"
        if not os.path.isdir(os.path.join(TARGET_DIR, "debug")):
            state = "cold"
            if os.path.exists(BASE_TAR):
                _sh(f"zstd -d -T0 -c {BASE_TAR} | tar -x -C /", check=True)
                state = f"restored base in {time.time() - t0:.0f}s"

        # Sync the worktree. Only files whose content changed are rewritten and get a new
        # mtime, so cargo's fingerprints stay valid for everything else.
        t_sync = time.time()
        incoming = "/tmp/incoming"
        shutil.rmtree(incoming, ignore_errors=True)
        os.makedirs(incoming)
        os.makedirs(SRC_DIR, exist_ok=True)
        subprocess.run(["bash", "-c", f"zstd -d -T0 | tar -x -C {incoming}"], input=src_zst, check=True)
        # Delete only paths that an earlier sync put there and the worktree no longer has.
        # A plain `rsync --delete` would also remove files the build generates inside the
        # source tree (the C bindings header, for one) and force their build scripts to rerun.
        # os.walk lists symlinks to directories in `dirs` and does not follow them.
        current = set()
        for root, dirs, files in os.walk(incoming):
            names = files + [d for d in dirs if os.path.islink(os.path.join(root, d))]
            for name in names:
                current.add(os.path.relpath(os.path.join(root, name), incoming))
        previous = set()
        if os.path.exists(MANIFEST):
            with open(MANIFEST) as fp:
                previous = set(fp.read().splitlines())
        removed = sorted(previous - current)
        for rel in removed:
            try:
                os.remove(os.path.join(SRC_DIR, rel))
            except (FileNotFoundError, IsADirectoryError):
                pass
        # mrsync cannot replace a non-empty directory with a file or symlink: clear those first.
        for rel in current:
            dst = os.path.join(SRC_DIR, rel)
            if os.path.isdir(dst) and not os.path.islink(dst):
                shutil.rmtree(dst)
        sync = subprocess.run(
            ["rsync", "-rlpc", "--itemize-changes", f"{incoming}/", f"{SRC_DIR}/"],
            check=True,
            capture_output=True,
            text=True,
        )
        changed = [line for line in sync.stdout.splitlines() if line and not line.startswith(".")]
        changed += [f"*deleting   {rel}" for rel in removed]
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w") as fp:
            fp.write("\n".join(sorted(current)))
        shutil.rmtree(incoming, ignore_errors=True)

        os.makedirs("/build/cargo", exist_ok=True)
        if not os.path.isdir("/build/cargo/registry") and os.path.exists(REGISTRY_TAR):
            _sh(f"zstd -d -T0 -c {REGISTRY_TAR} | tar -x -C /build/cargo", check=True)
        subprocess.run(["sccache", "--zero-stats"], check=False, capture_output=True)
        header = (
            f"[dynamo-cargo] slot {self.slot}: container {state}; synced {len(changed)} changed paths "
            f"in {time.time() - t_sync:.1f}s; running: {cmd}\n"
        )

        t1 = time.time()
        with open(log_path, "wb") as log:
            log.write(header.encode())
            for line in changed[:40]:
                log.write(f"[dynamo-cargo]   {line}\n".encode())
            log.flush()
            proc = subprocess.run(["bash", "-c", cmd], cwd=SRC_DIR, stdout=log, stderr=subprocess.STDOUT)
            tail = f"[dynamo-cargo] exit {proc.returncode} after {time.time() - t1:.1f}s\n"
            stats = subprocess.run(["sccache", "--show-stats"], capture_output=True, text=True, check=False).stdout
            for line in stats.splitlines():
                if any(k in line for k in ("Compile requests  ", "Cache hits  ", "Cache misses  ", "Non-cacheable calls")):
                    tail += f"[dynamo-cargo] {line.strip()}\n"
            log.write(tail.encode())

        if not os.path.exists(REGISTRY_TAR) and os.path.isdir("/build/cargo/registry/cache"):
            _sh(
                f"tar -c -C /build/cargo registry/cache registry/index | zstd -3 -T0 -o {REGISTRY_TAR}.tmp -f"
                f" && mv {REGISTRY_TAR}.tmp {REGISTRY_TAR}",
                check=False,
            )
        subprocess.run(["sccache", "--stop-server"], check=False, capture_output=True)
        try:
            cache_vol.commit()
        except Exception as exc:
            print(f"[dynamo-cargo] volume commit failed: {exc}", flush=True)
        log_zst = subprocess.run(["zstd", "-3", "-T0", "-c", log_path], check=True, capture_output=True).stdout
        return proc.returncode, log_zst

    @modal.method()
    def save_base(self) -> str:
        """Snapshot this slot's source tree and target dir as the base new slots start from."""
        if not os.path.isdir(TARGET_DIR) or not os.path.isdir(SRC_DIR):
            return "nothing to save: this slot has no built tree (run a build in it first)"
        t0 = time.time()
        self._reload()
        subprocess.run(["sccache", "--stop-server"], check=False, capture_output=True)
        os.makedirs(os.path.dirname(BASE_TAR), exist_ok=True)
        _sh(
            f"tar -c -C / {SRC_DIR.lstrip('/')} {TARGET_DIR.lstrip('/')} {MANIFEST.lstrip('/')} | zstd -1 -T0 -o {BASE_TAR}.tmp -f"
            f" && mv {BASE_TAR}.tmp {BASE_TAR}",
            check=True,
        )
        cache_vol.commit()
        size = os.path.getsize(BASE_TAR) / 1e9
        raw = subprocess.run(["du", "-sh", TARGET_DIR], capture_output=True, text=True).stdout.split()[0]
        return f"saved base snapshot: {size:.1f} GB compressed (target dir {raw}) in {time.time() - t0:.0f}s"

    @modal.method()
    def reset(self) -> str:
        shutil.rmtree(SRC_DIR, ignore_errors=True)
        shutil.rmtree(TARGET_DIR, ignore_errors=True)
        if os.path.exists(MANIFEST):
            os.remove(MANIFEST)
        return f"slot {self.slot}: source tree and target dir deleted"


def _pack_worktree(src_root: str) -> bytes:
    listing = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=src_root, check=True, capture_output=True
    ).stdout
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for rel in listing.decode().split("\0"):
            if not rel or rel.split("/", 1)[0] in SKIP_TOP_DIRS:
                continue
            path = os.path.join(src_root, rel)
            if os.path.islink(path) or os.path.isfile(path):
                tar.add(path, arcname=rel, recursive=False)
    return subprocess.run(["zstd", "-3", "-T0"], input=buf.getvalue(), check=True, capture_output=True).stdout


def _client(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__.split("Deploy (once")[0].strip(), file=sys.stderr)
        print('\nusage: dynamo_cargo.py "<shell command>" | --save-base | --reset', file=sys.stderr)
        return 2
    src = os.path.abspath(os.path.expanduser(os.environ.get("DYNAMO_SRC", "~/dynamo")))
    slot = os.environ.get("DYNAMO_CARGO_SLOT") or os.path.basename(src.rstrip("/")) or "default"
    try:
        cargo = modal.Cls.from_name(APP_NAME, "Cargo")(slot=slot)
        if argv[0] == "--save-base":
            print(f"[dynamo-cargo] slot {slot}: {cargo.save_base.remote()}")
            return 0
        if argv[0] == "--reset":
            print(f"[dynamo-cargo] {cargo.reset.remote()}")
            return 0
        log_out = os.environ.get("DYNAMO_CARGO_LOG")
        if not log_out:
            fd, log_out = tempfile.mkstemp(prefix=f"dynamo_cargo.{slot}.", suffix=".log")
            os.close(fd)
        t0 = time.time()
        code, log_zst = cargo.run.remote(_pack_worktree(src), argv[0])
    except modal.exception.NotFoundError:
        print(f"[dynamo-cargo] app '{APP_NAME}' is not deployed: run `modal deploy {os.path.abspath(__file__)}`", file=sys.stderr)
        return 3
    with open(log_out, "wb") as fp:
        fp.write(subprocess.run(["zstd", "-d", "-c"], input=log_zst, check=True, capture_output=True).stdout)
    print(f"[dynamo-cargo] slot {slot}: exit {code}; {time.time() - t0:.1f}s total; log: {log_out}")
    return code


if __name__ == "__main__":
    sys.exit(_client(sys.argv[1:]))
