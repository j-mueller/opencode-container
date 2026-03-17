{ pkgs, dockerImage }:
let
  mkOpencodeConfig = import ./opencode-config.nix;
  currentDefaultConfigJsonTemplate = builtins.toJSON (mkOpencodeConfig {
    baseURL = "__OLLAMA_HOST__/v1";
  });
  legacyDefaultConfigQwenExpandedJson = builtins.toJSON (mkOpencodeConfig {
    baseURL = "http://host.containers.internal:11434/v1";
    model = "ollama/qwen3.5:9b";
  });
in
pkgs.writeShellApplication {
  name = "run-opencode-container";
  runtimeInputs = [ pkgs.gnutar pkgs.jq pkgs.podman ];
  text = ''
    set -euo pipefail

    image_ref="opencode-container:latest"
    workspace_dir="$(pwd)"
    host_config_root="''${XDG_CONFIG_HOME:-$HOME/.config}"
    host_cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}"
    host_opencode_config_dir="$host_config_root/opencode"
    host_opencode_cache_dir="$host_cache_root/opencode"
    home_dir="/root"
    xdg_config_dir="/tmp/opencode-container-config"
    xdg_cache_dir="/tmp/opencode-container-cache"
    ollama_host="''${OLLAMA_HOST:-http://127.0.0.1:11434}"

    normalized_json() {
      jq -S . "$1"
    }

    write_default_config() {
      jq --arg base_url "$ollama_host/v1" '
        .provider.ollama.options.baseURL = $base_url
      ' <<'EOF' > "$1"
    ${currentDefaultConfigJsonTemplate}
    EOF
    }

    podman image rm "$image_ref" >/dev/null 2>&1 || true
    tar --create --numeric-owner --owner=0 --group=0 \
      -C "${dockerImage.rootfs}" . \
      | podman import \
          --change 'CMD ["/bin/bash"]' \
          --change 'ENTRYPOINT ["/bin/opencode-container-init"]' \
          --change 'ENV PATH=/bin' \
          --change 'ENV HOME=/root' \
          --change 'ENV XDG_CONFIG_HOME=/tmp/opencode-container-config' \
          --change 'ENV XDG_CACHE_HOME=/tmp/opencode-container-cache' \
          --change 'ENV SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt' \
          - "$image_ref" >/dev/null

    mkdir -p "$host_opencode_config_dir" "$host_opencode_cache_dir"

    config_file="$host_opencode_config_dir/opencode.json"
    current_default_config="$(mktemp)"
    legacy_default_config_qwen_expanded="$(mktemp)"
    trap 'rm -f "$current_default_config" "$legacy_default_config_qwen_expanded"' EXIT

    write_default_config "$current_default_config"

    cat > "$legacy_default_config_qwen_expanded" <<'EOF'
    ${legacyDefaultConfigQwenExpandedJson}
    EOF

    if [ ! -f "$config_file" ]; then
      write_default_config "$config_file"
    else
      config_json="$(normalized_json "$config_file")"
      if [ "$config_json" = "$(normalized_json "$legacy_default_config_qwen_expanded")" ]; then
        write_default_config "$config_file"
      fi
    fi

    tty_flags=()
    if [ -t 0 ] && [ -t 1 ]; then
      tty_flags+=(--interactive --tty)
    fi

    exec podman run --rm \
      "''${tty_flags[@]}" \
      --network host \
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
