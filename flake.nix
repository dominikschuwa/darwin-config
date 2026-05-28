{
  description = "darwin config for bling";

  # NOTE: `inputs` must be a static attrset literal -- modern Nix rejects
  # thunks (e.g. a `let ... in { ... }` wrapper) here. If you need to bump
  # the nixpkgs/nix-darwin/home-manager release line, update the three
  # `25.11`s below in lock-step.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgsunstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";

    prismLauncher.url = "github:HannesGitH/prismlauncherc";
    nix-search-cli.url = "github:peterldowns/nix-search-cli";
    mergiraf.url = "git+https://codeberg.org/HannesGitH/mergiraf";

    frosted.url = "github:HannesGitH/frosted";

    # secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    zed.url = "github:zed-industries/zed";

    zsh-nix-shell = {
      url = "github:chisui/zsh-nix-shell/v0.7.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      secretsModules = [
        # nix-shell -p gnupg -p ssh-to-age --run "ssh-to-age -i $HOME/.ssh/id_ed25519.pub"
        # nix-shell -p gnupg -p ssh-to-age --run "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519" > $HOME/Library/Application\ Support/sops/age/keys.txt
        inputs.sops-nix.darwinModules.sops
        {
          # sops.defaultSopsFile = ./secrets/secrets2.yaml;
          sops.age.sshKeyPaths = [ "/Users/blingmember/.ssh/id_ed25519" ];
          # This is using an age key that is expected to already be in the filesystem
          # sops.age.keyFile = "/Users/blingmember/Library/Application Support/sops/age/keys.txt";
          sops.age.generateKey = true;
          sops.secrets = {
            "keyAndroid.jks" = {
              format = "binary";
              sopsFile = ./secrets/keyAndroid.jks;
              owner = "blingmember";
              mode = "0644";
              path = "/Users/blingmember/keyAndroid.jks";
            };
          };
        }
      ];
      globalModules = [
        {
          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;
        }
        inputs.nix-index-database.darwinModules.nix-index
        home-manager.darwinModules.home-manager
        (
          { pkgs, ... }:
          {
            # inherit nixpkgs;
            # `home-manager` config
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Move pre-existing dotfiles aside (e.g. Zen's profiles.ini) instead
            # of aborting activation. Backups land next to the originals as
            # `<name>.hm-backup` so they're recoverable if anything was lost.
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.sharedModules = [
              ./global/home.nix
            ];
          }
        )
        ./global/config.nix
        ./modules/ai.nix
      ]
      ++ secretsModules;
    in
    {
      darwinConfigurations = {
        # HANNES config
        "maccaroni" = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = globalModules ++ [
            {
              home-manager.users."blingmember" = import ./specifics/hannes/home.nix;
            }
            ./specifics/hannes/config.nix
            ./specifics/backend/config.nix
          ];
        };
        # schuwas config
        "rigatoni" = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = globalModules ++ [
            {
              # otherwise home-manager will ignore this user (and its sharedModules)
              home-manager.users."blingmember" = import ./specifics/schuwa/home.nix;
            }
            ./specifics/schuwa/config.nix
          ];
        };
        # general config
        "blingi" = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = globalModules ++ [
            {
              # otherwise home-manager will ignore this user (and its sharedModules)
              home-manager.users."blingmember" = { };
            }
          ];
        };
      };

      # sudo ln -s /Users/blingmember/Repos/nix-darwin-config/scripts/com.bling.wasyle.plist /Library/LaunchDaemons/com.bling.wasyle.plist
      # sudo launchctl load /Library/LaunchDaemons/com.bling.wasyle.plist
    };
}
