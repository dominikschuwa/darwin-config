{ config, pkgs, ... }:

{
    programs.git = {
      userName = "dominikschuwa";
      userEmail = "dominik.schulze.waltrup@blingcard.de";

      # extraConfig = {
      #   commit.gpgsign = true;
      #   user.signingkey = "418631D259CF0368999E14E35339BFCE9A05036C";
      # };
    };
}