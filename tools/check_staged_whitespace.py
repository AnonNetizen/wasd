#!/usr/bin/env python3
"""Check staged whitespace while excluding user draft directories.

The hook auto-fixes the low-risk "new blank line at EOF" case in staged files,
then reruns git's whitespace checker. Other whitespace issues still fail.
"""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys

EOF_BLANK_RE = re.compile(r"^(?P<path>.+):(?P<line>\d+): new blank line at EOF\.$")


def run_git(
    args: list[str],
    *,
    capture: bool = False,
    data: bytes | None = None,
) -> subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *args],
        check=False,
        input=data,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        text=capture and data is None,
    )


def check_staged() -> subprocess.CompletedProcess[str]:
    return run_git(
        [
            "diff",
            "--cached",
            "--check",
            "--",
            ".",
            ":(exclude)draft/**",
            ":(exclude)DRAFT/**",
        ],
        capture=True,
    )


def eof_blank_paths(output: str) -> set[str]:
    paths: set[str] = set()
    for line in output.splitlines():
        match = EOF_BLANK_RE.match(line)
        if match:
            paths.add(match.group("path"))
    return paths


def trim_eof_blank_lines(content: bytes) -> bytes:
    if not content:
        return content

    newline = b"\r\n" if b"\r\n" in content else b"\n"
    lines = content.splitlines(keepends=True)
    while lines and lines[-1].strip() == b"":
        lines.pop()

    if not lines:
        return b""

    fixed = b"".join(lines)
    if not fixed.endswith((b"\n", b"\r")):
        fixed += newline
    return fixed


def staged_content(path: str) -> bytes:
    completed = subprocess.run(
        ["git", "show", f":{path}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return completed.stdout


def has_unstaged_changes(path: str) -> bool:
    return run_git(["diff", "--quiet", "--", path]).returncode != 0


def stage_fixed_content(path: str, content: bytes) -> None:
    if not has_unstaged_changes(path):
        Path(path).write_bytes(content)
        run_git(["add", "--", path])
        return

    mode_result = run_git(["ls-files", "-s", "--", path], capture=True)
    mode_line = str(mode_result.stdout).splitlines()[0]
    mode = mode_line.split()[0]
    blob_result = run_git(["hash-object", "-w", "--stdin"], capture=True, data=content)
    if isinstance(blob_result.stdout, bytes):
        blob = blob_result.stdout.decode().strip()
    else:
        blob = str(blob_result.stdout).strip()
    run_git(["update-index", "--cacheinfo", mode, blob, path])


def main() -> int:
    completed = check_staged()
    if completed.returncode == 0:
        return 0

    output = completed.stdout or ""
    paths = eof_blank_paths(output)
    if not paths:
        print(output, end="")
        return completed.returncode

    fixed_paths: list[str] = []
    for path in sorted(paths):
        content = staged_content(path)
        fixed = trim_eof_blank_lines(content)
        if fixed != content:
            stage_fixed_content(path, fixed)
            fixed_paths.append(path)

    if fixed_paths:
        print("Auto-fixed blank line at EOF in staged files:")
        for path in fixed_paths:
            print(f"  {path}")

    completed = check_staged()
    if completed.stdout:
        print(completed.stdout, end="")
    return completed.returncode


if __name__ == "__main__":
    sys.exit(main())
