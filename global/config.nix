{ pkgs, inputs, ... }:
let
  # Pull substituters / trusted public keys straight from upstream Zed's
  # flake.nix (`nixConfig`) instead of duplicating them here. `inputs.zed`
  # resolves to the locked flake source in /nix/store, and its top-level
  # flake.nix is a plain attrset literal so we can `import` it directly.
  zedNixConfig = (import (inputs.zed + "/flake.nix")).nixConfig;
in
{

  ids.gids.nixbld = 350;

  nixpkgs.config.allowUnfree = true;

  # direnv 2.37.1's `test-fish` is flaky on darwin and gets SIGKILL'd
  # mid-build (`make: *** [GNUmakefile:150: test-fish] Killed: 9`).
  # Skip its checks until upstream stabilises it.
  nixpkgs.overlays = [
    (final: prev: {
      direnv = prev.direnv.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
    inputs.zed.overlays.default
  ];

  environment.variables.LANG = "en_GB.UTF-8";

  environment.systemPackages = with pkgs; [
    libiconv
    darwin.libiconv
    git
    git-lfs
    rename
    nil
    autojump
    go
    inputs.nix-search-cli.packages.${pkgs.system}.default
    bundletool
    gnupg

    kitty
    btop

          # firefox

    (inputs.mergiraf.packages.${pkgs.system}.default.overrideAttrs (old: {
      doCheck = false;
      doInstallCheck = false;
    }))
  ];

  system.activationScripts = {
    extraActivation.text = ''
      # ${pkgs.defaultbrowser}/bin/defaultbrowser firefox
      ln -sfn "${pkgs.jdk8}/Library/Java/JavaVirtualMachines/zulu-8.jdk" "/Library/Java/JavaVirtualMachines/"
      ln -sfn "${pkgs.jdk11}/Library/Java/JavaVirtualMachines/zulu-11.jdk" "/Library/Java/JavaVirtualMachines/"
      ln -sfn "${pkgs.jdk17}/Library/Java/JavaVirtualMachines/zulu-17.jdk" "/Library/Java/JavaVirtualMachines/"
      ln -sfn "${pkgs.jdk21}/Library/Java/JavaVirtualMachines/zulu-21.jdk" "/Library/Java/JavaVirtualMachines/"
    '';
    # Reload system.defaults into the running session so changes
    # (e.g. NSGlobalDomain.AppleInterfaceStyle) apply without logout.
    # `postActivation` is the last stock hook and runs after `userDefaults`
    # has written the plist. Since activation runs as root but
    # `activateSettings -u` must run in the primary user's context,
    # we drop privileges via `sudo -u`.
    postActivation.text = ''
      sudo -u blingmember /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';
  };

  programs.nix-index-database.comma.enable = true;

  homebrew = {
    enable = true;
    # onActivation.cleanup = "uninstall";

    taps = [ "leoafarias/fvm" ];
    brews = [
      "fvm"
      # "cocoapods" #!# /opt/homebrew/Cellar/cocoapods/1.15.2_1/libexec/bin/pod: /opt/homebrew/opt/ruby/bin/ruby: bad interpreter seems like it didnt find ruby where it thought it would be
      "gh"
      # "ruby"
      # "font-fira-code"
      # "wireshark"
      # "ideviceinstaller" # needed for flutter patrol tests
    ];
    casks = [
      # "displaylink"
      "raycast"
      "visual-studio-code"
      "cursor"
      "android-studio"
      "slack"
      "1password"
      "1password-cli"
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

  nix.settings.substituters = [
    "https://nixos-cache-proxy.cofob.dev"
  ];
  nix.settings.extra-substituters = zedNixConfig.extra-substituters;
  nix.settings.extra-trusted-public-keys = zedNixConfig.extra-trusted-public-keys;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  # programs.fish.enable = true;

  programs.gnupg.agent.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  system.defaults = {
    dock = {
      magnification = true;
      tilesize = 20;
      largesize = 50;
      show-process-indicators = true;
      persistent-apps = [
        "/Applications/Nix\ Apps/Firefox.app"
        "${pkgs.kitty}/Applications/kitty.app"
      ];
    };
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      "com.apple.trackpad.scaling" = 2.0;
      "com.apple.keyboard.fnState" = true;
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
