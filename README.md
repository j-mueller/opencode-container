# opencode-container

## Running The Container With Host Ollama

The container image includes `opencode`, but not `ollama`. The intended setup is:

- run Ollama on the host
- expose it to the container via `OLLAMA_HOST`
- keep your `opencode` config on the host and mount it into the container

The Nix runner in [nix/run-docker-image.nix](nix/run-docker-image.nix) now does this automatically:

- mounts the current working directory to `/workspace`
- mounts `~/.config/opencode` into the container config directory
- mounts `~/.cache/opencode` into the container cache directory
- sets `OLLAMA_HOST` to `http://host.containers.internal:11434` by default

If your host Ollama is listening somewhere else, override `OLLAMA_HOST` before starting the container.

## Start Ollama On The Host

Start Ollama on the host machine so it listens on the default port:

```bash
ollama serve
```

Make sure the model you want is already available on the host, for example:

```bash
ollama pull llama3.2
```

## Start Via Nix

From the repository root:

```bash
nix run .#runDockerImage -- opencode
```

To override the Ollama endpoint:

```bash
OLLAMA_HOST=http://host.containers.internal:11434 nix run .#runDockerImage -- opencode
```

Any `opencode` config you keep under `~/.config/opencode` on the host will be visible inside the container. If `opencode` needs a config file for your provider/model setup, put it there.

## Start Via Podman

If you want to run the image directly with Podman instead of the Nix wrapper, first build and load it:

```bash
nix build .#dockerImage
podman load --input result
```

Then start the container from the repository root:

```bash
podman run --rm -it \
  --workdir /workspace \
  --volume "$PWD:/workspace:Z" \
  --volume "${XDG_CONFIG_HOME:-$HOME/.config}/opencode:/tmp/opencode-container-config/opencode:Z" \
  --volume "${XDG_CACHE_HOME:-$HOME/.cache}/opencode:/tmp/opencode-container-cache/opencode:Z" \
  --env HOME=/tmp/opencode-container-home \
  --env XDG_CONFIG_HOME=/tmp/opencode-container-config \
  --env XDG_CACHE_HOME=/tmp/opencode-container-cache \
  --env OLLAMA_HOST="${OLLAMA_HOST:-http://host.containers.internal:11434}" \
  opencode-container:latest \
  opencode
```

If `host.containers.internal` does not resolve in your Podman setup, set `OLLAMA_HOST` explicitly to an address reachable from the container.
