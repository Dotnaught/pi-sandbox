# pi-sandbox

A Docker sandbox that runs [Pi](https://github.com/earendil-works/pi/tree/main/packages/coding-agent) — a terminal AI coding agent — backed by a local [oMLX](https://github.com/jundot/omlx) model server running on your Mac.

Pi runs inside an isolated container with filesystem isolation enforced by sbx. Network access is set to Open so the sandbox can reach oMLX on the host.

## Prerequisites

**macOS (Apple Silicon) only.** oMLX is built on Apple's MLX framework and does not run on Linux or Windows.

- Docker Desktop for Mac
- [oMLX](https://github.com/jundot/omlx) installed and running on the host at port 8000
- [`sbx`](https://github.com/docker/sandbox) CLI installed
- At least one LLM or VLM model available in oMLX

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

### 3. GitHub token

Store the token in sbx's secret keychain. The proxy injects it into requests to
`api.github.com`, so it never enters the sandbox:

```sh
sbx secret set github          # prompts, or: sbx secret import
```

Optional — without it, GitHub API calls from the sandbox are unauthenticated
(60 requests/hour, public repos only). An exported environment variable is not a
substitute: `spec.yaml` resolves this credential from the keychain only.

Private npm packages are not wired up. `npm` is not one of sbx's built-in secret
services, so it would need `sbx secret set-custom` plus a matching `credentials`
entry in `spec.yaml`.

### 4. Build and load the image

`sbx` uses its own container runtime and cannot access images built with the host `docker` CLI directly. Build the image and load it into sbx:

```sh
docker build -t pi-sandbox:latest .
docker image save pi-sandbox:latest -o pi-sandbox.tar
sbx template load pi-sandbox.tar
```

### Updating Pi

The Pi version is pinned in the Dockerfile and installed at build time, so the sandbox never updates itself. To see whether a newer release exists:

```sh
./check-pi-version.sh
```

It compares the pin against the npm registry and exits 0 when current, 1 when an update is available, and 2 on error. Applying an update means bumping the pin, rebuilding, and running `sbx rm pi-sandbox` — which destroys that sandbox's session history.

### Tests

```sh
./test.sh
```

Covers `pi-start.sh` model selection and error paths against fixture payloads with `curl` and `pi` stubbed out, then the extension's refresh behaviour. Needs neither Docker nor a running oMLX.

## Run

```sh
sbx run --kit /path/to/pi-sandbox --name pi-sandbox pi /path/to/project
```

Two separate paths are involved:

- **`--kit`** — always points to this repo (the sandbox config containing `spec.yaml`). Required on every `sbx run` invocation, not just the first.
- **Positional path** — the project directory Pi will work in. sbx mounts it into the container.

For example, to run Pi against `~/Code/repos/myapp`:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi ~/Code/repos/myapp
```

Mount additional directories by appending more paths. Add `:ro` to mount read-only:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi ~/Code/repos/myapp ~/docs:ro
```

To persist skills and extensions across sandbox recreations, mount your global Pi config directory read-only alongside the project:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi \
  ~/Code/repos/myapp \
  /Users/<username>/.pi/agent:ro
```

Use the absolute path — sbx mounts directories at their literal host path inside the container, not remapped to the container user's home. Replace `<username>` with your macOS username (`whoami` will print it).

For Pi to discover extensions from the mount, add the absolute path explicitly to `~/.pi/agent/settings.json` on your Mac:

```json
{
  "extensions": [
    "/Users/<username>/.pi/agent/extensions"
  ]
}
```

Pi reads this settings file from the mount at startup and loads extensions from the specified path. Skills in `/Users/<username>/.pi/agent/skills/` are discovered automatically without any settings change.

Pi connects to oMLX on the host at `host.docker.internal:8000`.

### Path casing must match exactly

macOS is case-insensitive, so `cd ~/code/repos/myapp` works even when the directory is really `~/Code/repos/myapp`. sbx exposes the host filesystem inside a Linux VM, which is case-sensitive, so a mismatched path fails to resolve there.

The bind mount then fails with only a warning in the sandbox daemon log, the sandbox is still created, and the agent dies immediately:

```
OCI runtime exec failed: chdir to `/Users/<username>/code/repos/myapp`: No such file or directory
ERROR: agent exited with code 127
```

Passing `.` does not avoid this. It expands to `$PWD`, which keeps whatever casing you typed when you changed into the directory.

In zsh, `${PWD:A}` resolves against the filesystem and returns the true on-disk names, so it corrects the casing for you:

```sh
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi "${PWD:A}" /Users/<username>/.pi/agent:ro
```

Quote it with single quotes when putting this in an alias, so it re-evaluates on each invocation. Note that `realpath` and Python's `os.path.realpath` are not substitutes — on macOS both return the path as typed, casing errors intact.

Recovering from a failed run means deleting the sandbox and recreating it, since the workspace mount is fixed at creation time.

### Resuming a session

The sandbox container keeps running after you quit Pi, and Pi persists session history per project directory inside the container. To resume where you left off:

```sh
# Continue the most recent session
sbx run --kit ~/Code/repos/pi-sandbox pi-sandbox -- --continue

# Pick a session interactively
sbx run --kit ~/Code/repos/pi-sandbox pi-sandbox -- --resume
```

`--kit` is required every time — sbx uses it to locate the "pi" agent definition in `spec.yaml`. Without it, sbx doesn't recognise "pi" as a valid agent and fails.

Starting without `--continue` or `--resume` starts a fresh session but does not delete previous ones.

### Switching to a different project

Workspace mounts are fixed at creation time. To work on a different project directory, delete the sandbox and recreate it:

```sh
sbx rm pi-sandbox
sbx run --kit ~/Code/repos/pi-sandbox --name pi-sandbox pi ~/Code/repos/other-project
```

Deleting the sandbox also destroys all session history stored inside it.

## Changing the model

Nothing to configure — Pi tracks oMLX in two stages.

At container start, `pi-start.sh` reads `/v1/models/status` and seeds `models.json`
with every LLM and VLM oMLX serves, defaulting to one that is already loaded. That
seed exists so `pi --model` resolves before any refresh, and so the sandbox keeps
working if oMLX goes away mid-session.

The `omlx` extension (`extensions/omlx/`) then registers a provider with a
`refreshModels` callback. Pi calls it at session start and every time the model
picker opens, replacing the seed with a fresh read of `/v1/models/status`. So a
model downloaded, or a context window changed, in the oMLX admin panel is picked up
by opening `/model` — no restart, no rebuild.

Context limits come along with it. oMLX rejects prompts above its
`max_context_window` (32768 by default); without that value Pi assumes 128k and
would not compact the session in time.

Refresh is not continuous: an admin-panel change does not reach a conversation
already in flight until the next refresh, and the current turn's budget is already
fixed. Setting `PI_OFFLINE` disables network refresh entirely, leaving only the seed.

If oMLX is unreachable when a refresh runs, Pi warns (`Could not refresh omlx;
searching cached models`) and keeps the catalog it already has, so the session
carries on with the seed.

To pin one model, set `environment.variables.OMLX_MODEL` in `spec.yaml` to an exact
model ID. Startup fails with the list of valid IDs if it does not match. Pinning sets
the default model; it does not hide the others from `/model`.

## Access limitations

| Dimension | Protection | Notes |
|---|---|---|
| Host filesystem | Strong | Container-only; no host volume mounts |
| Local network | Minimal | Open policy; Pi can reach any port on the host via `host.docker.internal` |
| Internet | Minimal | Open policy; Pi can reach any domain |
| Credentials | Proxy-managed | Tokens injected by proxy, never exposed in container env |

Filesystem isolation is the primary protection. Pi runs inside a Docker container with no host volume mounts and as a non-root `agent` user, so it cannot access host files.

Network isolation is weak by design. Open policy (`sbx policy set-default open`) is required for the sbx proxy to reach oMLX on the host. Under Open policy, all outbound traffic is allowed — the `permissions.network.allow` list in `spec.yaml` is not an enforced allow-list. Its role is to enable credential injection: the sbx proxy adds the stored `github` secret to requests to `api.github.com`, so Pi never sees the real token value.

If tighter network control is needed, you would need to switch to a Balanced or Locked Down sbx policy. That requires a different approach to oMLX connectivity — for example, running oMLX as an internet-accessible service with a real API key rather than relying on the localhost loopback.

## Global instructions (CLAUDE.md)

`CLAUDE.md` in this repo is copied into the image at `~/.pi/agent/CLAUDE.md`. Pi loads it at startup for every session, regardless of which project it's working in. Edit it to set coding standards, tool preferences, commit conventions, and anything else Pi should always follow.

For project-specific instructions, add a `CLAUDE.md` or `AGENTS.md` to the project repo. Pi walks up the directory tree from the working directory and loads all matches, so project files layer on top of the global one automatically — no sandbox changes needed.

After editing `CLAUDE.md`, rebuild the image (step 4 in [One-time setup](#4-build-and-load-the-image)).

## Adding skills

Skills are Markdown files that give Pi specialized knowledge and workflows. The recommended approach is to keep them on the host so they survive sandbox recreation and take effect immediately without a rebuild.

Create a skill at `~/.pi/agent/skills/<name>/SKILL.md` on your Mac:

```markdown
---
name: <name>
description: <what the skill does and when to use it>
---

# Instructions for Pi...
```

Then mount `/Users/<username>/.pi/agent` read-only when starting the sandbox (see [Run](#run)). Pi discovers skills from that path automatically — no settings change required.

Pi loads the name and description of all available skills at startup. It reads the full instructions when a task matches the description, or when you invoke the skill explicitly with `/skill:<name>`.

### Bundled skills

Skills in `skills/<name>/SKILL.md` in this repo are copied into the image at `~/.pi/agent/skills/` during build. These are available even without the host mount, but require a rebuild to update.

## What's in the image

- Base: `docker/sandbox-templates:shell`
- Node.js 26
- `@earendil-works/pi-coding-agent@0.74.0` (global npm install)
- `uv` + `ruff` (Python toolchain)
- `fd` (pre-installed so Pi doesn't download it at runtime)
- `pi-start.sh` — entrypoint that writes Pi's provider config and launches the agent
- `skills/` — bundled skills copied to `~/.pi/agent/skills/`
- `CLAUDE.md` — global instructions copied to `~/.pi/agent/CLAUDE.md`
