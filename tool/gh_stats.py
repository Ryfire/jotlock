#!/usr/bin/env python3
"""JotLock GitHub traction snapshot.

Reads repo traffic through the authenticated `gh` CLI (no tokens, no
third-party dependencies). Nothing here tracks users or ships in the app —
it only reads numbers GitHub already collects.

Usage:
    python tool/gh_stats.py             print the current snapshot
    python tool/gh_stats.py --save      print + append to docs/stats_history.md
    python tool/gh_stats.py --repo owner/name

GitHub keeps only 14 days of views/clones server-side; --save exists so a
human can keep the long-term record GitHub won't.
"""
import argparse
import datetime as dt
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HISTORY = ROOT / "docs" / "stats_history.md"


def gh_api(path):
    out = subprocess.run(
        ["gh", "api", path],
        capture_output=True, text=True, check=True,
        encoding="utf-8", errors="replace",
    )
    return json.loads(out.stdout)


def fetch(repo):
    return {
        "repo": gh_api(f"repos/{repo}"),
        "views": gh_api(f"repos/{repo}/traffic/views"),
        "clones": gh_api(f"repos/{repo}/traffic/clones"),
        "referrers": gh_api(f"repos/{repo}/traffic/popular/referrers"),
        "releases": gh_api(f"repos/{repo}/releases?per_page=100"),
    }


def total_downloads(releases):
    return sum(
        asset["download_count"]
        for release in releases
        for asset in release.get("assets", [])
    )


def snapshot_text(repo, data):
    info = data["repo"]
    views, clones = data["views"], data["clones"]
    lines = [
        f"JotLock - {repo} - {dt.date.today().isoformat()}",
        f"  Views:  {views['count']:,} ({views['uniques']:,} unique visitors, last 14 days)",
        f"  Clones: {clones['count']:,} ({clones['uniques']:,} unique, last 14 days)",
        f"  APK downloads (lifetime, all releases): {total_downloads(data['releases']):,}",
        f"  Stars {info['stargazers_count']:,} | Forks {info['forks_count']:,} | Watchers {info['subscribers_count']:,}",
    ]
    if data["referrers"]:
        lines.append("  Top sources:")
        for ref in data["referrers"][:5]:
            lines.append(f"    {ref['referrer']}: {ref['count']} views ({ref['uniques']} unique)")
    else:
        lines.append("  Top sources: none recorded yet")
    return "\n".join(lines)


def history_block(data):
    info = data["repo"]
    views, clones = data["views"], data["clones"]
    return (
        f"\n## {dt.date.today().isoformat()}\n\n"
        f"Views {views['count']} ({views['uniques']} unique) · "
        f"Clones {clones['count']} ({clones['uniques']} unique) · "
        f"APK downloads {total_downloads(data['releases'])} · "
        f"Stars {info['stargazers_count']} · Forks {info['forks_count']}\n"
    )


def main():
    parser = argparse.ArgumentParser(description="JotLock GitHub traction snapshot")
    parser.add_argument("--repo", default="Ryfire/jotlock")
    parser.add_argument(
        "--save", action="store_true",
        help="append the snapshot to docs/stats_history.md",
    )
    args = parser.parse_args()

    try:
        data = fetch(args.repo)
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(
            f"gh api failed ({exc.returncode}). Logged in? Check `gh auth status`.\n"
        )
        if exc.stderr:
            sys.stderr.write(exc.stderr)
        return 1

    print(snapshot_text(args.repo, data))

    if args.save:
        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        if not HISTORY.exists():
            HISTORY.write_text(
                "# JotLock — stats history\n\n"
                "Snapshots of GitHub traffic. GitHub only keeps 14 days of\n"
                "views/clones server-side; this file is the long-term record.\n"
                "Append with: python tool/gh_stats.py --save\n",
                encoding="utf-8",
            )
        with HISTORY.open("a", encoding="utf-8") as fh:
            fh.write(history_block(data))
        print(f"\nAppended to {HISTORY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())