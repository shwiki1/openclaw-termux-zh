#!/usr/bin/env python3
"""Mirror built APK artifacts to a Gitee release.

The Gitee v5 API accepts the access token as a form/query parameter. This
script keeps the token out of command lines and logs by reading it from the
environment and only adding it to request bodies.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import uuid
from pathlib import Path
from typing import Any
from urllib import error, parse, request


API_ROOT = "https://gitee.com/api/v5"


class GiteeError(RuntimeError):
    pass


def read_json_response(response: Any) -> Any:
    data = response.read()
    if not data:
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise GiteeError(f"Gitee returned non-JSON response: {data[:200]!r}") from exc


def request_json(method: str, path: str, token: str, fields: dict[str, str] | None = None) -> Any:
    fields = dict(fields or {})
    fields["access_token"] = token

    body = None
    headers = {"Accept": "application/json"}
    url = f"{API_ROOT}{path}"
    if method == "GET":
        url = f"{url}?{parse.urlencode(fields)}"
    else:
        body = parse.urlencode(fields).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    req = request.Request(url, data=body, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=60) as response:
            return read_json_response(response)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise GiteeError(f"Gitee {method} {path} failed with HTTP {exc.code}: {detail}") from exc
    except error.URLError as exc:
        raise GiteeError(f"Gitee {method} {path} failed: {exc.reason}") from exc


def multipart_upload(path: str, token: str, file_path: Path) -> Any:
    boundary = f"----openclaw-{uuid.uuid4().hex}"
    file_name = file_path.name
    content_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"

    chunks: list[bytes] = []
    for name, value in {"access_token": token}.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("ascii"),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("ascii"),
                value.encode("utf-8"),
                b"\r\n",
            ]
        )
    chunks.extend(
        [
            f"--{boundary}\r\n".encode("ascii"),
            f'Content-Disposition: form-data; name="file"; filename="{file_name}"\r\n'.encode("utf-8"),
            f"Content-Type: {content_type}\r\n\r\n".encode("ascii"),
            file_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode("ascii"),
        ]
    )
    body = b"".join(chunks)
    req = request.Request(
        f"{API_ROOT}{path}",
        data=body,
        headers={
            "Accept": "application/json",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
        },
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=300) as response:
            return read_json_response(response)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise GiteeError(f"Gitee upload failed with HTTP {exc.code}: {detail}") from exc
    except error.URLError as exc:
        raise GiteeError(f"Gitee upload failed: {exc.reason}") from exc


def get_release(owner: str, repo: str, token: str, tag: str) -> dict[str, Any] | None:
    encoded_tag = parse.quote(tag, safe="")
    try:
        release = request_json("GET", f"/repos/{owner}/{repo}/releases/tags/{encoded_tag}", token)
        return release if isinstance(release, dict) else None
    except GiteeError as exc:
        if "HTTP 404" in str(exc):
            return None
        raise


def create_release(
    owner: str,
    repo: str,
    token: str,
    tag: str,
    name: str,
    body: str,
    target_commitish: str,
) -> dict[str, Any]:
    release = request_json(
        "POST",
        f"/repos/{owner}/{repo}/releases",
        token,
        {
            "tag_name": tag,
            "name": name,
            "body": body,
            "prerelease": "false",
            "target_commitish": target_commitish,
        },
    )
    if not isinstance(release, dict) or "id" not in release:
        raise GiteeError(f"Gitee release creation returned unexpected payload: {release!r}")
    return release


def find_existing_asset(release: dict[str, Any], file_name: str) -> dict[str, Any] | None:
    for key in ("attach_files", "assets"):
        value = release.get(key)
        if not isinstance(value, list):
            continue
        for asset in value:
            if isinstance(asset, dict) and asset.get("name") == file_name:
                return asset
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mirror APK artifacts to a Gitee release")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--body", default="")
    parser.add_argument("--target-commitish", default="main")
    parser.add_argument("--artifact-dir", default="artifacts")
    parser.add_argument("--token-env", default="GITEE_TOKEN")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = os.environ.get(args.token_env)
    if not token:
        print(f"{args.token_env} is not configured; skipping Gitee mirror.")
        return 0

    artifact_dir = Path(args.artifact_dir)
    apk_files = sorted(artifact_dir.glob("*.apk"))
    if not apk_files:
        raise GiteeError(f"No APK files found in {artifact_dir}")

    release = get_release(args.owner, args.repo, token, args.tag)
    if release is None:
        release = create_release(
            args.owner,
            args.repo,
            token,
            args.tag,
            args.name,
            args.body,
            args.target_commitish,
        )
        print(f"Created Gitee release {args.tag}.")
    else:
        print(f"Using existing Gitee release {args.tag}.")

    release_id = release.get("id")
    if release_id is None:
        raise GiteeError("Gitee release payload did not include an id")

    for apk_file in apk_files:
        existing = find_existing_asset(release, apk_file.name)
        if existing is not None:
            print(f"Gitee asset already exists; skipping {apk_file.name}.")
            continue
        print(f"Uploading {apk_file.name} to Gitee release {args.tag}.")
        multipart_upload(f"/repos/{args.owner}/{args.repo}/releases/{release_id}/attach_files", token, apk_file)

    print("Gitee mirror step completed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GiteeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
