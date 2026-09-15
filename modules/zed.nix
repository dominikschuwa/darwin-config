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

  # Shared edit-prediction model presets, also consumed by modules/ai.nix
  # (the MLX server backend). See modules/ai-presets.nix.
  presets = import ./ai-presets.nix;
in
{
  options.myModules.zed = {
    enable = mkEnableOption "Zed editor with darwin-config defaults";

    editPrediction = {
      provider = mkOption {
        type = types.enum [
          "zed"
          "local"
        ];
        default = "zed";
        description = ''
          Which edit-prediction backend Zed should use:

          - `zed` *(default)*: Zed's own hosted Zeta service. No local
            model, GPU, or RAM cost; requires a zed.dev sign-in. This is
            the default so machines don't run a local LLM unless they
            explicitly opt in.
          - `local`: the Metal-accelerated `mlx_lm.server` from
            `modules/ai.nix`. Fully offline and sign-in free, but keeps
            the model resident in RAM and uses the GPU. When selecting
            this, also set `myModules.ai.enable = true` and keep `preset`
            in sync with `myModules.ai.preset`.
        '';
      };

      preset = mkOption {
        type = types.enum (builtins.attrNames presets);
        default = "zeta-2.1-3bit";
        description = ''
          Which model preset Zed's edit-prediction should target when
          `provider = "local"`. This selects both the `prompt_format` and
          the model id that Zed sends to the local MLX server. It has no
          effect when `provider = "zed"` (the hosted service).

          Must match `myModules.ai.preset` (the backend that actually
          serves the model). Both default to the same value, so normally
          there's nothing to do -- change them together if you switch.
        '';
      };
    };

    channel = mkOption {
      type = types.enum [
        "unstable"
        "nightly"
      ];
      default = "unstable";
      description = ''
        Which Zed package to install:

        - `unstable` *(default)*: the `zed-editor` package from the
          `nixpkgsunstable` flake input (i.e. whatever Zed release nixpkgs
          has shipped). The better-tested option, since the package goes
          through nixpkgs CI.
        - `nightly`: built directly from the `zed` flake input
          (`zed-industries/zed`, pinned by `flake.lock`). Rides upstream's
          nightly tip at the cost of compiling Zed locally -- see the
          aarch64-darwin build workarounds on `package` below.
      '';
    };

    extensions = {
      strategy = mkOption {
        type = types.enum [
          "auto"
          "registry"
        ];
        default = "auto";
        description = ''
          How the extensions below are installed:

          - `auto` *(default)*: build packaged extensions from source via
            nix-zed-extensions and drop them into Zed's `installed` dir --
            pinned to the flake lock, reproducible, and offline after the
            first build. Unsupported IDs and Dart (which requires writable
            grammar state) install from Zed's hosted registry.
          - `registry`: install everything through Zed's runtime
            auto-install (`programs.zed-editor.extensions`), i.e. the
            pre-nix-zed-extensions behavior. Nothing is built from source
            (the `nixInjectionFork` grammar fork still is -- it has no
            registry equivalent).

          The first `auto` rebuild compiles each extension's wasm (and any
          tree-sitter grammar), so expect some one-off build time; the
          results are cached afterwards.
        '';
      };
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
      nixInjectionFork = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install the Nix extension from the sebb3 fork instead of the
          registry `nix` extension. The fork adds runnable flake tasks and
          dynamic comment-based language injection: a comment naming a
          language (e.g. `# bash` or `/* python */`) before a string
          injects that language's syntax highlighting into the string.

          Both the extension and its bundled tree-sitter-nix grammar are
          built from source via nix-zed-extensions
          (`programs.zed-editor-extensions`), pinned to the fork commits:
            - grammar:   sebb3/tree-sitter-nix @ injection-comment
                         (nix-community/tree-sitter-nix#166)
            - extension: sebb3/nix @ main
                         (zed-extensions/nix#49)
          Both PRs are pending upstream merge; once they land, drop this
          toggle and flip `extensions.nix` back on.

          Takes precedence over `extensions.nix`: enabling it drops the
          registry `nix` id from the auto-installed set so the two Nix
          extensions don't fight over the same install slot.
        '';
      };
      comment = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install the Comments Highlighter extension
          (https://github.com/thedadams/zed-comment), which colorizes
          TODO/NOTE/FIXME-style comment tags via tree-sitter injections.
        '';
      };
      openscad = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install OpenSCAD support from johann-cm/zed-openscad, pinned to its
          source commit instead of resolving the similarly named registry
          extension.
        '';
      };
      spellcheck = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install the CSpell extension
          (https://github.com/mantou132/zed-cspell), a spell checker
          backed by `@vlabo/cspell-lsp`.

          When enabled, a global cspell config is written to
          `~/Library/Preferences/cspell/cspell.json` activating the
          English (bundled with cspell) and German dictionaries. The
          German dictionary (`@cspell/dict-de-de`) is pinned and built
          from its npm tarball via Nix and imported by absolute store
          path -- no `npm install -g` / `cspell link` needed.

          The LSP only reads cspell config files (project `cspell.json`,
          the global config above, and cspell's bundled defaults); it
          does not consult Zed's `lsp.cspell.settings`. Override the
          locale/dictionaries via the global config or a project-level
          `cspell.json`.
        '';
      };
    };

    extraExtensions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = literalExpression ''[ "elixir" "vue" "catppuccin" ]'';
      description = ''
        Additional Zed extension registry IDs to install on top of the
        ones covered by the `myModules.zed.extensions.*` toggles.

        The value is a list of extension IDs as they appear on
        https://zed.dev/extensions (or in each extension's
        `extension.toml`). Use this for per-user extensions that don't
        warrant a dedicated module option -- one-off language packs,
        alternative themes, niche tooling, etc.
      '';
    };

    theme = {
      dark = mkOption {
        type = types.str;
        default = "Palenight Theme";
        description = "Theme name used in dark mode.";
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

    extraSettings = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''
        {
          base_keymap = "VSCode";
          buffer_font_size = 16;
          ssh_connections = [ { host = "example.com"; username = "user"; } ];
        }
      '';
      description = ''
        Per-user overrides merged into Zed's `userSettings` on top of the
        shared module defaults. Uses `lib.recursiveUpdate`, so individual
        nested keys can be tweaked without clobbering sibling defaults
        (lists, however, are replaced wholesale, not concatenated).

        Set this from per-user files (e.g. `specifics/<user>/home.nix`) to
        tailor Zed without forking the module -- the shared defaults stay
        in `modules/zed.nix`, anything personal lives next to the user's
        other home-manager config.
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

      # Resolve the active edit-prediction preset (HF model + prompt format).
      epPreset = presets.${cfg.editPrediction.preset};

      # Pin the bridge binary to the current Node 26 release so this works on
      # hosts that don't have a system-wide npx (e.g. fresh `maccaroni` setups).
      npx = lib.getExe' pkgs.nodejs "npx";

      mkRemoteServer = url: {
        command = npx;
        args = [
          "-y"
          "mcp-remote"
          url
        ];
        env = { };
      };

      # German dictionary for cspell (`@cspell/dict-de-de`), built straight
      # from its published npm tarball. cspell bundles English already, but
      # German ships as a separate package; rather than the README's
      # imperative `npm install -g @cspell/dict-de-de && cspell link add`,
      # we pin it here and import its `cspell-ext.json` by absolute store
      # path from the global cspell config below. The tarball unpacks under
      # `package/`, so `--strip-components=1` lands `cspell-ext.json` and
      # `de_DE.trie.gz` at the root of `$out` (the trie path inside the ext
      # file is relative, so both must sit side by side).
      cspellGermanDict =
        pkgs.runCommand "cspell-dict-de-de-4.1.2"
          {
            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/@cspell/dict-de-de/-/dict-de-de-4.1.2.tgz";
              hash = "sha256-bikoewusguLv1UvP2x3k9/KpSfBfNP1H88Xfqa1zaUE=";
            };
          }
          ''
            mkdir -p $out
            tar -xzf $src --strip-components=1 -C $out
          '';

      # Global cspell config read by `cspell-lsp` via `getGlobalSettingsAsync`
      # (macOS path: ~/Library/Preferences/cspell/cspell.json -- the path
      # documented in the zed-cspell README). This is the declarative
      # equivalent of the README's `cspell link add` + `dictionaries`
      # recipe: `import` registers the German dictionary definition built
      # above (replacing the imperative `npm install -g`/`cspell link`
      # step), `dictionaries` enables it by name (`de-de` from its
      # cspell-ext.json), and `language` sets the active locales. English
      # ships bundled with cspell and stays on via the `en` locale.
      cspellGlobalConfig = (pkgs.formats.json { }).generate "cspell.json" {
        version = "0.2";
        language = "en,de-DE";
        import = [ "${cspellGermanDict}/cspell-ext.json" ];
        dictionaries = [ "de-de" ];
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

      # ---- Extension resolution --------------------------------------------
      # One wanted-set (by Zed registry id) resolved into two install paths:
      #
      #   * source-built (preferred): packaged extensions are built from
      #     source and dropped into Zed's `installed` dir via
      #     `programs.zed-editor-extensions` -- pinned to the flake lock,
      #     reproducible, offline after the first build.
      #   * registry: unsupported ids, plus the Dart extension, are installed
      #     from Zed's hosted extension registry at runtime.
      #
      # `extensions.strategy = "registry"` forces the whole set back onto
      # auto-install (source builds skipped, fork excepted).
      wantedExtensions = lib.unique (
        [
          "ayu"
          "toml"
        ]
        ++ optionals cfg.extensions.flutter [ "dart" ]
        # Base `nix`: registry id only when the fork is off. The fork is a
        # source build appended to `sourcePackages` below.
        ++ optionals (cfg.extensions.nix && !cfg.extensions.nixInjectionFork) [ "nix" ]
        # The Rust extension only adds toolchain helpers; rust-analyzer
        # itself is bundled with Zed, so this stays optional.
        ++ optionals cfg.extensions.rust [ "rust" ]
        # `comment` is the registry id for thedadams/zed-comment.
        ++ optionals cfg.extensions.comment [ "comment" ]
        # `cspell` is the registry id for mantou132/zed-cspell. The
        # dictionaries are wired up via the global config in home.file
        # below (the LSP ignores Zed's `lsp.cspell.settings`).
        ++ optionals cfg.extensions.spellcheck [ "cspell" ]
        # Per-user escape hatch for extensions without a dedicated toggle.
        ++ cfg.extraExtensions
      );

      # Dart is intentionally hosted: it maintains writable grammar state, so
      # installing it through Zed's registry avoids a mutable Nix-store copy.
      # Split the remaining wanted set by whether nix-zed-extensions packages it.
      preferSource = cfg.extensions.strategy != "registry";
      isPackaged = id: builtins.hasAttr id pkgs.zed-extensions;
      sourceIds = optionals preferSource (
        builtins.filter (id: id != "dart" && isPackaged id) wantedExtensions
      );
      registryIds = builtins.filter (id: !(builtins.elem id sourceIds)) wantedExtensions;

      # The pinned Nix fork (grammar overridden to the injection-comment PR).
      # Always a source build -- it's a fork, not a registry extension -- so
      # it's independent of `strategy`. See `extensions.nixInjectionFork`.
      nixForkExtension =
        let
          nixGrammar = pkgs.zed-grammars.nix_nix.overrideAttrs (_: {
            src = pkgs.fetchFromGitHub {
              owner = "sebb3";
              repo = "tree-sitter-nix";
              rev = "1c903f05d9ff4b74f0836018729ecbefdd0fbdd0";
              hash = "sha256-KQ00kJo350Xhj2pFaaYDcgXvv1CxunnhWIBZth2e5es=";
            };
          });
        in
        (pkgs.zed-extensions.nix.override {
          zed-grammars = pkgs.zed-grammars // {
            nix_nix = nixGrammar;
          };
        }).overrideAttrs
          (_: {
            src = pkgs.fetchFromGitHub {
              owner = "sebb3";
              repo = "nix";
              rev = "926b7150ebba7631cd1ba9227445a3d7e7ec4665";
              hash = "sha256-ukS2q0nt8kG5xMc+WiBHZMu66mkBjt9iAnj9gzlA9JQ=";
            };
          });

      # Keep OpenSCAD's source provenance explicit. This revision currently
      # matches the upstream extension byte-for-byte, but it is fetched from
      # the requested johann-cm fork so later registry changes cannot replace
      # it unnoticed.
      openscadForkExtension = pkgs.zed-extensions.openscad.overrideAttrs (_: {
        src = pkgs.fetchFromGitHub {
          owner = "johann-cm";
          repo = "zed-openscad";
          rev = "39dae407545f99a911e3aa20fd9c9a9e8bf61d26";
          hash = "sha256-AZLaGlcA4Rx+dH72KdTiaIAYRbrWVyEgMBtEvIu1yII=";
        };
      });

      # Final list handed to programs.zed-editor-extensions.
      sourcePackages =
        map (id: pkgs.zed-extensions.${id}) sourceIds
        ++ lib.optional cfg.extensions.nixInjectionFork nixForkExtension
        ++ lib.optional cfg.extensions.openscad openscadForkExtension;
    in
    mkIf cfg.enable {
      programs.zed-editor = {
        package =
          if cfg.channel == "nightly" then
            # The upstream zed flake exposes the editor as `packages.<system>.default`.
            #
            # Workaround for aarch64-darwin: the final Zed binary has grown
            # past ~150MB of code, and at that size Apple's `ld64` can't
            # satisfy ARM64's ±128MB `b`/`bl` direct-branch range for some
            # cross-crate calls (e.g. `gpui_macos::window` calling into
            # `cocoa_foundation`). The link step dies with:
            #
            #     ld: b(l) ARM64 branch out of range (-159277244 max is +/-128MB)
            #
            # `zed.cachix.org` doesn't currently publish aarch64-darwin
            # builds of the nightly tip either, so we can't sidestep the
            # link by pulling a substitute. Two patches together get us
            # under the limit:
            #
            #   1. Drop the per-package `[profile.release.package.zed]`
            #      override (which bumps `codegen-units` back to 16 for
            #      faster upstream iteration). With cg=16 the top crate
            #      emits ~16 duplicated copies of all monomorphized
            #      generics; falling back to the workspace default of
            #      cg=1 shrinks the binary slightly (~1MB) and makes the
            #      output layout denser.
            #
            #   2. Force the final link through LLVM's `lld` (`ld64.lld`)
            #      instead of Apple's `ld64`. `lld` automatically emits
            #      long-range branch "veneers" / trampolines for out-of-
            #      range `bl` instructions, which is the well-trodden fix
            #      for this error. Apple's current `ld64` (both the new
            #      `ld-prime` codepath and the legacy `-ld_classic` mode)
            #      regressed this on aarch64-darwin in recent cctools
            #      versions and fails the link instead of inserting a
            #      thunk. We tried `-Wl,-ld_classic` first -- the flag
            #      is honored but the underlying linker behavior is
            #      identical, so it didn't help.
            #
            #      The flag is added by extending the existing `[build]`
            #      rustflags list in `.cargo/config.toml` (rather than a
            #      new `[target.aarch64-apple-darwin]` block), because
            #      cargo _replaces_, not merges, rustflags when a more
            #      specific target section matches -- and the existing
            #      list contains `--cfg tokio_unstable`, which the rest
            #      of the workspace relies on at compile time. `lld` is
            #      put on `$PATH` via `nativeBuildInputs` so that clang's
            #      `-fuse-ld=lld` driver flag can find `ld64.lld`.
            #
            # The two patches above run in the outer `buildPackage`, so on
            # their own they leave `cargoArtifacts` (the dep build) cached --
            # only the `zed`/`cli` recompile and final link redo. (NB: editing
            # `.cargo/config.toml` does invalidate cargo's own fingerprint
            # cache inside the sandbox, so the final-crate compile re-runs end
            # to end; that's intrinsic, not something this hack causes.) The
            # `src` override below is the exception -- see its comment.
            #
            # Revisit once upstream fixes this (e.g. by switching darwin
            # to `lto = "fat"`, dropping the cg=16 override, or shipping
            # cached binaries we can actually consume).
            (
              let
                zedBase = inputs.zed.packages.${pkgs.stdenv.hostPlatform.system}.default;
                inherit (zedBase.passthru) craneLib commonArgs;

                # 3. Restore `corgi-patches/` to the build source.
                #
                #    Upstream's `nix/build.nix` filters the checkout down to a
                #    `topLevelIncludes` whitelist before handing it to crane.
                #    zed-industries/zed@ee6badf ("Support building with corgi",
                #    #63396, 2026-08-31) added
                #
                #        [patch.crates-io.scratch]
                #        path = "corgi-patches/scratch"
                #
                #    to the workspace Cargo.toml but never added
                #    `corgi-patches` to that whitelist (last touched
                #    2026-06-30). The directory is therefore filtered out and
                #    every nightly since then dies during dependency
                #    resolution with:
                #
                #        error: failed to load source for dependency `scratch`
                #        ... failed to read `.../corgi-patches/scratch/Cargo.toml`
                #
                #    The list below is upstream's verbatim, plus
                #    `corgi-patches`. Drop this whole `src`/`cargoArtifacts`
                #    override once upstream adds it -- watch `topLevelIncludes`
                #    in zed's `nix/build.nix`.
                src = builtins.path {
                  path = inputs.zed;
                  name = "source";
                  filter =
                    path: _type:
                    let
                      root = toString inputs.zed + "/";
                      relPath = lib.removePrefix root path;
                      firstComp = builtins.head (lib.path.subpath.components relPath);
                    in
                    builtins.elem firstComp [
                      "crates"
                      "assets"
                      "extensions"
                      "script"
                      "tooling"
                      "Cargo.toml"
                      ".config"
                      ".cargo"
                      "corgi-patches"
                    ];
                };

                #    The failure is in the *dependency* derivation, which crane
                #    derives from `commonArgs.src` via `mkDummySrc`, so an
                #    `overrideAttrs` on the outer package is not enough -- the
                #    deps have to be rebuilt against the corrected source too.
                #    Upstream's `passthru` exposes exactly what's needed to do
                #    that without restating its ~90-line `buildPackage` call.
                cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { inherit src; });
              in
              zedBase.overrideAttrs (old: {
                inherit src cargoArtifacts;
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.lld ];
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace Cargo.toml \
                    --replace-fail \
                      'zed = { codegen-units = 16 }' \
                      '# zed = { codegen-units = 16 } # patched out by darwin-config (modules/zed.nix) -- see comment there'

                  substituteInPlace .cargo/config.toml \
                    --replace-fail \
                      'rustflags = ["-C", "symbol-mangling-version=v0", "--cfg", "tokio_unstable"]' \
                      'rustflags = ["-C", "symbol-mangling-version=v0", "--cfg", "tokio_unstable", "-C", "link-arg=-fuse-ld=lld"]'
                '';
              })
            )
          else
            inputs.nixpkgsunstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor;
        enable = true;
        # Registry fallback only -- the source-built ids are installed via
        # `programs.zed-editor-extensions` below. See the resolver in the
        # `let` above (`wantedExtensions` -> `registryIds`/`sourceIds`).
        extensions = registryIds;

        # Shared defaults are defined inline below; per-user tweaks come in
        # via `cfg.extraSettings` (see e.g. `specifics/hannes/home.nix`).
        # `lib.recursiveUpdate` deep-merges with right-side precedence, so
        # individual leaf keys (or whole nested attrsets) can be overridden
        # without restating the rest of the defaults.
        userSettings = lib.recursiveUpdate {
          icon_theme = "Material Icon Theme";

          theme = {
            mode = "system";
            inherit (cfg.theme) dark light;
          };

          # Per-theme tweaks. Only the keys listed here override the base
          # theme; everything else is inherited.
          theme_overrides = {
            "Palenight Theme" = {
              "editor.background" = "#191D2b";
              "scrollbar.track.background" = "#191D2b";
              "scrollbar.track.border" = "#191D2b";
              "tab.active_background" = "#191D2b";
              "toolbar.background" = "#191D2b";
              "title_bar.background" = "#191D2b";
              background = "#191D2b";
              # "elevated_surface.background" = "#191D2e";
              # "surface.background" = "#191D2b";
              "editor.gutter.background" = "#191D2b";
              "error.background" = "#4d2b2b";
              "warning.background" = "#4a4327";
              "panel.background" = "#292D3e";
              syntax = {
                type = {
                  color = "#dcd288ff";
                  font_style = null;
                  font_weight = null;
                };
              };
              accents = [
                "#5b0"
                "#0ab"
              ];
            };
          };

          # `base_keymap` is intentionally not set here -- it's a personal
          # preference, so users opt into VSCode/Atom/JetBrains bindings via
          # `myModules.zed.extraSettings.base_keymap`.
          vim_mode = false;

          # Disable diagnostics + usage telemetry.
          telemetry = {
            diagnostics = false;
            metrics = false;
          };

          # External (ACP) agent servers. Cursor's agent via its registry.
          agent_servers = {
            cursor = {
              type = "registry";
              default_config_options = {
                model = "gpt-5.5[context=272k,reasoning=medium,fast=false]";
              };
            };
          };

          # ---- Edit prediction (a.k.a. inline AI completions) ------------------
          # Selected by `myModules.zed.editPrediction.provider`:
          #
          # - `"zed"` *(default)*: Zed's own hosted Zeta service. No local
          #   model, GPU, or RAM cost; uses a zed.dev sign-in. This is the
          #   default so machines don't run a local LLM unless they opt in.
          # - `"local"`: the Metal-accelerated `mlx_lm.server` from
          #   `modules/ai.nix` (enable via `myModules.ai.enable`). Fully
          #   offline and sign-in free, running Zeta 2.1 (Zed's own
          #   edit-prediction model) by default. The model + prompt_format
          #   come from `editPrediction.preset`, which must match the
          #   backend's `myModules.ai.preset`. The port is hardcoded here
          #   because home-manager can't read the system module's options
          #   -- keep in sync with `myModules.ai.port`.
          #
          # For other providers (`"copilot"`, `"none"`, ...) override via
          # `extraSettings.edit_predictions.provider`.
          edit_predictions = {
            # Never upload edit-prediction data to Zed's training set.
            allow_data_collection = "no";

            # Inert unless `provider` is flipped to ollama -- kept so the
            # endpoint/model are preconfigured if you switch locally.
            ollama = {
              api_url = "http://localhost:11434";
              max_output_tokens = 512;
              model = "qwen2.5-coder:1.5b-base";
              prompt_format = "qwen";
            };
          }
          // (
            if cfg.editPrediction.provider == "local" then
              {
                provider = "open_ai_compatible_api";
                open_ai_compatible_api = {
                  api_url = "http://localhost:8080/v1/completions";
                  model = epPreset.model;
                  prompt_format = epPreset.promptFormat;
                  max_output_tokens = 512;
                };
              }
            else
              {
                provider = "zed";
              }
          );

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

          # ---- Editor behavior -------------------------------------------------
          # `semantic_tokens = off` keeps Tree-sitter highlighting authoritative
          # so the `comment` extension (and others that rely on injections) win
          # over LSP-provided semantic tokens.
          semantic_tokens = "off";
          lsp_document_colors = "inlay";
          colorize_brackets = true;
          indent_guides = {
            background_coloring = "disabled";
            coloring = "indent_aware";
          };

          # ---- App behavior ----------------------------------------------------
          cli_default_open_behavior = "new_window";

          # ---- Layout / panels -------------------------------------------------
          bottom_dock_layout = "contained";

          collaboration_panel = {
            dock = "left";
          };

          git_panel = {
            group_by = "none";
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
            sidebar_side = "right";
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
              model = "claude-opus-4-8";
              enable_thinking = true;
              effort = "high";
            };
            model_parameters = [ ];

            default_profile = "write";

            # Custom agent profiles (per-task tool + context-server
            # allowlists). Tool entries are harmless on hosts where a given
            # MCP server isn't enabled.
            profiles = {
              investigate = {
                name = "investigate";
                default_model = {
                  provider = "anthropic";
                  model = "claude-opus-4-8";
                  enable_thinking = true;
                  effort = "high";
                };
                tools = {
                  copy_path = true;
                  diagnostics = true;
                  fetch = true;
                  find_path = true;
                  grep = true;
                  list_directory = true;
                  read_file = true;
                  skill = true;
                  spawn_agent = true;
                };
                enable_all_context_servers = false;
                context_servers = {
                  "sentry-mcp".tools = {
                    whoami = true;
                    update_project = true;
                    update_issue = true;
                    search_issues = true;
                    search_issue_events = true;
                    search_events = true;
                    search_docs = true;
                    get_sentry_resource = true;
                    get_replay_details = true;
                    get_profile_details = true;
                    get_issue_tag_values = true;
                    get_event_attachment = true;
                    get_doc = true;
                    find_teams = true;
                    find_releases = true;
                    find_projects = true;
                    find_organizations = true;
                    find_dsns = true;
                    analyze_issue_with_seer = true;
                  };
                  "mcp-server-figma".tools = {
                    get_figma_data = true;
                    download_figma_images = true;
                  };
                  linear.tools = {
                    prepare_attachment_upload = true;
                    list_users = true;
                    list_teams = true;
                    list_projects = true;
                    list_project_labels = true;
                    list_milestones = true;
                    list_issues = true;
                    list_issue_statuses = true;
                    list_issue_labels = true;
                    list_initiatives = true;
                    list_documents = true;
                    list_diffs = true;
                    list_cycles = true;
                    list_comments = true;
                    get_user = true;
                    get_team = true;
                    get_status_updates = true;
                    get_project = true;
                    get_milestone = true;
                    get_issue_status = true;
                    get_issue = true;
                    get_initiative = true;
                    get_document = true;
                    get_diff_threads = true;
                    get_diff = true;
                    get_attachment = true;
                  };
                  dart.tools = {
                    stop_app = true;
                    signature_help = true;
                    set_widget_selection_mode = true;
                    run_tests = true;
                    resolve_workspace_symbol = true;
                    remove_roots = true;
                    read_package_uris = true;
                    pub_dev_search = true;
                    list_running_apps = true;
                    list_devices = true;
                    launch_app = true;
                    hover = true;
                    hot_restart = true;
                    hot_reload = true;
                    get_widget_tree = true;
                    get_selected_widget = true;
                    get_runtime_errors = true;
                    get_app_logs = true;
                    get_active_location = true;
                    flutter_driver = true;
                    dart_fix = false;
                    create_project = false;
                    connect_dart_tooling_daemon = true;
                    analyze_files = true;
                    add_roots = true;
                  };
                };
              };
              write = {
                name = "Write";
                tools = {
                  copy_path = true;
                  create_directory = true;
                  delete_path = true;
                  diagnostics = true;
                  edit_file = true;
                  fetch = true;
                  list_directory = true;
                  project_notifications = false;
                  move_path = true;
                  now = true;
                  find_path = true;
                  read_file = true;
                  restore_file_from_disk = true;
                  save_file = true;
                  open = true;
                  grep = true;
                  spawn_agent = true;
                  terminal = true;
                  thinking = true;
                  update_plan = true;
                  search_web = true;
                };
                enable_all_context_servers = true;
                context_servers = { };
              };
            };

            # Allowlist read-only tools and well-anchored shell commands so
            # the agent can run them without prompting.
            tool_permissions = {
              tools = {
                fetch.default = "allow";
                move_path.default = "allow";
                create_directory.default = "allow";
                copy_path.default = "allow";
                "mcp:dart:add_roots".default = "allow";
                "mcp:dart:analyze_files".default = "allow";
                "mcp:dart:connect_dart_tooling_daemon".default = "allow";
                "mcp:dart:dart_format".default = "allow";
                "mcp:dart:flutter_driver".default = "allow";
                "mcp:dart:get_runtime_errors".default = "allow";
                "mcp:dart:get_widget_tree".default = "allow";
                "mcp:dart:hot_restart".default = "allow";
                "mcp:dart:hover".default = "allow";
                "mcp:dart:launch_app".default = "allow";
                "mcp:dart:list_devices".default = "allow";
                "mcp:dart:pub".default = "allow";
                "mcp:dart:pub_dev_search".default = "allow";
                "mcp:dart:read_package_uris".default = "allow";
                "mcp:dart:remove_roots".default = "allow";
                "mcp:dart:run_tests".default = "allow";
                "mcp:linear:get_diff".default = "allow";
                "mcp:linear:get_diff_threads".default = "allow";
                "mcp:linear:get_issue".default = "allow";
                "mcp:linear:list_comments".default = "allow";
                "mcp:linear:list_diffs".default = "allow";
                "mcp:linear:list_teams".default = "allow";
                "mcp:linear:search_documentation".default = "allow";
                "mcp:sentry-mcp:find_organizations".default = "allow";
                "mcp:sentry-mcp:get_sentry_resource".default = "allow";
                "mcp:sentry-mcp:search_events".default = "allow";
                "mcp:sentry-mcp:search_issues".default = "allow";
                "mcp:mcp-server-figma:get_figma_data".default = "allow";
                "mcp:mcp-server-figma:download_figma_images".default = "allow";
                edit_file = {
                  always_allow = [
                    { pattern = "^app/\\.zed/"; }
                  ];
                };
                write_file = {
                  always_allow = [
                    { pattern = "^zed-single-launch-debug/\\.zed/"; }
                  ];
                };
                delete_path = {
                  default = "allow";
                  always_allow = [
                    { pattern = "^be/src/models/"; }
                    { pattern = "^be/src/modules/billing/v2/features/"; }
                  ];
                };
                terminal = {
                  default = "allow";
                  always_allow = [
                    { pattern = "^ls\\b"; }
                    { pattern = "^sort\\b"; }
                    { pattern = "^tail\\b"; }
                    { pattern = "^grep\\b"; }
                    { pattern = "^head\\b"; }
                    { pattern = "^find\\s+/nix/store(\\s|$)"; }
                    { pattern = "^xargs\\s+grep(\\s|$)"; }
                    { pattern = "^git\\s+log(\\s|$)"; }
                    { pattern = "^git\\s+show(\\s|$)"; }
                  ];
                };
              };
            };
          };

          context_servers = contextServers;
        } cfg.extraSettings;
      };

      # Source-built extensions dropped into Zed's `installed` dir (pinned +
      # reproducible). Content comes from the resolver in the `let` above:
      # every packaged id under strategy `auto`, plus the grammar-overridden
      # Nix fork when `extensions.nixInjectionFork` is on. Empty (module
      # inactive) under strategy `registry` with the fork off.
      programs.zed-editor-extensions = lib.mkIf (sourcePackages != [ ]) {
        enable = true;
        packages = sourcePackages;
      };



      home.packages = lib.optional (cfg.fontFamily == "FiraCode Nerd Font") pkgs.nerd-fonts.fira-code;

      # Global cspell config consumed by `cspell-lsp` (see the `spellcheck`
      # toggle). Lives outside Zed's own settings because the LSP only
      # reads cspell config files, not Zed's `lsp.*.settings`.
      home.file = lib.mkIf cfg.extensions.spellcheck {
        "Library/Preferences/cspell/cspell.json".source = cspellGlobalConfig;
      };
    };
}
