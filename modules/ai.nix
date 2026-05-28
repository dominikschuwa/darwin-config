{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

# System-level AI inference for Zed's edit-prediction (and anything else that
# can speak OpenAI's `/v1/completions`). Runs `mlx_lm.server` from a
# nix-managed Python env as a launchd agent on `myModules.ai.port`, with a
# separate one-shot agent that lazily downloads the safetensors from
# HuggingFace on first login.
#
# Why MLX instead of ollama/llama.cpp for Zeta 2.1:
#   `llama.cpp`'s `convert_hf_to_gguf.py` drops Zeta's unusual bracketed FIM
#   tokens (`<[fim-prefix]>`, `<|marker_1|>`, `<|user_cursor|>`) -- they end
#   up split into ~7 sub-tokens each, so the model can't FIM. MLX uses the
#   stock `transformers` tokenizer (via the upstream `tokenizer.json`), so
#   the special tokens survive quantization and the model actually works.
#
# This module is purely the *backend*. The Zed-side wiring lives in
# `modules/zed.nix` -- it just needs `open_ai_compatible_api` pointed at the
# host/port configured here, which is the default.

let
  cfg = config.myModules.ai;

  # Pull from `nixpkgsunstable` because MLX moves quickly and the 25.11
  # release branch tends to lag a couple of MLX point versions.
  unstable = inputs.nixpkgsunstable.legacyPackages.${pkgs.system};

  # Single Python env containing both the server runtime (`mlx_lm.server`)
  # and the downloader (`huggingface-cli` is shipped by huggingface-hub).
  # Sharing one env keeps `nix store` traffic minimal and means the two
  # launchd agents below can reuse the same closure.
  aiPythonEnv = unstable.python3.withPackages (ps: [
    ps.mlx-lm
    ps.huggingface-hub
  ]);

  # Resolve the primary user's home declaratively so the launchd agents
  # don't bake `/Users/<name>` into multiple places.
  userHome = config.users.users.${config.system.primaryUser}.home;
  modelLocalDir = "${userHome}/Models/${cfg.modelLocalSlug}";
in
{
  options.myModules.ai = {
    enable = lib.mkEnableOption ''
      Local AI inference via MLX-LM.

      Runs `mlx_lm.server` as a launchd agent, exposing an
      OpenAI-compatible `/v1/completions` endpoint at
      `myModules.ai.host:myModules.ai.port`. The configured model is
      downloaded once from HuggingFace by a sibling one-shot agent
      (`dev.mlx.download`) into `~/Models/<slug>`.
    '';

    modelRepo = lib.mkOption {
      type = lib.types.str;
      default = "zed-industries/zeta-2.1";
      example = lib.literalExpression ''"mlx-community/Qwen2.5-Coder-7B-4bit"'';
      description = ''
        Source HuggingFace repo. Defaults to the official upstream Zeta
        safetensors -- which means we get the *correct* tokenizer config
        for free (no Mistral-regex warnings, no shredded FIM tokens).

        On first launch, this is downloaded and locally quantized by
        `mlx_lm.convert` (see `quantBits`). Subsequent launches just
        load the cached output.

        Override to e.g. `mlx-community/Qwen2.5-Coder-7B-4bit` if you'd
        rather skip the quantize step and serve a pre-built MLX model.
        When pointing at an already-MLX repo, set `quantBits = null`.
      '';
    };

    modelLocalSlug = lib.mkOption {
      type = lib.types.str;
      default = "zeta-2.1-mlx-q4";
      description = ''
        Subdirectory under `~/Models/` to write the final (post-convert)
        model into. Bump this when you change `modelRepo` or `quantBits`
        so different setups don't scribble over each other.
      '';
    };

    quantBits = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          2
          3
          4
          6
          8
        ]
      );
      default = 4;
      description = ''
        Bits per weight for the on-machine `mlx_lm.convert` quantization
        pass. Tradeoffs:

        - `null`: skip conversion, serve `modelRepo` as-is (BF16
          safetensors load directly; pre-built MLX repos load directly).
          For Zeta this means ~16 GB on disk + RAM.
        - `8`: ~8 GB, essentially lossless.
        - `4` *(default)*: ~4 GB, the usual sweet spot for code models.
        - `3` / `2`: smaller still, with progressively more quality loss.

        Doing the conversion *locally* (rather than pulling a community
        quant) is the whole point -- the upstream `tokenizer.json` is
        carried over verbatim, so Zeta's bracketed FIM markers
        (`<[fim-prefix]>`, `<|marker_1|>`, ...) survive as proper
        special tokens.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Bind address for the MLX server. Default is loopback-only --
        flip to `0.0.0.0` to expose to your LAN (and tighten your
        firewall).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port for the MLX server's HTTP API.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Exposes `mlx_lm.server`, `mlx_lm.generate`, and `huggingface-cli` on
    # the system PATH for manual debugging/tinkering.
    environment.systemPackages = [ aiPythonEnv ];

    # One-shot: prepare the model directory at `${modelLocalDir}`.
    #
    # When `quantBits` is set, this runs `mlx_lm.convert` which:
    #   1. Downloads `modelRepo` from HF (cached in ~/.cache/huggingface)
    #   2. Quantizes the BF16 weights to N-bit MLX format
    #   3. Writes the result (incl. the original tokenizer.json verbatim)
    #      into `modelLocalDir`
    #
    # When `quantBits` is null, we just download with `hf download` and
    # serve the source repo as-is (useful for already-MLX repos like
    # `mlx-community/...`).
    #
    # `config.json` is the canonical "model is ready" sentinel that
    # `mlx_lm.server` itself checks for, so we use it as the
    # idempotency marker too.
    #
    # NB: `huggingface-cli download` was renamed to `hf download` in
    # huggingface_hub 0.34.
    launchd.user.agents.mlx-prepare = {
      serviceConfig = {
        Label = "dev.mlx.prepare";
        ProgramArguments = [
          "/bin/sh"
          "-c"
          (
            if cfg.quantBits == null then
              ''
                if [ -f ${modelLocalDir}/config.json ]; then
                  exit 0
                fi
                mkdir -p ${modelLocalDir}
                exec ${aiPythonEnv}/bin/hf download ${cfg.modelRepo} \
                  --local-dir ${modelLocalDir}
              ''
            else
              ''
                                if [ -f ${modelLocalDir}/config.json ]; then
                                  exit 0
                                fi
                                ${aiPythonEnv}/bin/mlx_lm.convert \
                                  --hf-path ${cfg.modelRepo} \
                                  --mlx-path ${modelLocalDir} \
                                  -q \
                                  --q-bits ${toString cfg.quantBits}
                                # Patch _name_or_path so mlx_lm.server maps the HF repo
                                # name ("${cfg.modelRepo}") to our local model instead of
                                # re-downloading the BF16 weights from HF cache on every
                                # request.
                                ${aiPythonEnv}/bin/python3 -c "
                import json
                p = '${modelLocalDir}/config.json'
                with open(p) as f: c = json.load(f)
                c['_name_or_path'] = '${cfg.modelRepo}'
                with open(p, 'w') as f: json.dump(c, f, indent=2)
                "
              ''
          )
        ];
        EnvironmentVariables = {
          HOME = userHome;
        };
        RunAtLoad = true;
        KeepAlive = false;
        StandardOutPath = "/tmp/mlx-prepare.log";
        StandardErrorPath = "/tmp/mlx-prepare.err";
      };
    };

    # Long-running: the inference server. Waits in a polling loop until
    # the prepare agent has finished, then `exec`s `mlx_lm.server` so
    # launchd manages the actual server PID directly (clean restarts on
    # crash via KeepAlive).
    #
    # Key performance flags:
    #   --prompt-cache-size / --prompt-cache-bytes
    #     Persist KV caches between requests. On the FIRST request for a
    #     file the full 2000+ token prompt is prefilled (slow, ~50s on
    #     M-chip). Every subsequent keystroke in the same file reuses the
    #     cached KV state and only processes the new/changed tokens --
    #     typically < 1s. Without this flag each keystroke re-prefills the
    #     entire prompt.
    #   --prefill-step-size 4096
    #     Larger batches → better Metal GPU utilisation during prefill.
    #     Reduces that cold first-request time.
    launchd.user.agents.mlx-server = {
      serviceConfig = {
        Label = "dev.mlx.server";
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
                        until [ -f ${modelLocalDir}/config.json ]; do sleep 5; done

                        # Run server in background so we can send a warm-up request
                        # before handing control back to launchd via `wait`.
                        ${aiPythonEnv}/bin/mlx_lm.server \
                          --model ${modelLocalDir} \
                          --host ${cfg.host} \
                          --port ${toString cfg.port} \
                          --prompt-cache-size 4 \
                          --prompt-cache-bytes 1500000000 \
                          --prefill-step-size 4096 &
                        SERVER_PID=$!

                        # Poll until the HTTP server is ready.
                        until ${aiPythonEnv}/bin/python3 -c \
                          "import urllib.request; urllib.request.urlopen('http://${cfg.host}:${toString cfg.port}/health', timeout=2)" \
                          2>/dev/null; do sleep 2; done

                        # Warm-up: page model weights into GPU memory so the first real
                        # Zed request is fast (~2s) instead of cold (~50s).
                        # Use the local path as model ID to avoid the server trying to
                        # re-download BF16 weights from the HF cache.
                        ${aiPythonEnv}/bin/python3 -c "
            import urllib.request, json
            body = json.dumps({'model':'${modelLocalDir}','prompt':'def ','max_tokens':1,'temperature':0}).encode()
            urllib.request.urlopen(urllib.request.Request(
              'http://${cfg.host}:${toString cfg.port}/v1/completions',
              data=body, headers={'Content-Type':'application/json'}, method='POST'), timeout=120)
            " 2>/dev/null || true

                        wait "$SERVER_PID"
          ''
        ];
        EnvironmentVariables = {
          HOME = userHome;
          # Prevent mlx_lm from hitting the HF Hub on every startup to
          # verify model checksums or pull new files. All weights live in
          # `modelLocalDir`; we don't want network calls on a hot path.
          HF_HUB_OFFLINE = "1";
          # Belt-and-suspenders: transformers uses the same env var.
          TRANSFORMERS_OFFLINE = "1";
        };
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/mlx-server.log";
        StandardErrorPath = "/tmp/mlx-server.err";
      };
    };
  };
}
