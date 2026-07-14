#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys


SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def normalize_version(value: str) -> str:
    normalized = value.strip().lstrip("vV")
    if re.fullmatch(r"\d+\.\d+", normalized):
        normalized = f"{normalized}.0"
    if not SEMVER_RE.fullmatch(normalized):
        raise ValueError(f"无效的语义版本号：{value}")
    return normalized


def parse_build_number(value: str) -> int:
    normalized = value.strip()
    if not normalized.isdigit():
        raise ValueError(f"构建号必须是非负整数：{value}")
    return int(normalized)


def parse_semver(value: str) -> tuple[int, int, int]:
    normalized = normalize_version(value)
    match = SEMVER_RE.fullmatch(normalized)
    if not match:
        raise ValueError(f"无效的语义版本号：{value}")
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def display_version(version: str) -> str:
    major, minor, patch = parse_semver(version)
    if patch == 0:
        return f"{major}.{minor}"
    return f"{major}.{minor}.{patch}"


def derive_build_versions(
    base_version: str,
    base_build_number: str,
    target_build_number: str,
) -> dict[str, str]:
    major, minor, patch = parse_semver(base_version)
    if patch != 0:
        raise ValueError("基线语义版本必须使用 x.y.0 形式。")
    if minor > 9:
        raise ValueError("固定 0.0 显示样式要求基线次版本号不大于 9。")

    base_build = parse_build_number(base_build_number)
    target_build = parse_build_number(target_build_number)

    # The repo keeps the current display anchor. The next fresh artifact
    # starts from the same display version, then later builds advance by 0.1.
    series_steps = max(target_build - base_build - 1, 0)
    total_tenths = major * 10 + minor + series_steps
    derived_major, derived_minor = divmod(total_tenths, 10)
    semantic_version = f"{derived_major}.{derived_minor}.0"
    display = f"{derived_major}.{derived_minor}"

    return {
        "semanticVersion": semantic_version,
        "displayVersion": display,
        "fullVersion": f"{semantic_version}+{target_build}",
        "buildNumber": str(target_build),
        "baseVersion": normalize_version(base_version),
        "baseBuildNumber": str(base_build),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="次元虾构建版本推导工具")
    subparsers = parser.add_subparsers(dest="command", required=True)

    derive_parser = subparsers.add_parser(
        "derive",
        help="根据基线版本和目标构建号推导语义版本与显示版本",
    )
    derive_parser.add_argument("--base-version", required=True)
    derive_parser.add_argument("--base-build", required=True)
    derive_parser.add_argument("--target-build", required=True)
    derive_parser.add_argument(
        "--format",
        choices=("json", "shell"),
        default="json",
    )
    return parser


def emit_shell(values: dict[str, str]) -> str:
    key_map = {
        "semanticVersion": "SEMANTIC_VERSION",
        "displayVersion": "DISPLAY_VERSION",
        "fullVersion": "FULL_VERSION",
        "buildNumber": "BUILD_NUMBER",
        "baseVersion": "BASE_VERSION",
        "baseBuildNumber": "BASE_BUILD_NUMBER",
    }
    return "\n".join(
        f"{shell_key}={shlex.quote(values[key])}"
        for key, shell_key in key_map.items()
    )


def main() -> int:
    args = build_parser().parse_args()
    try:
        values = derive_build_versions(
            args.base_version,
            args.base_build,
            args.target_build,
        )
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    if args.format == "shell":
        print(emit_shell(values))
    else:
        print(json.dumps(values, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
