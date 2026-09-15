{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

# System-level AI inference backend for Zed's edit-prediction feature.
#
# Runs `mlx_lm.server` (Apple's MLX framework, Metal-accelerated via the
# wheel-repacked `modules/pkgs/mlx`) as a launchd agent, serving an
# OpenAI-compatible `/v1/completions` endpoint on loopback. The Zed side
# lives in `modules/zed.nix`, which points its `open_ai_compatible_api`
# edit-prediction provider at this server.
#
# Why MLX and not ollama: running MLX directly lets us serve Zeta 2.1 (Zed's
# own edit-prediction model) -- mlx-lm loads HF safetensors with the original
# tokenizer, so Zeta's special FIM tokens survive, unlike the GGUF conversion
# ollama relies on. Model choice rationale lives in modules/ai-presets.nix;
# the Metal-wheel story lives in modules/pkgs/mlx/default.nix.
#
# Model downloads: `mlx_lm.server` pulls the configured HF repo into
# `~/.cache/huggingface` on first start (no separate pull agent needed). If
# the network is down at login the server exits and launchd's KeepAlive
# retries until the download succeeds. Once loaded, the model stays resident
# in memory, so there's no reload latency between completions.

let
  cfg = config.myModules.ai;

  # Shared model presets (see modules/ai-presets.nix). Selected via
  # `myModules.ai.preset`; the exact HF repo can be overridden with `model`.
  presets = import ./ai-presets.nix;
  selected = presets.${cfg.preset};

  # Python toolchain from `nixpkgsunstable`: it packages `mlx-lm` (25.11
  # doesn't) and tracks mlx releases closely. python313 is pinned on purpose:
  # the Metal mlx wheel in modules/pkgs/mlx is cp313-tagged.
  python = inputs.nixpkgsunstable.legacyPackages.${pkgs.system}.python313;

  # MLX with the Metal GPU backend, from Apple's official PyPI wheels.
  mlx = python.pkgs.callPackage ./pkgs/mlx { };

  # nixpkgs' mlx-lm with the Metal-enabled mlx swapped in.
  # - doCheck = false: the upstream test selection assumes the CPU-only
  #   nixpkgs mlx (it disables tests with "No GPU back-end" errors); with
  #   Metal compiled in, other tests try to touch the GPU inside the build
  #   sandbox and fail.
  # - sentencepiece: declared in mlx-lm's runtime requirements but only
  #   listed as a test input in nixpkgs, so the runtime-deps check (and
  #   actual tokenizer use) needs it added explicitly.
  mlx-lm = (python.pkgs.mlx-lm.override { inherit mlx; }).overridePythonAttrs (prev: {
    doCheck = false;
    dependencies = prev.dependencies ++ [ python.pkgs.sentencepiece ];
  });

  pyEnv = python.withPackages (_: [ mlx-lm ]);

  # Expose only the mlx_lm.* CLI tools (generate/chat/convert/server) in the
  # system profile -- linking the whole python env would collide with any
  # other python3 in environment.systemPackages.
  mlxLmCli = pkgs.runCommand "mlx-lm-cli" { } ''
    mkdir -p $out/bin
    for f in ${pyEnv}/bin/mlx_lm.*; do
      ln -s "$f" $out/bin/
    done
  '';

  userHome = config.users.users.${config.system.primaryUser}.home;
in
{
  options.myModules.ai = {
    enable = lib.mkEnableOption ''
      Local AI inference via mlx_lm.server (Metal-accelerated MLX).

      Runs an OpenAI-compatible completion server as a launchd agent on
      `myModules.ai.host`:`myModules.ai.port`, serving the model selected
      by `preset` (downloaded from HuggingFace on first start). Consumed
      by Zed's edit-prediction (see modules/zed.nix).
    '';

    preset = lib.mkOption {
      type = lib.types.enum (builtins.attrNames presets);
      default = "zeta-2.1-3bit";
      description = ''
        Which model preset to serve (see modules/ai-presets.nix):

        - `zeta-2.1-3bit` *(default)*: Zed's own edit-prediction model, 8B
          at 3-bit (~3.6 GB). Lighter Zeta quant.
        - `zeta-2.1`: same model at 4-bit (~4.6 GB), higher quality.
        - `zeta-2.1-2bit`: lightest Zeta (~2.6 GB), degraded quality.
        - `qwen-1.5b`: fast plain-FIM fallback, far less RAM (~1 GB).
        - `qwen-0.5b`: fastest, near-instant; lower quality.
        - `qwen-7b`: highest-quality plain-FIM option.

        Keep in sync with `myModules.zed.editPrediction.preset` (both
        default to the same value). `model` defaults from this.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = selected.model;
      defaultText = lib.literalExpression "presets.\${cfg.preset}.model";
      example = "mlx-community/Qwen2.5-Coder-7B-4bit";
      description = ''
        HuggingFace repo (MLX format) to download and serve. Defaults to
        the selected `preset`'s model. Note Zed sends the preset's model id
        in its requests, so when overriding this make sure the Zed side
        matches (see modules/zed.nix).
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Bind address for the local mlx_lm server. Default is loopback-only
        (the server has no auth; don't expose it).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        Port for the local mlx_lm server. modules/zed.nix hardcodes this in
        its edit-prediction `api_url` (it can't read system options from
        home-manager) -- change both together.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ mlxLmCli ];

    # Keep the server running in the background so Zed's edit predictions
    # are always available. mlx_lm.server preloads the model at startup and
    # keeps it resident; it also maintains a prompt (KV) cache, which suits
    # Zed's per-keystroke requests with largely-shared prefixes.
    launchd.user.agents.mlx-lm = {
      serviceConfig = {
        Label = "com.mlx.mlx-lm-server";
        ProgramArguments = [
          "${pyEnv}/bin/mlx_lm.server"
          "--model"
          cfg.model
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
        ];
        EnvironmentVariables = {
          # HF hub cache (model weights) lives under ~/.cache/huggingface.
          HOME = userHome;
        };
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/mlx-lm.log";
        StandardErrorPath = "/tmp/mlx-lm.err";
      };
    };
  };
}
