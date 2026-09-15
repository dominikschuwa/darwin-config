# Shared edit-prediction model presets.
#
# Plain attrset (NOT a module), imported from both module trees without
# crossing the system <-> home-manager boundary:
#   - `modules/ai.nix`  (system)        serves `model` via `mlx_lm.server`.
#   - `modules/zed.nix` (home-manager)  feeds `model` + `promptFormat` into
#                                        Zed's `edit_predictions`.
#
# Keep `myModules.ai.preset` and `myModules.zed.editPrediction.preset` set to
# the same key (both default to the same value, so usually nothing to do).
#
# Why MLX (not ollama): MLX loads HuggingFace safetensors with the original
# tokenizer, so Zeta's special FIM tokens (`<|editable_region_start|>` etc.)
# survive intact -- it was llama.cpp's GGUF conversion that shredded them and
# previously forced us onto qwen-via-ollama. Metal GPU support comes from
# Apple's official PyPI wheels, repackaged in `modules/pkgs/mlx` (the nixpkgs
# `mlx` is CPU-only because the Metal shader compiler is closed-source).
#
# Each preset:
#   model          HuggingFace repo (MLX format) that `mlx_lm.server`
#                  downloads on first start and serves. Also the model id
#                  Zed sends in its completion requests.
#   promptFormat   Zed `prompt_format` matching the model family.
#
# Performance (Apple Silicon, Metal, ~2000-token file context):
#   qwen-0.5b: near-instant   qwen-1.5b: fast   zeta-2.1 / qwen-7b: usable
# Prefill cost scales with parameter count; smaller = faster.
#
# RAM: the 8B Zeta presets resident-load their weights plus ~0.5-1.5 GB of
# runtime + KV cache. Approximate weight footprints (8B = zed-industries/
# zeta-2.1): 4bit 4.6 GB, 3bit 3.6 GB, 2bit 2.6 GB. If even 3bit Zeta is too
# heavy, drop to `qwen-1.5b` (~1 GB) -- a much bigger RAM win than any Zeta
# quant, at the cost of Zeta's multi-location edit smarts.

{
  # Zeta 2.1 (8B, 3-bit MLX quant of zed-industries/zeta-2.1) -- recommended
  # default. Zed's own purpose-built edit-prediction model: unlike plain FIM
  # models it predicts multi-location *edits*, not just insertions at the
  # cursor. ~3.6 GB weights -- the lighter Zeta quant; mild quality loss vs
  # 4bit but noticeably less RAM.
  "zeta-2.1-3bit" = {
    model = "NexVeridian/zeta-2.1-3bit";
    promptFormat = "zeta2_1";
  };

  # Zeta 2.1, 4-bit MLX quant -- best quality/size balance of the Zeta
  # options. ~4.6 GB weights. Use this if you have RAM to spare.
  "zeta-2.1" = {
    model = "NexVeridian/zeta-2.1-4bit";
    promptFormat = "zeta2_1";
  };

  # Zeta 2.1, 2-bit MLX quant -- lightest Zeta option (~2.6 GB weights), but
  # 2-bit on an 8B noticeably degrades output quality, and this is the only
  # repo offering it (a low-traffic single-user upload, not vetted like the
  # NexVeridian quants above). Prefer `qwen-1.5b` for a lighter *and*
  # higher-quality alternative unless you specifically need Zeta's edit
  # behavior at minimal RAM.
  "zeta-2.1-2bit" = {
    model = "ton-An/zeta-2.1-mlx-2Bit";
    promptFormat = "zeta2_1";
  };

  # Qwen2.5-Coder 1.5B base (4-bit MLX) -- fast fallback with solid FIM
  # quality for machines where the 8B Zeta prefill feels sluggish.
  "qwen-1.5b" = {
    model = "mlx-community/Qwen2.5-Coder-1.5B-4bit";
    promptFormat = "qwen";
  };

  # Qwen2.5-Coder 0.5B base (4-bit MLX) -- fastest, predictions appear
  # near-instantly even on large files; lower quality than 1.5B.
  "qwen-0.5b" = {
    model = "mlx-community/Qwen2.5-Coder-0.5B-4bit";
    promptFormat = "qwen";
  };

  # Qwen2.5-Coder 7B base (4-bit MLX) -- highest-quality plain-FIM option,
  # comparable footprint to zeta-2.1 (prefer Zeta unless qwen's FIM style
  # works better for you).
  "qwen-7b" = {
    model = "mlx-community/Qwen2.5-Coder-7B-4bit";
    promptFormat = "qwen";
  };
}
