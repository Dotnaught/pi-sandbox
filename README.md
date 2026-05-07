# pi-sandbox

A Docker sandbox that runs [Pi](https://github.com/mariozechner/pi-coding-agent) — a terminal AI coding agent — backed by a local [oMLX](https://github.com/mariozechner/omlx) model server running on your Mac.

Pi runs inside an isolated container with filesystem isolation enforced by sbx. Network access is set to Open so the sandbox can reach oMLX on the host.

## Prerequisites

- Docker Desktop (macOS or Windows)
- [oMLX](https://github.com/mariozechner/omlx) installed and running on the host at port 8000
- [`sbx`](https://github.com/docker/sandbox) CLI installed
- The model loaded in oMLX: `Qwen3.6-35B-A3B-MLX-8bit` (or update `spec.yaml` to match your loaded model)

## One-time setup

### 1. oMLX: skip API key verification

The sbx proxy routes container traffic through its own localhost, so oMLX sees all requests as coming from `127.0.0.1`. Enable the matching setting so no API key is required:

1. Open the oMLX Admin Dashboard
2. Go to **Global Settings**
3. Set **Skip API key verification** to **On**

### 2. sbx: set network policy to Open

The proxy must be able to reach oMLX on the host:

```sh
sbx policy set-default open
```

### 3. Environment variables

Export these before running:

```sh
export GITHUB_PERSONAL_ACCESS_TOKEN=<your-github-personal-access-token>
export NPM_TOKEN=<your-npm-token>          # optional, only needed for private npm packages
```

### 4. Build and load the image

`sbx` uses its own container runtime and cannot access images built with the host `docker` CLI directly. Build the image and load it into sbx:

```sh
docker build -t pi-sandbox:latest .
docker image save pi-sandbox:latest -o pi-sandbox.tar
sbx template load pi-sandbox.tar
```

## Run

```sh
sbx run --kit . --name pi-sandbox pi
```

Pi connects to oMLX on the host at `host.docker.internal:8000`.

### Linux hosts

`host.docker.internal` is a macOS/Windows Docker Desktop convention. On Linux the name doesn't resolve inside the container. Pass the host gateway mapping when creating the sandbox:

```sh
sbx run --kit . --name pi-sandbox --add-host=host.docker.internal:host-gateway pi
```

## Changing the model

1. Load a different model in oMLX.
2. Update `environment.variables.OMLX_MODEL` in `spec.yaml`.
3. No image rebuild required — the model name is read from the environment at startup.

## Access limitations

| Dimension | Protection | Notes |
|---|---|---|
| Host filesystem | Strong | Container-only; no host volume mounts |
| Local network | Minimal | Open policy; Pi can reach any port on the host via `host.docker.internal` |
| Internet | Minimal | Open policy; Pi can reach any domain |
| Credentials | Proxy-managed | Tokens injected by proxy, never exposed in container env |

Filesystem isolation is the primary protection. Pi runs inside a Docker container with no host volume mounts and as a non-root `agent` user, so it cannot access host files.

Network isolation is weak by design. Open policy (`sbx policy set-default open`) is required for the sbx proxy to reach oMLX on the host. Under Open policy, all outbound traffic is allowed — the `allowedDomains` list in `spec.yaml` is not an enforced allow-list. Its role is to enable credential injection: the sbx proxy automatically adds `GITHUB_PERSONAL_ACCESS_TOKEN` to requests to `api.github.com` and `NPM_TOKEN` to `registry.npmjs.org`, so Pi never sees the real token values.

If tighter network control is needed, you would need to switch to a Balanced or Locked Down sbx policy. That requires a different approach to oMLX connectivity — for example, running oMLX as an internet-accessible service with a real API key rather than relying on the localhost loopback.

## What's in the image

- Base: `docker/sandbox-templates:shell`
- Node.js 26
- `@mariozechner/pi-coding-agent` (global npm install)
- `uv` + `ruff` (Python toolchain)
- `fd` (pre-installed so Pi doesn't download it at runtime)
- `pi-start.sh` — entrypoint that writes Pi's provider config and launches the agent
