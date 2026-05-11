{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

# Home-manager module that wires up Zed with the project's preferred defaults
# (Ayu theme, VSCode bindings, ligatures) and exposes a small set of bool
# toggles for language extensions and MCP context servers. Imported from
# global/home.nix; configure via `myModules.zed.*` in any home-manager
# context (see global/home.nix for the canonical call site).
#
# https://wiki.nixos.org/wiki/Zed

let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    optionals
    literalExpression
    ;
in
{
  options.myModules.zed = {
    enable = mkEnableOption "Zed editor with darwin-config defaults";

    channel = mkOption {
      type = types.enum [
        "stable"
        "unstable"
      ];
      default = "stable";
      description = ''
        Which Zed package to install:

        - `stable`: the `zed-editor` package from the `nixpkgsunstable` flake
          input (i.e. whatever Zed release nixpkgs has shipped). This is the
          better-tested option since the package goes through nixpkgs CI.
        - `unstable`: the package built directly from the `zed` flake input
          (`zed-industries/zed`, pinned by tag in `flake.nix`). Use this to
          ride closer to upstream releases or to pin a specific Zed version
          independently of nixpkgs.
      '';
    };

    extensions = {
      flutter = mkOption {
        type = types.bool;
        default = true;
        description = "Install the Dart extension (covers Flutter projects).";
      };
      rust = mkOption {
        type = types.bool;
        default = true;
        description = "Install the Rust extension.";
      };
      nix = mkOption {
        type = types.bool;
        default = true;
        description = "Install the Nix extension.";
      };
    };

    theme = {
      dark = mkOption {
        type = types.str;
        default = "Ayu Dark";
        description = "Theme name used in dark mode (provided by the Ayu extension).";
      };
      light = mkOption {
        type = types.str;
        default = "Ayu Light";
        description = "Theme name used in light mode (provided by the Ayu extension).";
      };
    };

    fontFamily = mkOption {
      type = types.str;
      default = "FiraCode Nerd Font";
      description = ''
        Editor + terminal font. Should be a ligature-aware font; the matching
        package is added to home.packages automatically when this is left at
        the default.
      '';
    };

    mcp = {
      # Each entry below maps to one entry in Zed's `context_servers` setting.
      # Zed only speaks stdio MCP natively, so HTTP-only providers are
      # bridged through `npx -y mcp-remote <url>` (the de-facto local proxy).

      linear.enable = mkEnableOption "Linear MCP (https://mcp.linear.app/mcp via mcp-remote)";

      dart = {
        enable = mkEnableOption "Dart/Flutter MCP (`dart mcp-server`)";
        command = mkOption {
          type = types.str;
          default = "dart";
          example = literalExpression ''"\${config.home.homeDirectory}/fvm/default/bin/dart"'';
          description = ''
            Path (or PATH-resolvable name) of the dart binary that exposes
            `mcp-server`. macOS GUI apps inherit launchd's PATH, not zsh's,
            so when using fvm point this at the absolute path
            (e.g. `$HOME/fvm/default/bin/dart`). The fvm `default` symlink
            is created with `fvm global <version>` and must exist for this
            path to resolve -- otherwise Zed sees the bridge process exit
            immediately and reports a context-server timeout.
          '';
        };
      };

      figma = {
        enable = mkEnableOption "Figma MCP (hosted remote, OAuth via mcp-remote)";
        useDesktop = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Point at Figma's local desktop-app MCP server
            (`http://127.0.0.1:3845/mcp`) instead of the hosted remote one.
            Requires the Figma desktop app running with "Enable MCP server"
            turned on under Preferences and a Dev/Full seat on a paid plan.
            Leave `false` to use Figma's hosted endpoint, which works
            without any local setup (OAuth flow on first connect, same as
            Linear).
          '';
        };
        url = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Override the Figma MCP endpoint. When `null` (the default),
            the URL is derived from {option}`useDesktop` -- hosted at
            `https://mcp.figma.com/mcp`, or local at
            `http://127.0.0.1:3845/mcp`.
          '';
        };
      };
    };
  };

  config =
    let
      cfg = config.myModules.zed;

      # Pin the bridge binary to the nixpkgs nodejs so this works on hosts
      # that don't have a system-wide npx (e.g. fresh `maccaroni` setups).
      npx = lib.getExe' pkgs.nodejs "npx";

      mkRemoteServer = url: {
        source = "custom";
        command = npx;
        args = [
          "-y"
          "mcp-remote"
          url
        ];
        env = { };
      };

      figmaUrl =
        if cfg.mcp.figma.url != null then
          cfg.mcp.figma.url
        else if cfg.mcp.figma.useDesktop then
          "http://127.0.0.1:3845/mcp"
        else
          "https://mcp.figma.com/mcp";

      contextServers =
        lib.optionalAttrs cfg.mcp.linear.enable {
          linear = mkRemoteServer "https://mcp.linear.app/mcp";
        }
        // lib.optionalAttrs cfg.mcp.dart.enable {
          dart = {
            source = "custom";
            command = cfg.mcp.dart.command;
            # `--experimental-mcp-server` is a no-op on Dart 3.9+, kept for
            # forward compatibility with older SDKs. `--force-roots-fallback`
            # works around clients (Cursor, Zed) with partial Roots support.
            args = [
              "mcp-server"
              "--experimental-mcp-server"
              "--force-roots-fallback"
            ];
            env = { };
          };
        }
        // lib.optionalAttrs cfg.mcp.figma.enable {
          figma = mkRemoteServer figmaUrl;
        };
    in
    mkIf cfg.enable {
      programs.zed-editor = {
        package =
          if cfg.channel == "unstable" then
            # The upstream zed flake exposes the editor as `packages.<system>.default`.
            inputs.zed.packages.${pkgs.system}.default
          else
            inputs.nixpkgsunstable.legacyPackages.${pkgs.system}.zed-editor;
        enable = true;
        extensions = lib.unique (
          [
            "ayu"
            "toml"
          ]
          ++ optionals cfg.extensions.flutter [ "dart" ]
          ++ optionals cfg.extensions.nix [ "nix" ]
          # The Rust extension only adds toolchain helpers; rust-analyzer
          # itself is bundled with Zed, so this stays optional.
          ++ optionals cfg.extensions.rust [ "rust" ]
        );

        userSettings = {
          theme = {
            mode = "system";
            inherit (cfg.theme) dark light;
          };

          base_keymap = "VSCode";
          vim_mode = false;

          ui_font_size = 15;
          buffer_font_size = 14;
          buffer_font_family = cfg.fontFamily;
          buffer_font_features = {
            calt = true;
            liga = true;
          };
          terminal.font_family = cfg.fontFamily;

          # Empty proxy explicitly disables Zed's auto-detected proxy. Keep
          # this set so corporate macOS proxy settings don't bleed into Zed.
          proxy = "";

          # ---- Layout / panels -------------------------------------------------
          bottom_dock_layout = "contained";

          git_panel = {
            tree_view = true;
            dock = "left";
          };

          outline_panel = {
            default_width = 340.0;
            dock = "left";
          };

          project_panel = {
            hide_hidden = false;
            hide_root = true;
            git_status = true;
            git_status_indicator = false;
            diagnostic_badges = true;
            bold_folder_labels = true;
            default_width = 340.0;
            dock = "left";
          };

          tabs = {
            git_status = true;
            file_icons = true;
          };

          tab_bar = {
            show = true;
          };

          title_bar = {
            show_branch_status_icon = true;
          };

          # ---- Agent (Zed AI) --------------------------------------------------
          agent = {
            max_content_width = 1000.0;
            default_width = 540.0;
            dock = "right";
            favorite_models = [
              {
                provider = "anthropic";
                model = "claude-opus-4-7-latest";
                enable_thinking = true;
                effort = "high";
              }
            ];
            default_model = {
              provider = "anthropic";
              model = "claude-opus-4-7-latest";
              enable_thinking = true;
              effort = "high";
            };
            model_parameters = [ ];
          };

          context_servers = contextServers;
        };
      };

      home.packages = lib.optional (cfg.fontFamily == "FiraCode Nerd Font") pkgs.nerd-fonts.fira-code;
    };
}
