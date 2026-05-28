{
  config,
  lib,
  ...
}:

# Wires up the per-user merge tool for git, choosing between Zed and
# Cursor and -- when Zed is selected -- routing to whichever binary the
# active `myModules.zed.channel` package exposes:
#
# - nixpkgs `zed-editor` ships its CLI as `zeditor` to dodge the ncurses
#   `zed` name collision (so the `unstable` channel resolves to a
#   `bin/zeditor` in /nix/store).
# - The upstream `zed-industries/zed` flake keeps the native `zed` CLI
#   name (so the `nightly` channel resolves to a `bin/zed`).
#
# Both packages set `meta.mainProgram` correctly, so `lib.getExe` picks
# the right binary by absolute store path. That avoids depending on the
# user's PATH inside the mergetool, which git's `git-mergetool--lib`
# scrubs (this used to manifest as `zeditor: command not found` when
# launching mergetool from a fresh shell).
#
# Zed still lacks 3-way merge editing
# (https://github.com/zed-industries/zed/issues/34813), which is why
# the zed entry only passes $MERGED instead of $REMOTE/$LOCAL/$BASE.

let
  inherit (lib) mkOption types;

  cfg = config.myModules.git;

  zedExe = lib.getExe config.programs.zed-editor.package;
in
{
  options.myModules.git = {
    mergetool = mkOption {
      type = types.enum [
        "zed"
        "cursor"
        "vscode"
      ];
      default = "zed";
      description = ''
        Which editor `git mergetool` should launch by default. `zed`
        follows whichever package `myModules.zed.channel` selects
        (the binary is `zed` on `nightly`, `zeditor` on `unstable`).
        `cursor` and `vscode` invoke the respective CLIs and require
        those tools to be on PATH.
      '';
    };
  };

  config = {
    programs.git.settings = {
      "mergetool \"vscode\"" = {
        cmd = "code --wait --merge $REMOTE $LOCAL $BASE $MERGED";
        trustExitCode = true;
      };
      "mergetool \"cursor\"" = {
        cmd = "cursor --wait --merge $REMOTE $LOCAL $BASE $MERGED";
        trustExitCode = true;
      };
      "mergetool \"zed\"" = {
        cmd = "${zedExe} --wait $MERGED";
        trustExitCode = true;
      };
      merge.tool = cfg.mergetool;
    };
  };
}
