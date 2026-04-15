{ config, pkgs, ... }:
let
  mod = "alt"; 
  
  # --- COLORS (Catppuccin Mocha) ---
  colors = {
    bg       = "0xff1e1e2e";
    fg       = "0xffcdd6f4";
    accent   = "0xff89b4fa"; # Blue
    green    = "0xffa6e3a1";
    red      = "0xfff38ba8";
    yellow   = "0xfff9e2af";
    surface  = "0xff313244";
    item_bg  = "0xff45475a";
  };

  # --- ICONS (Nerd Font) ---
  icons = {
    apple    = "";
    calendar = "󰃭";
    clock    = "";
    volume   = "";
    wifi     = "";
    battery  = "";
  };

  # --- SCRIPTS (Plugins) ---
  
  aerospacePlugin = pkgs.writeShellScript "sketchybar-aerospace" ''
    FOCUSED_WORKSPACE=$(${pkgs.aerospace}/bin/aerospace list-workspaces --focused)
    
    if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
        ${pkgs.sketchybar}/bin/sketchybar --set $NAME background.drawing=on background.color=${colors.accent} label.color=${colors.bg}
    else
        ${pkgs.sketchybar}/bin/sketchybar --set $NAME background.drawing=off label.color=${colors.fg}
    fi
  '';
    # 2. Volume (Mit Mute-Logic)
  pluginVolume = pkgs.writeShellScript "sketchybar-volume" ''
    VOL=$(/usr/bin/osascript -e 'output volume of (get volume settings)')
    MUTED=$(/usr/bin/osascript -e 'output muted of (get volume settings)')
    
    ICON="${icons.volume}"
    if [ "$MUTED" = "true" ]; then ICON="󰝟"; fi
    
    ${pkgs.sketchybar}/bin/sketchybar --set $NAME icon="$ICON" label="$VOL%"
  '';

  # 3. Battery
  pluginBattery = pkgs.writeShellScript "sketchybar-battery" ''
    # 1. Info holen
    BATT_INFO=$(/usr/bin/pmset -g batt)
    
    PERCENT=$(echo "$BATT_INFO" | /usr/bin/grep -Eo "[0-9]+%" | /usr/bin/cut -d% -f1)
    
    CHARGING=$(echo "$BATT_INFO" | /usr/bin/grep 'AC Power')

    if [ "$PERCENT" = "" ]; then PERCENT="?"; fi

    ICON="${icons.battery}"
    COLOR=${colors.fg}
    
    if [ -n "$CHARGING" ]; then 
        ICON=""
        COLOR=${colors.green}
    elif [ "$PERCENT" != "?" ] && [ "$PERCENT" -lt 20 ]; then
        COLOR=${colors.red}
    fi

    # Update SketchyBar
    ${pkgs.sketchybar}/bin/sketchybar --set $NAME icon="$ICON" label="$PERCENT%" icon.color=$COLOR
  '';

  # 4. Clock
  pluginClock = pkgs.writeShellScript "sketchybar-clock" ''
    ${pkgs.sketchybar}/bin/sketchybar --set $NAME label="$(date '+%H:%M')"
  '';
