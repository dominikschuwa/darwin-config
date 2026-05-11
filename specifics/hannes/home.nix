{ config, pkgs, ... }:

{
    programs.git = {
      settings = {
        user.name = "Hannes";
        user.email = "github@h-h.win";
        commit.gpgsign = true;
        user.signingkey = "792D2673D758C914A2293714355878B8CF2515D1";
      };
    };

    # Declarative GPG public-key + ownertrust management. The public key
    # itself is not secret so it lives unencrypted in the repo; the
    # matching private key is dropped in by sops-nix and imported by the
    # postActivation hook in specifics/hannes/config.nix.
    #
    # `mutableKeys = false` and `mutableTrust = false` make home-manager
    # overwrite pubring.kbx / trustdb.gpg on activation, so any ad-hoc
    # `gpg --import`s you do outside of this config will not survive a
    # rebuild -- intentional, keeps the keyring reproducible.
    programs.gpg = {
      enable = true;
      mutableKeys = false;
      mutableTrust = false;
      publicKeys = [{
        source = ../../secrets/hannes/gpg.pub.asc;
        trust = "ultimate";
      }];
    };
}