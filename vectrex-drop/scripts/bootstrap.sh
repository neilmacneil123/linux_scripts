#!/bin/sh
# Local, pinned dependencies. Does not need root or change system packages.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
case "${1:-}" in
    ""|--with-tests) ;;
    *) echo "Usage: sh scripts/bootstrap.sh [--with-tests]" >&2; exit 2 ;;
esac
for command in git make cc python3; do
    command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
mkdir -p tools
fetch_pinned() {
    destination=$1
    remote=$2
    revision=$3
    if [ ! -d "$destination" ]; then
        git init -q "$destination"
        git -C "$destination" remote add origin "$remote"
        git -C "$destination" fetch --depth 1 origin "$revision"
        git -C "$destination" checkout -q --detach FETCH_HEAD
    fi
    actual=$(git -C "$destination" rev-parse HEAD)
    if [ "$actual" != "$revision" ]; then
        echo "Unexpected revision in $destination; preserving your checkout." >&2
        exit 1
    fi
    if [ -n "$(git -C "$destination" status --porcelain --untracked-files=no)" ]; then
        echo "Tracked edits in $destination; preserving your changes." >&2
        exit 1
    fi
}
fetch_pinned tools/lwtools https://github.com/stahta01/LWTools.git a00d389d0a1e47ea54834649d7cc86d17046b4af
make -C tools/lwtools -j2 lwasm
if [ "${1:-}" = --with-tests ]; then
    fetch_pinned tools/vecx https://github.com/jhawthorn/vecx.git 9b2894cacf73bdacaba32cb505289c658d981fd9
fi
make all
