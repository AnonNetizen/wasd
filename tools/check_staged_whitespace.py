#!/usr/bin/env python3
"""Check staged whitespace while excluding user draft directories."""

from __future__ import annotations

import subprocess
import sys


def main() -> int:
    command = [
        "git",
        "diff",
        "--cached",
        "--check",
        "--",
        ".",
        ":(exclude)draft/**",
        ":(exclude)DRAFT/**",
    ]
    completed = subprocess.run(command, text=True)
    return completed.returncode


if __name__ == "__main__":
    sys.exit(main())
