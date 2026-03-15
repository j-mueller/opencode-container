{ baseURL, model ? "ollama/qwen3.5:27b" }:
{
  "$schema" = "https://opencode.ai/config.json";
  provider = {
    ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama (local)";
      options = {
        inherit baseURL;
      };
      models = {
        "qwen3.5:9b" = {
          name = "Qwen 3.5 9B";
        };
        "qwen3.5:27b" = {
          name = "Qwen 3.5 27B";
        };
        "qwen3.5:35b" = {
          name = "Qwen 3.5 35B";
        };
        "qwen3.5:latest" = {
          name = "Qwen 3.5 Latest";
        };
        "qwen3-coder-next:latest" = {
          name = "Qwen 3 Coder Next Latest";
        };
      };
    };
  };
  inherit model;
}
