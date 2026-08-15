#!/bin/bash
# Exercises pi-start.sh model selection and error paths against fixture
# payloads with curl and pi stubbed out, then spec.yaml and the extension's
# behaviour. Needs neither Docker nor a running oMLX.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home"

cat >"$work/bin/pi" <<'EOF'
#!/bin/bash
echo "PI_ARGS: $*"
EOF

cat >"$work/bin/curl" <<'EOF'
#!/bin/bash
# Mimics `curl -s -o FILE -w '%{http_code}'`: copy the fixture, print the code.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
[[ -n "$out" && -f "${FIXTURE:-}" ]] && cp "$FIXTURE" "$out"
printf '%s' "${HTTP_CODE:-200}"
[[ "${HTTP_CODE:-200}" == "000" ]] && exit 7
exit 0
EOF

chmod +x "$work/bin/pi" "$work/bin/curl"

fixture() { printf '%s' "$2" >"$work/$1"; }

# The loaded chat model is deliberately not first, so a "take chat[0]"
# regression is distinguishable from correct loaded-first selection.
fixture loaded.json '{"models":[
 {"id":"bge-reranker-v2-m3","model_type":"reranker","loaded":true},
 {"id":"nomic-embed","model_type":"embedding","loaded":true},
 {"id":"gemma-4-27b","model_type":"llm","loaded":false},
 {"id":"Qwen3.6-35B","model_type":"llm","loaded":true,"max_context_window":32768,"max_tokens":8192},
 {"id":"qwen3-8b:thinking","model_type":"llm","loaded":false},
 {"id":"Qwen3-VL-8B","model_type":"vlm","loaded":false}]}'
fixture none-loaded.json '{"models":[
 {"id":"nomic-embed","model_type":"embedding","loaded":false},
 {"id":"gemma-4-27b","model_type":"llm","loaded":false}]}'
fixture no-chat.json '{"models":[{"id":"nomic-embed","model_type":"embedding","loaded":true}]}'
fixture legacy.json '{"models":[{"id":"legacy-model","loaded":true}]}'
fixture bad-shape.json '{"data":[{"id":"x"}]}'
fixture not-json.json '<html><body>502 Bad Gateway</body></html>'
fixture zero-ctx.json '{"models":[{"id":"m","model_type":"llm","loaded":true,"max_context_window":0}]}'

pass=0
fail=0

# Prints the entrypoint's combined output followed by "exit=N", so assertions
# can cover the exit status as well as the message.
run() { # fixture http_code [omlx_model]
  find "$work/home" -mindepth 1 -delete 2>/dev/null || true
  local output status
  output=$(
    env PATH="$work/bin:$PATH" HOME="$work/home" FIXTURE="$work/$1" \
      HTTP_CODE="$2" OMLX_MODEL="${3:-}" \
      OMLX_CATALOG="$script_dir/extensions/omlx/catalog.mjs" \
      bash "$script_dir/pi-start.sh" 2>&1
  ) && status=0 || status=$?
  printf '%s\nexit=%s' "$output" "$status"
}

expect() { # label expected_substring actual
  if [[ "$3" == *"$2"* ]]; then
    pass=$((pass + 1))
    echo "ok   - $1"
  else
    fail=$((fail + 1))
    echo "FAIL - $1"
    echo "       expected to contain: $2"
    echo "       got: $3"
  fi
}

expect "prefers the loaded chat model over loaded non-chat models" \
  "PI_ARGS: --model omlx/Qwen3.6-35B" "$(run loaded.json 200)"
expect "launches Pi successfully" "exit=0" "$(run loaded.json 200)"
expect "falls back to the first chat model when none are loaded" \
  "PI_ARGS: --model omlx/gemma-4-27b" "$(run none-loaded.json 200)"
expect "accepts a model with no model_type (legacy oMLX)" \
  "PI_ARGS: --model omlx/legacy-model" "$(run legacy.json 200)"
expect "honours a valid OMLX_MODEL pin" \
  "PI_ARGS: --model omlx/gemma-4-27b" "$(run loaded.json 200 gemma-4-27b)"
expect "rejects an OMLX_MODEL pin that oMLX does not serve" \
  'is not served by oMLX' "$(run loaded.json 200 nope-27B-fp16)"
expect "lists valid IDs when a pin is rejected" \
  "available: gemma-4-27b, Qwen3.6-35B" "$(run loaded.json 200 nope-27B-fp16)"
expect "errors when oMLX serves no chat models" \
  "serves no llm or vlm models" "$(run no-chat.json 200)"
expect "errors on an unexpected payload shape" \
  "expected a models array" "$(run bad-shape.json 200)"
expect "reports non-JSON bodies without a stack trace" \
  "returned a non-JSON response" "$(run not-json.json 200)"
expect "echoes the offending body snippet" \
  "502 Bad Gateway" "$(run not-json.json 200)"
expect "distinguishes an unreachable server" \
  "cannot reach oMLX" "$(run loaded.json 000)"
