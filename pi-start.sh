#!/bin/bash
set -euo pipefail

model="${OMLX_MODEL:-Qwen3.6-35B-A3B-MLX-8bit}"
port="${OMLX_PORT:-8000}"
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

exec pi --model "omlx/${model}"
