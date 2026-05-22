#!/bin/bash
set -euo pipefail

port="${OMLX_PORT:-8000}"

if [[ -n "${OMLX_MODEL:-}" ]]; then
  model="$OMLX_MODEL"
else
  response=$(curl -sf "http://host.docker.internal:${port}/v1/models") \
    || { echo "error: oMLX is not running on host port ${port}" >&2; exit 1; }
  model=$(printf '%s' "$response" \
    | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).data[0].id))") \
    || { echo "error: could not parse model ID from oMLX response" >&2; exit 1; }
fi
config_dir="$HOME/.pi/agent"

mkdir -p "$config_dir"

cat > "$config_dir/models.json" <<EOF
{
  "providers": {
    "omlx": {
      "baseUrl": "http://host.docker.internal:${port}/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "${model}",
          "name": "${model}",
          "reasoning": false,
          "input": ["text"],
          "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
        }
      ]
    }
  }
}
EOF
chmod 600 "$config_dir/models.json"

cat > "$config_dir/settings.json" <<EOF
{"defaultProvider": "omlx", "defaultModel": "${model}"}
EOF

exec pi --model "omlx/${model}" "$@"