in
{
      xdg.configFile."sketchybar/sketchybarrc" = {
    executable = true;
    text = ''
      #!/bin/bash
      
      # Helper Variables
      SB="${pkgs.sketchybar}/bin/sketchybar"
      AEROSPACE="${pkgs.aerospace}/bin/aerospace"
      
      # --- GLOBAL DEFAULTS ---
      $SB --default \
          updates=on \
          drawing=on \
          icon.font="Hack Nerd Font:Bold:14.0" \
          icon.color=${colors.fg} \
          label.font="Hack Nerd Font:Bold:13.0" \
          label.color=${colors.fg} \
          label.padding_left=4 \
          label.padding_right=4 \
          icon.padding_left=4 \
          icon.padding_right=4 \
          background.height=28 \
          background.corner_radius=8 \
          popup.background.border_width=2 \
          popup.background.corner_radius=5 \
          popup.background.color=${colors.bg}

      # --- BAR SETUP ---
      $SB --bar \
          height=36 \
          color=${colors.bg} \
          position=top \
          sticky=on \
          padding_left=10 \
          padding_right=10 \
          notch_width=188 # M1/M2/M3 Notch Workaround

      # --- LEFT MODULES (Workspaces) ---
      $SB --add event aerospace_workspace_change
      
      for sid in $($AEROSPACE list-workspaces --all); do
          $SB --add item space.$sid left \
              --subscribe space.$sid aerospace_workspace_change \
              --set space.$sid \
              label="$sid" \
              background.color=${colors.surface} \
              background.drawing=off \
              click_script="$AEROSPACE workspace $sid" \
              script="${aerospacePlugin} $sid"
      done

      # --- RIGHT MODULES ---
      
      # 1. Volume
      $SB --add item volume right \
          --subscribe volume volume_change \
          --set volume \
          script="${pluginVolume}" \
          background.color=${colors.item_bg} \
          background.drawing=on \
          label.width=40 \
          background.padding_left=10 \
          updates=on # Polling für Erst-Init

      # 2. Battery
      $SB --add item battery right \
          --set battery \
          update_freq=120 \
          script="${pluginBattery}" \
          background.color=${colors.item_bg} \
          background.drawing=on \
          background.padding_left=10 \
          background.padding_right=10

      # 3. Calendar (Date)
      $SB --add item date right \
          --set date \
          update_freq=60 \
          icon="${icons.calendar}" \
          label="$(date '+%a %d. %b')" \
          background.color=${colors.surface} \
          background.drawing=on \
          background.padding_left=10 \
          background.padding_right=10

      $SB --add item clock right \
          --set clock \
          update_freq=10 \
          icon="${icons.clock}" \
          script="${pluginClock}" \
          background.color=${colors.surface} \
          background.drawing=on \
          background.padding_left=10 \
          background.padding_right=10

      # --- BRACKETS (Optische Gruppierung rechts) ---
      # Macht das Ganze visuell zusammenhängend ("Pill"-Look)
      $SB --add bracket status volume battery date clock \
          --set status background.color=${colors.surface} \
                       background.border_color=${colors.bg} \
                       background.border_width=2 \
                       background.height=34

      # --- FINALIZE ---
      $SB --update
    '';
  };

    programs.git = {
      userName = "dominikschuwa";
      userEmail = "dominik.schulze.waltrup@bling.de";

       extraConfig = {
        commit.gpgsign = true;
        user.signingkey = "935FE616171A2DE2AAC7271E169962694C012151";
       };
    };

      xdg.configFile."aerospace/aerospace.toml".text = ''
    # Generated via Nix Home Manager
    
    # -----------------------------------------------------------------------------
    # BASIC SETTINGS
    # -----------------------------------------------------------------------------
    enable-normalization-flatten-containers = true
    enable-normalization-opposite-orientation-for-nested-containers = true
    

    default-root-container-layout = 'tiles'
    default-root-container-orientation = 'auto'

    exec-on-workspace-change = ['/bin/bash', '-c', '${pkgs.sketchybar}/bin/sketchybar --trigger aerospace_workspace_change']
    
    # Auto-Start
    after-startup-command = ['exec-and-forget ${pkgs.sketchybar}/bin/sketchybar']
    
    # -----------------------------------------------------------------------------
    # KEY BINDINGS (${mod} mapped)
    # -----------------------------------------------------------------------------
    [mode.main.binding]

    # Apps
    ${mod}-q = 'close'
    ${mod}-d = 'exec-and-forget open -a Raycast'
    
    # Layout
    ${mod}-v = 'layout floating tiling'
    
    # Focus (Vim Style)
    ${mod}-h = 'focus left'
    ${mod}-n = 'focus down'
    ${mod}-e = 'focus up'
    ${mod}-i = 'focus right'
    
    # Move
    ${mod}-shift-h = 'move left'
    ${mod}-shift-n = 'move down'
    ${mod}-shift-e = 'move up'
    ${mod}-shift-i = 'move right'
    
    # Workspaces (switch with numbers)
    ${mod}-1 = 'workspace 1'
    ${mod}-keypad1 = 'workspace 1'
    ${mod}-2 = 'workspace 2'
    ${mod}-keypad2 = 'workspace 2'
    ${mod}-3 = 'workspace 3'
    ${mod}-keypad3 = 'workspace 3'
    ${mod}-4 = 'workspace 4'
    ${mod}-keypad4 = 'workspace 4'
    ${mod}-keypad5 = 'workspace 5'
    ${mod}-5 = 'workspace 5'
    ${mod}-keypad6 = 'workspace 6'
    ${mod}-6 = 'workspace 6'

    # Move node to workspace (QWERTZ row)
    ${mod}-shift-1 = 'move-node-to-workspace 1'
    ${mod}-shift-keypad1 = 'move-node-to-workspace 1'
    ${mod}-shift-2 = 'move-node-to-workspace 2'
    ${mod}-shift-keypad2 = 'move-node-to-workspace 2'
    ${mod}-shift-3 = 'move-node-to-workspace 3'
    ${mod}-shift-keypad3 = 'move-node-to-workspace 3'
    ${mod}-shift-4 = 'move-node-to-workspace 4'
    ${mod}-shift-keypad4 = 'move-node-to-workspace 4'
    ${mod}-shift-5 = 'move-node-to-workspace 5'
    ${mod}-shift-keypad5 = 'move-node-to-workspace 5'
    ${mod}-shift-6 = 'move-node-to-workspace 6'
    ${mod}-shift-keypad6 = 'move-node-to-workspace 6'

    [gaps]
    inner.horizontal = 5
    inner.vertical   = 5
    outer.left       = 5
    outer.bottom     = 5
    outer.top        = [{ monitor.main = 36  },  {  monitor."LG HDR WQHD (1)" = 36 }, { monitor."LG HDR WQHD (2)" = 36 }, 36]
    outer.right      = 5
    
    # Monitor Assignment (Regex!)
    [workspace-to-monitor-force-assignment]
    
    1 = ['LG HDR WQHD \(1\)', 'DELL.*21D']
    2 = ['LG HDR WQHD \(2\)', 'VX.*-QHD']
    3 = ['^Built-in.*', 'LG HDR WQHD \(1\)']
    4 = ['LG HDR WQHD \(2\)', 'DELL.*21D']
    5 = ['VX.*-QHD']
    6 = ['^Built-in.*']
  '';
}