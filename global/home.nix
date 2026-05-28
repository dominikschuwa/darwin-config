{
  config,
  pkgs,
  inputs,
  ...
}:

{

  imports = [
    inputs.zen-browser.homeModules.beta
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

  programs.zen-browser = {
    enable = true;

    # Declare a single default profile so that profiles.ini always
    # contains a Default=1 entry. Without this, every Nix rebuild
    # produces a new install-hash for Zen, which Zen treats as a
    # brand-new install and uses to create a fresh empty profile,
    # orphaning logins/history/sessions/extensions. With a declared
    # default present, new install-hashes fall through to this
    # profile instead of spawning a new one.
    #
    # Empty body is intentional: home-manager only manages files it
    # is told about, so places.sqlite, key4.db, logins.json,
    # cookies.sqlite, extensions/, etc. inside Profiles/main are
    # left untouched.
    profiles.main = { };

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

      # Option+Right / Option+Left to jump words (matches macOS Terminal/iTerm2 default escape sequences)
      bindkey "\e[1;3C" emacs-forward-word
      bindkey "\e[1;3D" emacs-backward-word

      export PATH="$PATH":"$HOME/.pub-cache/bin"

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
