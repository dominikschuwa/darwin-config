{ pkgs, config,inputs,... }: {

  nixpkgs.overlays = [ inputs.prismLauncher.overlays.default ];

  environment.systemPackages = with pkgs; [
    prismlauncher
    openscad
  ];

  sops.secrets = {
    "gpg.key" = {
      format = "binary";
      sopsFile = ../../secrets/hannes/gpg.key;
      owner = "blingmember";
      mode = "0400";
      path = "/Users/blingmember/.gnupg/private-keys-v1.d/B36A4C516860D789671E2010E8A907F623EB6C32.key";
    };
  };

  homebrew = {
    enable = true;
    casks = [
      "displaylink"
    ];
  };

  # launchd.daemons."frosted-repos" =  let dir_to_watch = "/Users/blingmember/Repos/"; in {
  #   command = "${inputs.frosted.packages.${pkgs.system}.default}/bin/frosted -d ${dir_to_watch} -i 'localization.dart'";
  #   serviceConfig = {
  #     RunAtLoad = true;
  #     KeepAlive = true;
  #     StandardErrorPath = "/Users/blingmember/frosted-repos.log";
  #     StandardOutPath = "/Users/blingmember/frosted-repos.log";
  #   };
  # };
}