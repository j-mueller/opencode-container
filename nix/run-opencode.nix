{ pkgs, dockerImage }:
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
    home_dir="/tmp/opencode-container-home"
    xdg_config_dir="/tmp/opencode-container-config"
    xdg_cache_dir="/tmp/opencode-container-cache"
    ollama_host="''${OLLAMA_HOST:-http://127.0.0.1:11434}"

    normalized_json() {
      jq -S . "$1"
    }

    write_default_config() {
      cat > "$1" <<EOF
    {
      "\$schema": "https://opencode.ai/config.json",
      "provider": {
        "ollama": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Ollama (local)",
          "options": {
            "baseURL": "''${ollama_host}/v1"
          },
          "models": {
            "qwen3.5:9b": {
              "name": "Qwen 3.5 9B"
            },
            "qwen3.5:27b": {
              "name": "Qwen 3.5 27B"
            },
            "qwen3.5:35b": {
              "name": "Qwen 3.5 35B"
            },
            "qwen3.5:latest": {
              "name": "Qwen 3.5 Latest"
            },
            "qwen3-coder-next:latest": {
              "name": "Qwen 3 Coder Next Latest"
            }
          }
        }
      },
      "model": "ollama/qwen3.5:27b"
    }
    EOF
    }

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

    config_file="$host_opencode_config_dir/opencode.json"
    current_default_config="$(mktemp)"
    legacy_default_config_llama32="$(mktemp)"
    legacy_default_config_qwen9b="$(mktemp)"
    legacy_default_config_qwen_expanded="$(mktemp)"
    trap 'rm -f "$current_default_config" "$legacy_default_config_llama32" "$legacy_default_config_qwen9b" "$legacy_default_config_qwen_expanded"' EXIT

    write_default_config "$current_default_config"

    cat > "$legacy_default_config_llama32" <<'EOF'
    {
      "$schema": "https://opencode.ai/config.json",
      "provider": {
        "ollama": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Ollama (local)",
          "options": {
            "baseURL": "http://host.containers.internal:11434/v1"
          },
          "models": {
            "llama3.2": {
              "name": "Llama 3.2"
            }
          }
        }
      },
      "model": "ollama/llama3.2"
    }
    EOF

    cat > "$legacy_default_config_qwen9b" <<'EOF'
    {
      "$schema": "https://opencode.ai/config.json",
      "provider": {
        "ollama": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Ollama (local)",
          "options": {
            "baseURL": "http://host.containers.internal:11434/v1"
          },
          "models": {
            "qwen3.5:9b": {
              "name": "Qwen 3.5 9B"
            }
          }
        }
      },
      "model": "ollama/qwen3.5:9b"
    }
    EOF

    cat > "$legacy_default_config_qwen_expanded" <<'EOF'
    {
      "$schema": "https://opencode.ai/config.json",
      "provider": {
        "ollama": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "Ollama (local)",
          "options": {
            "baseURL": "http://host.containers.internal:11434/v1"
          },
          "models": {
            "qwen3.5:9b": {
              "name": "Qwen 3.5 9B"
            },
            "qwen3.5:27b": {
              "name": "Qwen 3.5 27B"
            },
            "qwen3.5:35b": {
              "name": "Qwen 3.5 35B"
            },
            "qwen3.5:latest": {
              "name": "Qwen 3.5 Latest"
            },
            "qwen3-coder-next:latest": {
              "name": "Qwen 3 Coder Next Latest"
            }
          }
        }
      },
      "model": "ollama/qwen3.5:9b"
    }
    EOF

    if [ ! -f "$config_file" ]; then
      write_default_config "$config_file"
    else
      config_json="$(normalized_json "$config_file")"
      if [ "$config_json" = "$(normalized_json "$legacy_default_config_llama32")" ] || [ "$config_json" = "$(normalized_json "$legacy_default_config_qwen9b")" ] || [ "$config_json" = "$(normalized_json "$legacy_default_config_qwen_expanded")" ]; then
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
