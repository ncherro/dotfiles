#!/usr/bin/env bash
set -euo pipefail

# reclaim docker disk space without slowing down builds or losing data:
#   - removes stopped containers, except ones matching KEEP_CONTAINERS
#   - removes images no remaining container uses (kept containers pin theirs)
#   - removes build cache unused for BUILD_CACHE_MAX_AGE (recent layers stay warm)
#   - never touches volumes
#
# usage: docker-cleanup.sh [-y]    (-y skips the confirmation prompt)

: "${KEEP_CONTAINERS:="^actionloop-"}"     # extended regex matched against container names
: "${BUILD_CACHE_MAX_AGE:="720h"}"         # 30 days

assume_yes=false
[ "${1:-}" = "-y" ] && assume_yes=true

if ! docker info &>/dev/null; then
  echo "ERROR: docker is not running"
  exit 1
fi

echo "BEFORE:"
docker system df
echo

to_remove=()
while IFS=$'\t' read -r name status; do
  if [[ "$status" == Up* ]]; then
    echo "KEEP $name: running"
  elif [[ "$name" =~ $KEEP_CONTAINERS ]]; then
    echo "KEEP $name: matches KEEP_CONTAINERS"
  else
    echo "REMOVE $name: $status"
    to_remove+=("$name")
  fi
done < <(docker ps -a --format '{{.Names}}\t{{.Status}}')

echo
echo "Then: prune images not used by any remaining container,"
echo "      and build cache unused for $BUILD_CACHE_MAX_AGE. Volumes are left alone."
echo

if ! $assume_yes; then
  read -rp "Proceed? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted"; exit 0; }
fi

for name in ${to_remove[@]+"${to_remove[@]}"}; do
  docker rm "$name" >/dev/null && echo "  REMOVED container: $name"
done

echo "  PRUNE images"
docker image prune -a -f | tail -1

echo "  PRUNE build cache older than $BUILD_CACHE_MAX_AGE"
docker builder prune -f --filter "until=$BUILD_CACHE_MAX_AGE" | tail -1

echo
echo "AFTER:"
docker system df
echo
echo "Docker Desktop returns freed space to macOS gradually; restart it if Finder doesn't catch up."
