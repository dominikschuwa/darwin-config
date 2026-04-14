{ config, pkgs, ... }:

{
    programs.git = {
      userName = "Hannes";
      userEmail = "github@h-h.win";

      extraConfig = {
        commit.gpgsign = true;
        user.signingkey = "792D2673D758C914A2293714355878B8CF2515D1";
      };
    };
}