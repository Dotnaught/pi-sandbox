# pi-sandbox

A Docker sandbox that runs [Pi](https://github.com/mariozechner/pi-coding-agent) — a terminal AI coding agent — backed by a local [oMLX](https://github.com/mariozechner/omlx) model server running on your Mac.

Pi runs inside an isolated container with access only to the GitHub API, npm registry, PyPI, and your local oMLX server. All other network traffic is blocked.

## Prerequisites

- Docker Desktop (macOS or Windows)
- [oMLX](https://github.com/mariozechner/omlx) installed and running on the host at port 8000
- [`sbx`](https://github.com/docker/sandbox) CLI installed
- The model loaded in oMLX: `Qwen3.6-35B-A3B-MLX-8bit` (or update `spec.yaml` to match your loaded model)

## Environment variables

Export these before running:

```sh
export OMLX_API_KEY=<your-omlx-api-key>
export GITHUB_TOKEN=<your-github-personal-access-token>
export NPM_TOKEN=<your-npm-token>          # optional, only needed for private npm packages
```

## Build the image

```sh
docker build -t pi-sandbox:latest .
```

## Run

```sh
sbx run spec.yaml
```

This starts a Pi session inside the sandbox. Pi connects to oMLX on the host at `host.docker.internal:8000`.

### Linux hosts

`host.docker.internal` is a macOS/Windows Docker Desktop convention. On Linux, pass the extra flag:

```sh
sbx run --add-host=host.docker.internal:host-gateway spec.yaml
```

## Changing the model

1. Load a different model in oMLX.
2. Update `spec.yaml` in two places:
   - `agent.entrypoint.run` — the `--model` flag
   - `environment.variables.OMLX_MODEL`
3. Rebuild the image if the model ID affects the startup config.

## What's in the image

- Base: `docker/sandbox-templates:shell`
- Node.js 22
- `@mariozechner/pi-coding-agent` (global npm install)
- `uv` + `ruff` (Python toolchain)

## Network access

The sandbox allows outbound connections only to:

| Destination | Purpose |
|---|---|
| `host.docker.internal:8000` | oMLX model server |
| `*.github.com`, `*.githubusercontent.com` | GitHub API and raw content |
| `registry.npmjs.org`, `*.npmjs.com` | npm registry |
| `pypi.org`, `files.pythonhosted.org` | PyPI |
