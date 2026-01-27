{ config, pkgs, ... }:

{

    # home.userName = "blingmember";
    # home.homeDirectory = "/home/blingmember";

    home.packages = with pkgs; [

      autojump

      #nodejs
      #yarn

    ];

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

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
        
        fb="fvm dart run build_runner build --delete-conflicting-outputs";
        fg="fvm flutter pub get";
        fcl="fvm flutter clean && rm -rf ~/Library/Developer/Xcode/DerivedData && fvm flutter pub get && rm -rf ./build/app/outputs/apk";
        fclh="rm ios/Podfile.lock && rm -rf ios/Pods && pod install --repo-update --project-directory=ios && fcl";

        editzshrc="code $HOME/.zshrc";
        gbrclean="git branch | xargs -I {} git branch -d {}";
        # pod="arch -x86_64 pod";

        gmud="git fetch upstream && git merge upstream/dev || git mergetool";
        gnew="g fetch upstream && gsw dev && g pull upstream dev && gsw -c";
      };
      #histSize = 10000;
      #histFile = "$HOME/.zsh_history";
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        plugins = [ "git" "autojump" ];
        theme = "robbyrussell";
      };
      plugins = [
        {
          name = "zsh-nix-shell";
          file = "nix-shell.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "chisui";
            repo = "zsh-nix-shell";
            rev = "v0.7.0";
            sha256 = "149zh2rm59blr2q458a5irkfh82y3dwdich60s9670kl3cl5h2m1";
          };
        }
      ];
      initContent = ''
        eval "$(/opt/homebrew/bin/brew shellenv)"
        export PATH="$HOME/fvm/default/bin:$PATH"

        export PATH="$PATH":"$HOME/.pub-cache/bin"

        # cargo (installed via rustup)
        . "$HOME/.cargo/env"

        export JAVA_HOME="/Library/Java/JavaVirtualMachines/corretto-17.0.16/Contents/Home"
      '';
    };
    programs.git = {
      enable = true;
      lfs.enable = true;
      extraConfig = {
        push.autoSetupRemote = true;
        "mergetool \"vscode\"" = {
          cmd = "code --wait $MERGED";
          trustExitCode = true;
        };
        "mergetool \"vscursor\"" = {
          cmd = "cursor --wait $MERGED";
          trustExitCode = true;
        };
        # on a new machine, run `mergiraf languages --gitattributes >> ~/.gitattributes`
        core.attributesfile = "~/.gitattributes";
        merge = {
          tool = "vscursor";
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