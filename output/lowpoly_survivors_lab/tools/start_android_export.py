#!/usr/bin/env python3
"""Start a hidden Godot Android export without exposing EOS values to the shell."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path


LAB_ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--config", default=str(LAB_ROOT / "config" / "eos_config.local.json"))
    parser.add_argument("--apk", default=str(LAB_ROOT / "builds" / "android" / "LowpolySurvivorsLab-debug.apk"))
    parser.add_argument("--stdout", default=str(LAB_ROOT / "builds" / "android" / "export-0.2.5.stdout.log"))
    parser.add_argument("--stderr", default=str(LAB_ROOT / "builds" / "android" / "export-0.2.5.stderr.log"))
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    client_id = str(config.get("client_id", "")).strip()
    if not client_id:
        raise SystemExit("EOS local config has no client_id")

    stdout_path = Path(args.stdout)
    stderr_path = Path(args.stderr)
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["LOWPOLY_EOS_CLIENT_ID"] = client_id
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with stdout_path.open("w", encoding="utf-8") as stdout_file, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_file:
        process = subprocess.Popen(
            [
                args.godot,
                "--headless",
                "--path",
                str(LAB_ROOT),
                "--export-debug",
                "Android arm64",
                args.apk,
            ],
            stdout=stdout_file,
            stderr=stderr_file,
            env=environment,
            creationflags=creation_flags,
        )
    print(f"Android export started PID={process.pid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
