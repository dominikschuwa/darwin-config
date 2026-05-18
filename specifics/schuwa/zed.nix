{
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  ...
}:
{
  programs.zed-editor = {
    enable = true;
    # This populates the userSettings "auto_install_extensions"
    extensions = [
      "nix"
      "toml"
      "dart"
      "ayu"
      "rust"
    ];

    package = inputs.nixpkgsunstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor;
    userKeymaps = [
      {
        context = "Workspace";
        bindings = {
          # "shift shift" = "file_finder::Toggle";
        };
      }
      {
        context = "Editor && vim_mode == insert";
        bindings = {
          # "j k" = "vim::NormalBefore";
        };
      }
      {
        context = "Workspace";
        unbind = {
          "shift shift" = "command_palette::Toggle";
        };
      }
      {
        context = "Workspace";
        bindings = {
          "shift shift" = "file_finder::Toggle";
        };
      }
      {
        context = "Workspace";
        unbind = {
          "cmd-shift-o" = "file_finder::Toggle";
        };
      }
      {
        bindings = {
          "f5" = "debugger::Start";
        };
      }
      {
        unbind = {
          "alt-shift-f9" = "debugger::Start";
        };
      }
      {
        bindings = {
          "cmd-k" = "edit_prediction::ToggleMenu";
        };
      }
    ];
    # Everything inside of these brackets are Zed options
    userSettings = {
      agent = {
        dock = "right";
        enabled = true;
        favorite_models = [
          {
            provider = "anthropic";
            model = "claude-opus-4-7-latest";
            enable_thinking = true;
            effort = "high";
          }
        ];
        default_model = {
          provider = "anthropic";
          model = "claude-opus-4-7-latest";
          enable_thinking = true;
          effort = "high";
        };
        model_parameters = [ ];
      };
      agent_servers = {
      };
      cli_default_open_behavior = "new_window";
      project_panel = {
        dock = "left";
      };
      outline_panel = {
        dock = "left";
      };
      collaboration_panel = {
        dock = "left";
      };
      git_panel = {
        tree_view = true;
        dock = "left";
      };
      edit_predictions = {
        provider = "zed";
        mode = "eager";
        ollama = {
          prompt_format = "zeta2";
          max_output_tokens = 90;
          model = "hf.co/bartowski/zed-industries_zeta-2-GGUF:Q4_K_M";
          api_url = "http://127.0.0.1:11434";
        };
      };
      icon_theme = {
        mode = "dark";
        light = "Zed (Default)";
        dark = "Zed (Default)";
      };
      tabs = {
        git_status = true;
        file_icons = true;
      };
      hour_format = "hour24";
      auto_update = false;
      terminal = {
        alternate_scroll = "off";
        blinking = "off";
        copy_on_select = false;
        env = {
          TERM = "xterm";
        };
        font_family = "FiraCode Nerd Font";
        font_features = null;
        font_size = null;
        line_height = "comfortable";
        option_as_meta = false;
        button = false;
        shell = "system";
        toolbar = {
          title = true;
        };
        working_directory = "current_project_directory";
      };
      lsp = {
        rust-analyzer = {
          binary = {
            path = lib.getExe pkgs.rust-analyzer;
          };
        };
        nixd = {
          binary = {
            path = lib.getExe pkgs.nixd;
          };
        };
        dart = {
          binary = {
            path = "fvm";
            arguments = [
              "dart"
              "language-server"
              "--protocol=lsp"
            ];
          };
        };
      };
      languages = {
      };
      vim_mode = false;
      # Tell Zed to use direnv and direnv can use a flake.nix environment
      load_direnv = "shell_hook";
      base_keymap = "JetBrains";
      theme = {
        mode = "dark";
        light = "Shades Of Purple";
        dark = "Shades Of Purple (Super Dark)";
      };
      semantic_tokens = "combined";
      global_lsp_settings = {
        semantic_token_rules = [
          {
            token_modifiers = [ "deprecated" ];
            strikethrough = true;
          }
        ];
      };
      colorize_brackets = true;
      indent_guides = {
        coloring = "indent_aware";
      };
      git = {
        inline_blame = {
          show_commit_summary = true;
        };
      };
      show_whitespaces = "all";
      ui_font_size = 16;
      buffer_font_size = 16;
      buffer_font_family = "FiraCode Nerd Font";
      buffer_font_features = {
        calt = true;
        liga = true;
      };
    };
  };
}
