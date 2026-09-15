{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    nodejs_26 # 26.5.0+
  ];

  homebrew = {
    enable = true;
    casks = [
      "ngrok"
    ];
  };
}
