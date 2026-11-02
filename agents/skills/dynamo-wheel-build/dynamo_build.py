"""Ultra-fast Dynamo wheel builds on Modal with a shared sccache.

Usage:
    modal run ~/modal/dynamo_build.py                  # build ~/dynamo HEAD/worktree
    DYNAMO_SRC=/path/to/worktree modal run ~/modal/dynamo_build.py
    modal volume get dynamo-wheels / ./wheels          # fetch wheels after build

Layout:
    dynamo-build-cache volume: /cache/sccache (SCCACHE_DIR, shared across machines),
                               /cache/cargo   (CARGO_HOME registry/git cache)
    dynamo-wheels volume:      /out           (maturin --out, fetched locally after)
    CARGO_TARGET_DIR stays on ephemeral container disk (fast NVMe); sccache makes
    rebuilds hit the shared cache anyway.
"""
import os
import subprocess

import modal

SRC = os.path.abspath(os.path.expanduser(os.environ.get("DYNAMO_SRC", "~/dynamo")))

app = modal.App("dynamo-wheel-build")

cache_vol = modal.Volume.from_name("dynamo-build-cache", create_if_missing=True)
wheel_vol = modal.Volume.from_name("dynamo-wheels", create_if_missing=True)

IGNORE = [
    ".git",
    "target",
    "**/target",
    ".venv",
    "**/.venv",
    "node_modules",
    "**/node_modules",
    ".tmp-*",
    "*.whl",
]

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
    )
    .run_commands(
        # uv for fast python-side installs
        "curl -LsSf https://astral.sh/uv/install.sh | sh",
        # pinned toolchain matching rust-toolchain.toml
        "curl --proto '=https' -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.96.1 --profile minimal",
        # prebuilt sccache binary (matches container/use-sccache.sh version)
        "curl -L https://github.com/mozilla/sccache/releases/download/v0.14.0/sccache-v0.14.0-x86_64-unknown-linux-musl.tar.gz | tar xz --strip-components=1 -C /usr/local/bin --wildcards '*/sccache'",
        # jammy protoc is 3.12, too old for proto3 optional; use upstream binary
        "curl -L -o /tmp/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v25.8/protoc-25.8-linux-x86_64.zip && unzip -o /tmp/protoc.zip -d /usr/local && rm /tmp/protoc.zip",
        "/root/.local/bin/uv tool install maturin",
    )
    .env(
        {
            "PATH": "/root/.cargo/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            # shared caches on the volume
            "SCCACHE_DIR": "/cache/sccache",
            "SCCACHE_CACHE_SIZE": "200G",
            "SCCACHE_IDLE_TIMEOUT": "0",
            "CARGO_HOME": "/cache/cargo",
            "RUSTC_WRAPPER": "sccache",
            "CARGO_INCREMENTAL": "0",
            # workspace sets codegen-units=1 (serial, max-perf). 16 keeps thin
            # LTO but parallelizes codegen; set DYNAMO_CGU=1 for perf builds.
            "CARGO_PROFILE_RELEASE_CODEGEN_UNITS": os.environ.get("DYNAMO_CGU", "16"),
            # target persists on the volume: warm rebuilds skip unchanged crates
            # entirely instead of replaying rustc through sccache
            "CARGO_TARGET_DIR": "/cache/target",
            # env RUSTFLAGS replaces .cargo/config.toml rustflags, so the repo's
            # own flags (v3, ffp, tokio_unstable) must be repeated here
            "RUSTFLAGS": "-C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3 -C force-frame-pointers=yes --cfg tokio_unstable",
        }
    )
    .add_local_dir(SRC, "/src/dynamo", ignore=IGNORE)
)


@app.function(
    image=img,
    volumes={"/cache": cache_vol, "/out": wheel_vol},
    cpu=32,
    memory=65536,
    timeout=3600,
)
def build_wheel(sha: str) -> str:
    subprocess.run(
        [
            "bash",
            "-c",
            "set -euo pipefail; "
            "cd /src/dynamo/lib/bindings/python && "
            f"maturin build --release --out /out/{sha} && "
            "sccache --show-stats",
        ],
        check=True,
    )
    wheel_vol.commit()
    return sha


@app.local_entrypoint()
def main() -> None:
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=SRC
    ).stdout.strip() or "no-git"
    diff_hash = subprocess.run(
        ["bash", "-c", "git diff | sha256sum | cut -d' ' -f1"],
        capture_output=True, text=True, cwd=SRC,
    ).stdout.strip()
    print(f"Building {SRC} @ {sha} (diff {diff_hash[:16]})")
    tag = f"{sha}-d{diff_hash[:12]}"
    build_wheel.remote(tag)
    print(f"\nDone. Wheels are on volume 'dynamo-wheels' under /{tag}/")
    print(f"Fetch with:  modal volume get dynamo-wheels {tag} ./wheels-{sha[:8]}")
