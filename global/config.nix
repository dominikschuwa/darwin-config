{ pkgs, inputs,... }: {

      ids.gids.nixbld = 350;

      nixpkgs.config.allowUnfree = true;

      environment.variables.LANG = "en_GB.UTF-8";

      environment.systemPackages = with pkgs;
        [ 
          libiconv
          libiconv-darwin
          git
          git-lfs
          rename
          nil
          autojump
          go
          inputs.nix-search-cli.packages.${pkgs.system}.default
#          gimp
          bundletool
          gnupg

          # firefox

          (inputs.mergiraf.packages.${pkgs.system}.default.overrideAttrs (old: { doCheck = false; doInstallCheck = false; }))
        ];

      system.activationScripts.extraActivation.text = ''
        ln -sf "${pkgs.jdk8}/zulu-8.jdk" "/Library/Java/JavaVirtualMachines/"
        ln -sf "${pkgs.jdk11}/zulu-11.jdk" "/Library/Java/JavaVirtualMachines/"
        ln -sf "${pkgs.jdk17}/zulu-17.jdk" "/Library/Java/JavaVirtualMachines/"
        ln -sf "${pkgs.jdk21}/zulu-21.jdk" "/Library/Java/JavaVirtualMachines/"
      '';

      programs.nix-index-database.comma.enable = true;


      homebrew = {
          enable = true;
          # onActivation.cleanup = "uninstall";

          taps = [ "leoafarias/fvm"  ];
          brews = [ 
            "fvm" 
            # "cocoapods" #!# /opt/homebrew/Cellar/cocoapods/1.15.2_1/libexec/bin/pod: /opt/homebrew/opt/ruby/bin/ruby: bad interpreter seems like it didnt find ruby where it thought it would be
            "gh" 
            # "ruby" 
            # "font-fira-code"
            # "wireshark"
          ];
          casks = [
            # "displaylink"
            "raycast"
            # "visual-studio-code"
            "cursor"
            "android-studio"
          ];
      };

      nix.extraOptions = ''
        extra-platforms = x86_64-darwin aarch64-darwin
        sandbox = false
      '';


      # Auto upgrade nix package and the daemon service.
      nix.enable = true;
      # nix.package = pkgs.nix;


      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      nix.settings.trusted-users = [ "blingmember" ];
      system.primaryUser = "blingmember";

      # Create /etc/zshrc that loads the nix-darwin environment.
      programs.zsh.enable = true;  # default shell on catalina
      # programs.fish.enable = true;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;

      system.defaults = {
        dock = {
          magnification = true;
          tilesize = 20;
          largesize = 50;
          show-process-indicators = true;
          persistent-apps = [ "/Applications/Nix\ Apps/Firefox.app" "/Applications/Cursor.app" ];
        };
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          "com.apple.trackpad.scaling" = 2.0;
        };
        finder = {
          AppleShowAllFiles = true;
          AppleShowAllExtensions = true;
          QuitMenuItem = true;
          FXEnableExtensionChangeWarning = false;
        };
      };

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

      security.pam.services.sudo_local.touchIdAuth = true;

      users.users."blingmember".home = "/Users/blingmember";
    }
