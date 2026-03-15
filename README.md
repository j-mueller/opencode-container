# opencode-container

An OCI container with [opencode](https://opencode.ai/).
This container can be used in agent workflows where you want to give full permissions to the agent but still have some degree of isolation (eg. not being able to see the entire file system).

There are two ways to run it.

## Running the container with nix

This runs the container with the current directory mounted as the home directory.

```bash
nix run github:j-mueller/opencode-container/refs/tags/0.1.4
```

## Running the container with podman

Run the container in interactive mode.
Make sure to mount the directory that you want the agent to work in.

```bash
podman run -it ghcr.io/j-mueller/opencode-container:0.1.4
```

## Running The Container With Host Ollama

The Nix runner in [nix/run-docker-image.nix](nix/run-docker-image.nix) sets up everything to use opencode with Ollama running on the host:

- mounts the current working directory to `/workspace`
- mounts `~/.config/opencode` into the container config directory
- mounts `~/.cache/opencode` into the container cache directory
- runs the container with `--network host`
- sets `OLLAMA_HOST` to `http://127.0.0.1:11434` by default
- writes `~/.config/opencode/opencode.json` on first run if it does not exist yet
- migrates older generated default configs to the current qwen-based default

If your host Ollama is listening somewhere else, override `OLLAMA_HOST` before starting the container.

### Start Ollama On The Host

Start Ollama on the host machine so it listens on the default port:

```bash
ollama serve
```

Make sure the model you want is already available on the host, for example:

```bash
ollama pull qwen3.5:9b
```

The default generated config uses the Ollama provider at `${OLLAMA_HOST}/v1` and selects `ollama/qwen3.5:27b`.
It also includes entries for `qwen3.5:27b`, `qwen3.5:35b`, `qwen3.5:latest`, and `qwen3-coder-next:latest`.
If you prefer a different model, change `~/.config/opencode/opencode.json` or switch models in OpenCode.

### Start Via Nix

From the repository root:

```bash
nix run .#runDockerImage -- opencode
```

To override the Ollama endpoint:

```bash
OLLAMA_HOST=http://127.0.0.1:11434 nix run .#runDockerImage -- opencode
```

Any `opencode` config you keep under `~/.config/opencode` on the host will be visible inside the container. If `~/.config/opencode/opencode.json` does not exist yet, the runner creates one that points to host Ollama. If that file still matches an older generated default, the runner updates it to the current qwen-based default on startup.

### Start Via Podman

If you want to run the image directly with Podman instead of the Nix wrapper, first build and load it:

```bash
nix build .#dockerImage
podman load --input result
```

Then start the container from the repository root. The image is interactive, so `-it` is required for both the default shell and `opencode`:

```bash
podman run --rm -it ghcr.io/j-mueller/opencode-container:latest
```

To launch `opencode` directly:

```bash
podman run --rm -it \
  --workdir /workspace \
  --volume "$PWD:/workspace:Z" \
  --volume "${XDG_CONFIG_HOME:-$HOME/.config}/opencode:/tmp/opencode-container-config/opencode:Z" \
  --volume "${XDG_CACHE_HOME:-$HOME/.cache}/opencode:/tmp/opencode-container-cache/opencode:Z" \
  --env HOME=/tmp/opencode-container-home \
  --env XDG_CONFIG_HOME=/tmp/opencode-container-config \
  --env XDG_CACHE_HOME=/tmp/opencode-container-cache \
  --network host \
  --env OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}" \
  opencode-container:latest \
  opencode
```

If you omit `-it`, the container exits with a short error message instead of starting a broken non-interactive session.
