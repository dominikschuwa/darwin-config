# Remote Nix builder access for trusted colleagues.
#
# Exposes this Mac as a remote build machine over SSH without handing any
# colleague an interactive shell or access to anything beyond the Nix
# store-serve protocol. Two independent lockdown layers keep this safe
# even when the config is redeployed onto another machine:
#
#   1. authorized_keys: every colleague key is prefixed with
#      `command="nix-store --serve --write",restrict`, so the key itself
#      can only ever speak the store-serve protocol (no pty, no
#      forwarding, no arbitrary command).
#   2. sshd ForceCommand: a `Match User` block forces the very same
#      command for the whole account, independent of authorized_keys.
#
# Colleagues CAN build derivations this machine has never seen: their
# build inputs are copied in, realised by this machine's nix-daemon, and
# the outputs copied back. That is exactly what `--write` plus being a
# trusted-user enables.
#
# NOTE: builds run via the system nix-daemon. This config sets
# `sandbox = false` (global/config.nix), so remote builds are NOT
# sandboxed -- only expose this to people you trust to run code here.
#
# Manual one-time steps after `darwin-rebuild switch` (Remote Login is
# not manageable declaratively on darwin):
#   * Enable SSH:   sudo systemsetup -setremotelogin on
#   * If Remote Login is scoped to specific users in System Settings ->
#     General -> Sharing -> Remote Login, add the builder account too.
{ config, lib, ... }:
let
  cfg = config.myModules.remoteBuilder;
  # Absolute path so it works regardless of the connecting user's PATH.
  serveCmd = "${config.nix.package}/bin/nix-store --serve --write";
in
{
  options.myModules.remoteBuilder = {
    enable = lib.mkEnableOption "remote Nix builder access for trusted colleagues";

    user = lib.mkOption {
      type = lib.types.str;
      default = "nixremote";
      description = "Dedicated, unprivileged account that accepts remote builds.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 2001;
      description = "Stable UID for the builder account (pick a free value).";
    };

    colleagueKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ dominik = "ssh-ed25519 AAAA... dominik"; }'';
      description = ''
        SSH *public* keys allowed to offload builds, keyed by a human
        label. Each value is a full `ssh-ed25519 ...` line.

        These must be supplied directly: they are the keys the matching
        age identities in `.sops.yaml` were derived from via
        `ssh-to-age`, but that conversion is one-way -- the SSH form
        cannot be recovered from an age key.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Dedicated, unprivileged account. It needs a *real* login shell:
    # sshd runs both the ForceCommand and the per-key forced command via
    # `shell -c <cmd>`, and a nologin shell would refuse and break remote
    # builds. Shell access is neutralised by ForceCommand + `restrict`
    # below, not by the choice of shell.
    users.knownUsers = [ cfg.user ];
    users.users.${cfg.user} = {
      uid = cfg.uid;
      gid = 20; # staff -- the default macOS primary group
      home = "/Users/${cfg.user}";
      createHome = true;
      isHidden = true; # keep it out of the macOS login window
      shell = "/bin/zsh";
      ignoreShellProgramCheck = true;
      description = "Nix remote builder";

      # Per-key lockdown (layer 1).
      openssh.authorizedKeys.keys = lib.mapAttrsToList (
        _label: key: ''command="${serveCmd}",restrict ${key}''
      ) cfg.colleagueKeys;
    };

    # Let the builder account add/copy store paths through the daemon.
    # This is what allows colleagues to realise derivations this machine
    # has never built. Lists merge (concatenate) across modules, so this
    # adds to -- it does not replace -- the existing trusted-users.
    nix.settings.trusted-users = [ cfg.user ];

    # sshd-level lockdown (layer 2). Enforced for the whole account
    # regardless of authorized_keys. Picked up via the
    # `Include /etc/ssh/sshd_config.d/*` already present in macOS
    # sshd_config.
    environment.etc."ssh/sshd_config.d/200-${cfg.user}.conf".text = ''
      Match User ${cfg.user}
        ForceCommand ${serveCmd}
        PermitTTY no
        AllowTcpForwarding no
        AllowAgentForwarding no
        X11Forwarding no
        PermitTunnel no
    '';
  };
}
