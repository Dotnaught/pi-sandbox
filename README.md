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
sbx run --kit /path/to/pi-sandbox --name pi-sandbox pi /path/to/project
```

Two separate paths are involved:

- **`--kit`** — always points to this repo (the sandbox config containing `spec.yaml`). Never the project.
- **Positional path** — the project directory Pi will work in. sbx mounts it into the container.

For example, to run Pi against `~/code/repos/myapp`:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi ~/code/repos/myapp
```

Mount additional directories by appending more paths. Add `:ro` to mount read-only:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi ~/code/repos/myapp ~/docs:ro
```

Pi connects to oMLX on the host at `host.docker.internal:8000`.

### Linux hosts

`host.docker.internal` is a macOS/Windows Docker Desktop convention. On Linux the name doesn't resolve inside the container. Pass the host gateway mapping when creating the sandbox:

```sh
sbx run --kit /path/to/pi-sandbox --name pi-sandbox --add-host=host.docker.internal:host-gateway pi /path/to/project
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

## Global instructions (CLAUDE.md)

`CLAUDE.md` in this repo is copied into the image at `~/.pi/agent/CLAUDE.md`. Pi loads it at startup for every session, regardless of which project it's working in. Edit it to set coding standards, tool preferences, commit conventions, and anything else Pi should always follow.

For project-specific instructions, add a `CLAUDE.md` or `AGENTS.md` to the project repo. Pi walks up the directory tree from the working directory and loads all matches, so project files layer on top of the global one automatically — no sandbox changes needed.

After editing `CLAUDE.md`, rebuild the image (step 4 in [One-time setup](#4-build-and-load-the-image)).

## Adding skills

Skills are Markdown files that give Pi specialized knowledge and workflows. They live in `skills/<name>/SKILL.md` in this repo and are copied into the image at `~/.pi/agent/skills/` during build.

To add a skill, create `skills/<name>/SKILL.md` with this structure:

```markdown
---
name: <name>
description: <what the skill does and when to use it>
---

# Instructions for Pi...
```

Pi loads the name and description of all available skills at startup. It reads the full instructions when a task matches the description, or when you invoke the skill explicitly with `/skill:<name>`.

After adding or changing a skill, rebuild the image (steps 4 in [One-time setup](#4-build-and-load-the-image)).

## What's in the image

- Base: `docker/sandbox-templates:shell`
- Node.js 26
- `@mariozechner/pi-coding-agent` (global npm install)
- `uv` + `ruff` (Python toolchain)
- `fd` (pre-installed so Pi doesn't download it at runtime)
- `pi-start.sh` — entrypoint that writes Pi's provider config and launches the agent
- `skills/` — bundled skills copied to `~/.pi/agent/skills/`
- `CLAUDE.md` — global instructions copied to `~/.pi/agent/CLAUDE.md`
