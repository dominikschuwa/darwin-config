{ ... }:

{
  # Backend-role Zed tweaks (TypeScript/JavaScript work). Imported into the
  # home-manager config of any host used for backend development -- currently
  # only `maccaroni` (see flake.nix), the system counterpart being
  # `specifics/backend/config.nix`.
  #
  # The shared Zed defaults live in `modules/zed.nix`; this layers the vtsls
  # (TypeScript/JS LSP) settings on top via `extraSettings`, which
  # `recursiveUpdate`s into Zed's `userSettings`.
  myModules.zed.extraSettings = {
    lsp = {
      vtsls = {
        settings = {
          typescript = {
            updateImportsOnFileMove = {
              enabled = "always";
            };
          };
          javascript = {
            updateImportsOnFileMove = {
              enabled = "always";
            };
          };
        };
        enable_lsp_tasks = true;
      };
    };
  };
}
