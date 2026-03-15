{ pkgs, dockerImage }:
pkgs.writeShellApplication {
  name = "run-opencode-container";
  runtimeInputs = [ pkgs.gnutar pkgs.podman ];
  text = ''
    set -euo pipefail

    image_ref="opencode-container:latest"
    workspace_dir="$(pwd)"
    host_config_root="''${XDG_CONFIG_HOME:-$HOME/.config}"
    host_cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}"
    host_opencode_config_dir="$host_config_root/opencode"
    host_opencode_cache_dir="$host_cache_root/opencode"
    home_dir="/tmp/opencode-container-home"
    xdg_config_dir="/tmp/opencode-container-config"
    xdg_cache_dir="/tmp/opencode-container-cache"
    ollama_host="''${OLLAMA_HOST:-http://host.containers.internal:11434}"

    podman image rm "$image_ref" >/dev/null 2>&1 || true
    tar --create --numeric-owner --owner=0 --group=0 \
      -C "${dockerImage.rootfs}" . \
      | podman import \
          --change 'CMD ["/bin/bash"]' \
          --change 'ENV PATH=/bin' \
          --change 'ENV HOME=/tmp/opencode-container-home' \
          --change 'ENV XDG_CONFIG_HOME=/tmp/opencode-container-config' \
          --change 'ENV XDG_CACHE_HOME=/tmp/opencode-container-cache' \
          --change 'ENV SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt' \
          - "$image_ref" >/dev/null

    mkdir -p "$host_opencode_config_dir" "$host_opencode_cache_dir"

    tty_flags=()
    if [ -t 0 ] && [ -t 1 ]; then
      tty_flags+=(--interactive --tty)
    fi

    exec podman run --rm \
      "''${tty_flags[@]}" \
      --workdir /workspace \
      --volume "$workspace_dir:/workspace:Z" \
      --volume "$host_opencode_config_dir:$xdg_config_dir/opencode:Z" \
      --volume "$host_opencode_cache_dir:$xdg_cache_dir/opencode:Z" \
      --env HOME="$home_dir" \
      --env XDG_CONFIG_HOME="$xdg_config_dir" \
      --env XDG_CACHE_HOME="$xdg_cache_dir" \
      --env OLLAMA_HOST="$ollama_host" \
      "$image_ref" \
      "$@"
  '';
}
