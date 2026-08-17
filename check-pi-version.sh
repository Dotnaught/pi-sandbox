#!/bin/bash
set -euo pipefail

# Exit status: 0 up to date, 1 update available, 2 error.

package="@earendil-works/pi-coding-agent"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile="$repo_dir/Dockerfile"

fail() {
  echo "error: $1" >&2
  exit 2
}

command -v node >/dev/null || fail "node is required to parse the npm registry response"
[[ -f "$dockerfile" ]] || fail "no Dockerfile at $dockerfile"

pinned=$(sed -n "s|.*${package}@\([0-9][0-9.]*\).*|\1|p" "$dockerfile")
[[ -n "$pinned" ]] || fail "no pinned ${package} version found in $dockerfile"

response=$(curl -sf "https://registry.npmjs.org/${package}/latest") ||
  fail "could not reach the npm registry"
latest=$(printf '%s' "$response" |
  node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).version))") ||
  fail "could not parse the version from the npm registry response"

echo "pinned: $pinned"
echo "latest: $latest"

if [[ "$pinned" == "$latest" ]]; then
  echo "pi is up to date"
  exit 0
fi

cat <<EOF

An update is available. To apply it, bump the pin in Dockerfile to $latest,
then from the repo root:

  docker build -t pi-omlx-sandbox:latest .
  docker image save pi-omlx-sandbox:latest -o pi-omlx-sandbox.tar
  sbx template load pi-omlx-sandbox.tar
  sbx rm pi-omlx-sandbox

Recreating the sandbox destroys its session history.
EOF
exit 1
