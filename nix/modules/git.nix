{ config, pkgs, ... }:

{
  # Git configuration
  # Replaces setup_git.sh functionality
  programs.git = {
    enable = true;

    # User configuration (can be overridden by local .gitconfig)
    userName = "music-brain88";
    userEmail = "music-brain88@example.com"; # Update with actual email

    # Git aliases
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      cm = "commit -m";
      ca = "commit --amend";
      df = "diff";
      dc = "diff --cached";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      lol = "log --graph --decorate --pretty=oneline --abbrev-commit";
      lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "log --graph --all --decorate --oneline";
    };

    # Git extra configuration
    extraConfig = {
      core = {
        editor = "nvim";
        autocrlf = "input";
        safecrlf = true;
      };

      init = {
        defaultBranch = "main";
      };

      pull = {
        rebase = false;
      };

      push = {
        default = "simple";
        followTags = true;
      };

      merge = {
        conflictstyle = "diff3";
        tool = "vimdiff";
      };

      diff = {
        tool = "vimdiff";
        colorMoved = "default";
      };

      color = {
        ui = true;
        branch = "auto";
        diff = "auto";
        status = "auto";
      };

      credential = {
        helper = "cache --timeout=3600";
      };

      # GitHub Copilot CLI integration
      alias = {
        copilot-explain = "!gh copilot explain";
        copilot-suggest = "!gh copilot suggest";
      };
    };

    # Git ignore patterns
    ignores = [
      "*~"
      "*.swp"
      "*.swo"
      ".DS_Store"
      "Thumbs.db"
      ".idea/"
      ".vscode/"
      "*.log"
      "node_modules/"
      ".env"
      ".env.local"
    ];
  };

  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
      prompt = "enabled";
      pager = "less";
    };

    # GitHub Copilot CLI extension
    extensions = [
      pkgs.gh-copilot
    ];
  };

  # Additional Git tools
  home.packages = with pkgs; [
    git-lfs
    delta # Better diff viewer
    gh-dash # GitHub dashboard
  ];

  # Delta configuration (better git diff)
  programs.git.delta = {
    enable = true;
    options = {
      navigate = true;
      light = false;
      line-numbers = true;
      side-by-side = false;
    };
  };
}
