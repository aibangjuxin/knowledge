#!/usr/bin/env python3
"""
Count the REAL visible words in an ELI5 HTML file.

The naive `sed -E 's/<[^>]+>//g' | wc -w` recipe inflates the count by 2-3x
because it includes CSS inside <style>, SVG <text> attributes, and HTML
comments. This script strips all of those before counting.

Usage:
    python3 wordcount.py <file.html>          # prints just the count
    python3 wordcount.py <file.html> --verbose # prints count + the actual text
    python3 wordcount.py <file.html> --budget 250  # warn if over budget

Exit code: 0 if within budget, 1 if over.
"""
import argparse
import re
import sys

TARGET = 250
HARD_CAP = 280


def visible_words(html: str) -> str:
    h = re.sub(r"<style.*?</style>", "", html, flags=re.DOTALL)
    h = re.sub(r"<svg.*?</svg>", "", h, flags=re.DOTALL)
    h = re.sub(r"<!--.*?-->", "", h, flags=re.DOTALL)
    text = re.sub(r"<[^>]+>", " ", h)
    return re.sub(r"\s+", " ", text).strip()


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("file", help="HTML file to count")
    p.add_argument("--verbose", action="store_true", help="print the visible text")
    p.add_argument(
        "--budget",
        type=int,
        default=TARGET,
        help=f"target word budget (default {TARGET})",
    )
    args = p.parse_args()

    try:
        html = open(args.file).read()
    except OSError as e:
        print(f"error: cannot read {args.file}: {e}", file=sys.stderr)
        return 2

    text = visible_words(html)
    n = len(text.split())

    if args.verbose:
        print(f"--- visible text ({n} words) ---")
        print(text)
        print("--- end ---")

    status = "OK"
    if n > HARD_CAP:
        status = "OVER HARD CAP"
    elif n > args.budget:
        status = f"OVER BUDGET ({args.budget})"

    print(f"{args.file}: {n} words  [{status}]")
    return 1 if n > args.budget else 0


if __name__ == "__main__":
    sys.exit(main())