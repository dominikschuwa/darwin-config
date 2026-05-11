{ pkgs, config, lib, inputs, ... }: {

  environment.systemPackages = with pkgs; [
    nodejs #22
  ];

  homebrew = {
    enable = true;
    casks = [
      "ngrok"
    ];
  };
}