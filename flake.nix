{
  description = "darwin config for bling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nix-darwin.url = "github:LnL7/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";

    prismLauncher.url = "github:HannesGitH/prismlauncherc";
    nix-search-cli.url = "github:peterldowns/nix-search-cli";
    mergiraf.url = "git+https://codeberg.org/HannesGitH/mergiraf";

    frosted.url = "github:HannesGitH/frosted";

    # secrets management
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nix-darwin, nixpkgs, home-manager, ... }@inputs:
  let 
    secretsModules = [
      # nix-shell -p gnupg -p ssh-to-age --run "ssh-to-age -i $HOME/.ssh/id_ed25519.pub"
      # nix-shell -p gnupg -p ssh-to-age --run "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519" > $HOME/Library/Application\ Support/sops/age/keys.txt
      inputs.sops-nix.darwinModules.sops
      {
        sops.defaultSopsFile = ./secrets/secrets2.yaml;
        sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        # This is using an age key that is expected to already be in the filesystem
        sops.age.keyFile = "/Users/blingmember/Library/Application Support/sops/age/keys.txt";
        sops.age.generateKey = true;
        sops.secrets = {
          ".netrc" = {
            owner = "blingmember";
            mode = "0600";
            path = "/Users/blingmember/.netrc";
          };
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
      {
        # inherit nixpkgs;
        # `home-manager` config
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.sharedModules = [
          ./global/home.nix
        ];
      }
      ./global/config.nix
    ] ++ secretsModules;
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
            home-manager.users."blingmember" = {};
          }
        ];
      };
    };

    # sudo ln -s /Users/blingmember/Repos/nix-darwin-config/scripts/com.bling.wasyle.plist /Library/LaunchDaemons/com.bling.wasyle.plist
    # sudo launchctl load /Library/LaunchDaemons/com.bling.wasyle.plist
  };
}
