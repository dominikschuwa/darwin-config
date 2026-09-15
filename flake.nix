{
  description = "darwin config for bling";

  # NOTE: `inputs` must be a static attrset literal -- modern Nix rejects
  # thunks (e.g. a `let ... in { ... }` wrapper) here. nixpkgs/nix-darwin/
  # home-manager track unstable/master rather than a release line, so that
  # inputs which themselves target nixpkgs-unstable (zen-browser, zed,
  # nix-zed-extensions) keep evaluating against our pin. To go back to a
  # release line, move all three below in lock-step (`nixos-XX.YY`,
  # `nix-darwin-XX.YY`, `release-XX.YY`).
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Kept as its own input so `modules/ai.nix` / `modules/zed.nix` keep
    # working unchanged; now resolves to the same rev as `nixpkgs` above.
    nixpkgsunstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/master";

    prismLauncher.url = "github:HannesGitH/prismlauncherc";
    nix-search-cli.url = "github:peterldowns/nix-search-cli";
    mergiraf.url = "git+https://codeberg.org/HannesGitH/mergiraf";

    frosted.url = "github:HannesGitH/frosted";

    # secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    zen-browser = {
      # Needs a nixpkgs with `ffmpeg_9` (zen-browser-flake#381), i.e. unstable
      # -- release lines up to 26.05 only carry `ffmpeg_8`. An overlay can't
      # paper that over: zen builds its packages from its own
      # `nixpkgs.legacyPackages`, which never sees `nixpkgs.overlays` from
      # this config, so the `follows` below has to point at unstable.
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    zed.url = "github:zed-industries/zed";

    # Declarative, source-built Zed extensions (grammars + wasm). Consumed
    # by modules/zed.nix to install the sebb3 Nix-extension fork (runnable
    # flake tasks + comment-based language injection) with its
    # tree-sitter-nix grammar pinned to the injection-comment PR.
    nix-zed-extensions.url = "github:DuskSystems/nix-zed-extensions";
    nix-zed-extensions.inputs.nixpkgs.follows = "nixpkgs";

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
          { ... }:
          {
            # inherit nixpkgs;
            # `home-manager` config
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Move pre-existing dotfiles aside (e.g. Zen's profiles.ini) instead
            # of aborting activation. Backups land next to the originals as
            # `<name>.hm-backup` so they're recoverable if anything was lost.
            home-manager.backupFileExtension = "hm-backup";
            # `backupFileExtension` on its own is single-shot: the second time
            # the same path needs backing up, home-manager refuses to clobber
            # the existing `<name>.hm-backup` and aborts activation with
            # "Existing file ... would be clobbered by backing up ...".
            # Zed's registry-installed extensions trip this on every upgrade.
            # Keep only the most recent backup rather than failing the switch.
            home-manager.overwriteBackup = true;
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
        ./modules/remote-builder.nix
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
              home-manager.users."blingmember" = {
                imports = [
                  ./specifics/hannes/home.nix
                  # Backend-role Zed config (vtsls). maccaroni is a backend
                  # dev box; pairs with ./specifics/backend/config.nix below.
                  ./specifics/backend/home.nix
                ];

                # SSH remote scoped to this host (maccaroni) only -- layered
                # into Zed's userSettings via extraSettings (modules/zed.nix).
                myModules.zed.extraSettings.ssh_connections = [
                  {
                    host = "zuhause.h-h.win";
                    username = "hannes";
                    args = [ ];
                    projects = [
                      { paths = [ "/home/hannes" ]; }
                      { paths = [ "/home/hannes/nix_config" ]; }
                    ];
                  }
                ];
              };
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
              home-manager.users."blingmember" = {
                # Ride upstream Zed releases directly (via the `zed` flake
                # input) instead of nixpkgs' `unstable` package, matching
                # maccaroni.
                myModules.zed.channel = "nightly";
              };
            }
          ];
        };
      };

      # sudo ln -s /Users/blingmember/Repos/nix-darwin-config/scripts/com.bling.wasyle.plist /Library/LaunchDaemons/com.bling.wasyle.plist
      # sudo launchctl load /Library/LaunchDaemons/com.bling.wasyle.plist
    };
}
