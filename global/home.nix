{
  config,
  pkgs,
  inputs,
  ...
}:

{

  imports = [
    inputs.zen-browser.homeModules.beta
    # Adds `programs.zed-editor-extensions` (source-built Zed extensions),
    # used by modules/zed.nix's `extensions.nixInjectionFork` toggle.
    inputs.nix-zed-extensions.homeManagerModules.default
    ../modules/zed.nix
    ../modules/git.nix
  ];

  # home.userName = "blingmember";
  # home.homeDirectory = "/home/blingmember";

  home.packages = with pkgs; [

    autojump

    #nodejs
    #yarn

  ];

  myModules.zed = {
    enable = true;
    # Extension toggles default to `true` in `modules/zed.nix`, so there's
    # no need to restate them here. Per-user opt-outs live in
    # `specifics/<user>/home.nix`

    # Use the sebb3 Nix-extension fork (runnable flake tasks + dynamic
    # comment-based language injection). Off by default in the module;
    # opt in here. Supersedes the registry `nix` extension. Remove once
    # nix-community/tree-sitter-nix#166 + zed-extensions/nix#49 land.
    extensions.nixInjectionFork = true;

    # Source-build the johann-cm/zed-openscad fork, rather than the
    # similarly named registry extension.
    extensions.openscad = true;

    mcp = {
      linear.enable = true;
      dart = {
        enable = true;
        # Match the fvm-managed Dart SDK that's already on the user's
        # zsh PATH (see initContent below); spelled out absolutely so
        # Zed launched from Spotlight/Finder still resolves it.
        command = "${config.home.homeDirectory}/fvm/default/bin/dart";
      };
      figma.enable = true;
    };
  };

  programs.zen-browser = {
    enable = true;

    # zen-browser-flake #361 made "signed" the Darwin default: the upstream
    # .app is installed untouched (keeping its signature, and with it 1Password,
    # iCloud Passwords and Touch ID) and policies are routed through
    # targets.darwin.defaults instead of wrapFirefox. That needs the
    # `lib.functionArgs package.override ? cfg` guard in home-manager's
    # mkFirefoxModule, which only exists on HM master -- our home-manager input
    # tracks release-26.05, whose wrapPackage unconditionally does
    # `package.override { cfg = ...; }` and so fails on the unwrapped .app with
    # "function 'anonymous lambda' called with unexpected argument 'cfg'".
    # "wrapped" is the pre-#361 behaviour. Drop this once release-26.06 (or
    # a HM release carrying that guard) lands.
    darwin.packageMode = "wrapped";

    # Declare a single default profile so that profiles.ini always
    # contains a Default=1 entry. Without this, every Nix rebuild
    # produces a new install-hash for Zen, which Zen treats as a
    # brand-new install and uses to create a fresh empty profile,
    # orphaning logins/history/sessions/extensions. With a declared
    # default present, new install-hashes fall through to this
    # profile instead of spawning a new one.
    #
    # home-manager only manages files it is told about, so
    # places.sqlite, key4.db, logins.json, cookies.sqlite,
    # extensions/, etc. inside Profiles/main are left untouched.
    # Only the prefs declared in `settings` below are written to
    # the profile's user.js.
    profiles.main = {
      # Force DNS-over-HTTPS through Quad9 (TRR mode 2 = DoH first,
      # fall back to native DNS on failure).
      settings = {
        "network.trr.mode" = 2;
        "network.trr.uri" = "https://dns.quad9.net/dns-query";
        "network.trr.bootstrapAddress" = "9.9.9.9";
      };
    };

    policies =
      let
        mkExtensionSettings = builtins.mapAttrs (
          _: pluginId: {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${pluginId}/latest.xpi";
            installation_mode = "force_installed";
          }
        );
      in
      {
        ExtensionSettings = mkExtensionSettings {
          "ublock-origin" = "uBlock0@raymondhill.net";
        };
      };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  home.file.".config/direnv/direnv.toml".text = ''
    [global]

    [whitelist]
    prefix = [ "${config.home.homeDirectory}/repos/b" ]
  '';

  programs.pay-respects = {
    enable = true;
  };

  programs.zsh = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      n-s = "nix-shell";
      ns = "nix shell";
      ndh = "nix develop . -c zsh";

      fflutter = "fvm flutter";

      editzshrc = "code $HOME/.zshrc";
      gbrclean = "git branch | xargs -I {} git branch -d {}";
      # pod="arch -x86_64 pod";

      gmud = "git fetch upstream && git merge upstream/dev || git mergetool";
      gnew = "echo 'deprecated, use gneu'; gneu"; # defined below
    };
    #histSize = 10000;
    #histFile = "$HOME/.zsh_history";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "autojump"
      ];
      theme = "robbyrussell";
    };
    plugins = [
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = inputs.zsh-nix-shell;
      }
    ];
    initContent = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
      export PATH="$HOME/fvm/default/bin:$PATH"

      # User-installed binaries, incl. the cursor-agent CLI (`agent`).
      export PATH="$HOME/.local/bin:$PATH"

      # Option+Right / Option+Left to jump words (matches macOS Terminal/iTerm2 default escape sequences)
      bindkey "\e[1;3C" emacs-forward-word
      bindkey "\e[1;3D" emacs-backward-word

      export PATH="$PATH":"$HOME/.pub-cache/bin"

      export NODE_OPTIONS='--no-experimental-strip-types'

      # cargo (installed via rustup)
      # . "$HOME/.cargo/env"

      export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
      export ANDROID_HOME="/Users/blingmember/Library/Android/sdk"
      export PATH="$PATH:$ANDROID_HOME/tools"
      export PATH="$PATH:$ANDROID_HOME/platform-tools"

      # things that are to hefty for alias :D

      gneu() {
        g fetch upstream &&
        gsw -c "$1" upstream/dev --no-track;
      }
      gneo() {
        g fetch origin &&
        gsw -c "$1" origin/dev --no-track;
      }
    '';
  };
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      # Mergetool entries (vscode/cursor/zed) and `merge.tool` live in
      # `modules/git.nix`, which picks the right zed binary name based on
      # `myModules.zed.channel` and exposes `myModules.git.mergetool` for
      # per-user overrides.
      # on a new machine, run `mergiraf languages --gitattributes >> ~/.gitattributes`
      core.attributesfile = "~/.gitattributes";
      core.untrackedCache = true;
      core.fsmonitor = true;
      merge = {
        mergiraf = {
          name = "mergiraf";
          driver = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L";
        };
        conflictstyle = "diff3";
      };
    };
  };

  home.stateVersion = "23.11";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
