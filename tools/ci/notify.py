#!/usr/bin/env python3
"""
Build failure notification helper for AtomZero CI.

Creates a GitHub issue summarizing build failures and optionally posts to a
Slack/Discord webhook if configured.  Invoked from the notify-failure job in
.github/workflows/build.yml via actions/github-script or a direct shell call.

Environment variables (read automatically):
    GITHUB_REPOSITORY     e.g. "atomlife/atom-zero"
    GITHUB_RUN_ID         run ID
    GITHUB_SERVER_URL     e.g. "https://github.com"
    GITHUB_TOKEN          token with `issues:write` scope (for issue creation)
    GITHUB_EVENT_NAME     e.g. "push" or "workflow_dispatch"
    GITHUB_REF            e.g. "refs/tags/v2026.9.0"
    NOTIFY_WEBHOOK_URL    optional Slack/Discord webhook (if set, posts a message)

Usage:
    # Create a GitHub issue
    python3 tools/ci/notify.py --version 2026.9.0 --failed-jobs macos,linux

    # Just print a summary (no GitHub API calls)
    python3 tools/ci/notify.py --dry-run --version 2026.9.0 --failed-jobs macos
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def build_issue_title(version: str, tag: str) -> str:
    if tag:
        return f"Build failed: {tag}"
    if version:
        return f"Build failed: v{version}"
    return f"Build failed: manual run ({datetime.now(timezone.utc).strftime('%Y-%m-%d')})"


def build_issue_body(version: str, tag: str, failed_jobs: list, run_id: str) -> str:
    repo = env("GITHUB_REPOSITORY", "atomlife/atom-zero")
    server = env("GITHUB_SERVER_URL", "https://github.com")
    event = env("GITHUB_EVENT_NAME", "unknown")
    ref = env("GITHUB_REF", "")

    lines = [
        "## AtomZero Build Failure",
        "",
        f"**Version:** `{version or 'N/A'}`",
        f"**Tag:** `{tag or 'N/A'}`",
        f"**Event:** `{event}`",
        f"**Ref:** `{ref}`",
        f"**Run:** [{run_id}]({server}/{repo}/actions/runs/{run_id})",
        "",
        "### Failed Jobs",
        "",
    ]
    if failed_jobs:
        for job in failed_jobs:
            lines.append(f"- `{job}`")
    else:
        lines.append("- (job list not provided)")
    lines.append("")
    lines.append("### Logs")
    lines.append("")
    lines.append(f"Full logs: {server}/{repo}/actions/runs/{run_id}")
    lines.append("")
    lines.append("---")
    lines.append("_This issue was automatically created by the CI build workflow._")
    return "\n".join(lines)


def create_github_issue(title: str, body: str, labels: list) -> dict:
    """Create a GitHub issue via the REST API. Returns the API response."""
    repo = env("GITHUB_REPOSITORY")
    token = env("GITHUB_TOKEN")
    if not repo:
        raise RuntimeError("GITHUB_REPOSITORY is not set")
    if not token:
        raise RuntimeError("GITHUB_TOKEN is not set")

    url = f"https://api.github.com/repos/{repo}/issues"
    payload = {
        "title": title,
        "body": body,
        "labels": labels or ["build-failure"],
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API error {e.code}: {body_text}") from e


def post_webhook(url: str, title: str, body: str) -> None:
    """Post a message to a Slack-compatible webhook URL."""
    payload = {"text": f"*{title}*\n\n{body}"}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
    except urllib.error.URLError as e:
        print(f"[notify] WARNING: webhook post failed: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Send build-failure notifications.")
    parser.add_argument("--version", default="", help="Game version that was built")
    parser.add_argument("--tag", default="", help="Git tag (e.g. v2026.9.0)")
    parser.add_argument(
        "--failed-jobs",
        default="",
        help="Comma-separated list of failed job names",
    )
    parser.add_argument(
        "--labels",
        default="build-failure",
        help="Comma-separated GitHub issue labels",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the issue body without creating it",
    )
    args = parser.parse_args()

    failed_jobs = [j.strip() for j in args.failed_jobs.split(",") if j.strip()]
    labels = [l.strip() for l in args.labels.split(",") if l.strip()]
    run_id = env("GITHUB_RUN_ID", "unknown")

    title = build_issue_title(args.version, args.tag)
    body = build_issue_body(args.version, args.tag, failed_jobs, run_id)

    if args.dry_run:
        print("=" * 60)
        print(f"TITLE: {title}")
        print("=" * 60)
        print(body)
        print("=" * 60)
        return

    webhook_url = env("NOTIFY_WEBHOOK_URL", "")
    if webhook_url:
        post_webhook(webhook_url, title, body)
        print(f"[notify] Posted to webhook")

    if env("GITHUB_TOKEN") and env("GITHUB_REPOSITORY"):
        issue = create_github_issue(title, body, labels)
        print(f"[notify] Created issue: {issue.get('html_url', 'unknown')}")
    else:
        print("[notify] GITHUB_TOKEN or GITHUB_REPOSITORY not set; printing body only")
        print(body)


if __name__ == "__main__":
    main()
