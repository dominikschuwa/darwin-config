{ pkgs, config, lib, inputs, ... }: {

  # Friendly name (AirDrop, Sharing), Bonjour, and Unix hostname
  networking = {
    computerName = "maccaroni";
    hostName = "maccaroni";
  };

  nixpkgs.overlays = [ inputs.prismLauncher.overlays.default ];

  environment.systemPackages = with pkgs; [
    # prismlauncher # just run nix run github:HannesGitH/prismlauncherc instead
  ];

  # Full ASCII-armored export of the GPG signing key (public + private in
  # one blob). Home-manager's `programs.gpg` handles the public-key side
  # declaratively (see specifics/hannes/home.nix); this secret covers only
  # the private material that can't live unencrypted in the repo.
  #
  # Importing via `gpg --import` lets GPG manage its own
  # ~/.gnupg/private-keys-v1.d/ layout instead of us hand-crafting files
  # there based on internal implementation details.
  sops.secrets."gpg.key.asc" = {
    format = "binary";
    sopsFile = ../../secrets/hannes/gpg.key.asc;
    owner = "blingmember";
    mode = "0400";
  };

  # nix-darwin 25.05 removed postUserActivation -- everything runs as root,
  # so we drop into the target user explicitly via `sudo -u`. mkAfter
  # ensures this runs after sops-nix has decrypted the secrets into
  # /run/secrets/ (sops-nix also appends to postActivation.text).
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "[gpg] importing signing key from sops secret" >&2
    gnupg_home=/Users/blingmember/.gnupg
    sudo -u blingmember install -d -m 700 "$gnupg_home"
    # `sudo -u` preserves root's HOME=/var/root, so gpg would try to
    # create /var/root/.gnupg. Pin the homedir explicitly instead.
    sudo -u blingmember ${pkgs.gnupg}/bin/gpg --homedir "$gnupg_home" \
      --batch --import "${config.sops.secrets."gpg.key.asc".path}" || true
  '';

  homebrew = {
    enable = true;
    casks = [
      # "displaylink"
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