expect "distinguishes an auth rejection from an outage" \
  "skip API key verification" "$(run loaded.json 401)"
expect "surfaces other HTTP failures" \
  "returned HTTP 500" "$(run loaded.json 500)"

# Every error path must abort rather than fall through into launching Pi.
for case in "no-chat.json 200" "bad-shape.json 200" "not-json.json 200" \
  "loaded.json 000" "loaded.json 401" "loaded.json 500"; do
  # shellcheck disable=SC2086  # deliberate word splitting of the case pair
  result="$(run $case)"
  expect "aborts on $case" "exit=1" "$result"
  expect "does not launch Pi on $case" "no-launch" "$(
    [[ "$result" != *PI_ARGS* ]] && echo "no-launch"
  )"
done
expect "aborts on a rejected pin" "exit=1" "$(run loaded.json 200 nope-27B-fp16)"

run loaded.json 200 >/dev/null
config=$(cat "$work/home/.pi/agent/models.json")
expect "passes through the oMLX context window" '"contextWindow": 32768' "$config"
expect "passes through the oMLX max output tokens" '"maxTokens": 8192' "$config"
expect "flags :thinking profiles as reasoning models" '"reasoning": true' "$config"
expect "marks vlm models as image-capable" '"image"' "$config"
expect "sets the local-server compat flags" '"maxTokensField": "max_tokens"' "$config"

# Extension-supplied models are spread verbatim, so every field Pi would
# otherwise default must be present in the shared mapping.
for field in name reasoning input cost contextWindow maxTokens compat; do
  expect "emits a complete entry: $field" "\"$field\"" "$config"
done

run zero-ctx.json 200 >/dev/null
expect "falls back to oMLX's default window when the reported one is unusable" \
  '"contextWindow": 32768' "$(cat "$work/home/.pi/agent/models.json")"

fixture small-model.json '{"models":[
 {"id":"tiny","model_type":"llm","loaded":true,"max_context_window":4096}]}'
run small-model.json 200 >/dev/null
expect "never lets the output budget exceed the context window" \
  '"maxTokens": 4096' "$(cat "$work/home/.pi/agent/models.json")"

# `sbx kit validate` only checks the YAML shape. An empty credential identifier
# passes it and then panics during credential resolution at `sbx run`, so assert
# on the parsed artifact instead of trusting the validator.
if command -v sbx >/dev/null 2>&1; then
  kit_json=$(
    sbx kit pack "$script_dir" -o "$work/kit.tar" >/dev/null 2>&1 &&
      sbx kit inspect "$work/kit.tar" --json 2>/dev/null
  ) || kit_json=""

  if [[ -z "$kit_json" ]]; then
    fail=$((fail + 1))
    echo "FAIL - could not pack or inspect the kit; spec.yaml is unverified"
  else
    # shellcheck disable=SC2016  # single quotes are required: the ${...} below
    # are JS template literals resolved by node, not bash expansions.
    spec=$(printf '%s' "$kit_json" | node -e '
let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  const kit = JSON.parse(raw);
  const creds = kit.credentials ?? [];
  const injects = creds.flatMap((c) => c.apiKey?.inject ?? []);
  const allow = kit.caps?.network?.allow ?? [];
  const out = {
    "schema": kit.manifest?.schemaVersion ?? "missing",
    "empty-service": creds.filter((c) => !c.service).length,
    "inject-rules": injects.length,
    "incomplete-inject": injects.filter((i) => !i.domain || !i.header).length,
    "network-allow-empty": allow.length === 0 ? "yes" : "no",
    "omlx-host-allowed": allow.some((d) => d.startsWith("host.docker.internal:")) ? "yes" : "no",
    "omlx-port-set": kit.environment?.variables?.OMLX_PORT ? "yes" : "no",
    "entrypoint": kit.manifest?.binary ?? "missing",
  };
  for (const [k, v] of Object.entries(out)) console.log(`${k}=${v}`);
});
')
    expect "spec.yaml is kit-spec v2" "schema=2" "$spec"
    expect "every credential has a service identifier" "empty-service=0" "$spec"
    expect "credential injection is configured" "inject-rules=1" "$spec"
    expect "every inject rule has a domain and header" "incomplete-inject=0" "$spec"
    expect "the network allow list survives the schema" "network-allow-empty=no" "$spec"
    expect "oMLX on the host stays reachable" "omlx-host-allowed=yes" "$spec"
    expect "OMLX_PORT reaches the sandbox" "omlx-port-set=yes" "$spec"
    expect "the entrypoint matches the path the Dockerfile installs" \
      "entrypoint=/usr/local/bin/pi-start.sh" "$spec"
  fi

  expect "spec.yaml uses no deprecated fields" "current" "$(
    sbx kit validate "$script_dir" 2>&1 | rg -q "deprecated field" || echo "current"
  )"
else
  echo "skip - sbx not installed; spec.yaml checks skipped"
fi

echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]] || exit 1

echo
echo "--- extension ---"
node --test "$script_dir/test-extension.mjs"
