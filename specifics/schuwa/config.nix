{ pkgs, config,inputs,... }: {
  homebrew = {
    enable = true;
    casks = [
      "nikitabobko/tap/aerospace"
      "font-hack-nerd-font"
      "eurkey"
      "claude-code"
    ];
    brews = [
      "fzf"
    ];
  };

  environment.systemPackages = [ pkgs.sketchybar ];
}