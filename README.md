# dotfiles

![Actions Status](https://github.com/music-brain88/dotfiles/workflows/build/badge.svg)

## Overview


This repository contains my personal dotfiles - a collection of configuration files and scripts for setting up a powerful development environment. It focuses on creating a highly customized and efficient workspace primarily using Neovim, Tmux, and Fish shell, along with various other tools and utilities.

```shell
# Directory Structure
dotfiles/
├── .bin/
│   ├── deploy.sh
│   ├── install.sh
│   └── utils/
│       ├── manage_cargo_tools.sh
│       ├── setup_neovim.sh
│       ├── setup_fish.sh
│       └── setup_tmux.sh
├── .config/
│   ├── alacritty/
│   ├── fish/
│   ├── i3/
│   ├── mpd/
│   ├── ncmpcpp/
│   ├── nvim/
│   │   └── status_line/
│   ├── polybar/
│   │   └── forest/
│   ├── rofi/
│   └── starship/
├── .github/
├── polybar-themes/
├── .bash_aliases
├── .bashrc
├── .gitconfig
├── .gitconfig.local.sample
├── .gitignore
├── .gitmodules
├── .tmux.conf
├── Dockerfile
├── LICENSE
├── Makefile
├── README.md
└── fish_plugin_setup.fish
```
## Directory Structure Explanation

.bin/: Contains main scripts and utility scripts

deploy.sh: Handles symlinking of dotfiles
install.sh: Main installation script
utils/: Directory for utility scripts

manage_cargo_tools.sh: Manages Cargo tools
setup_neovim.sh: Sets up Neovim
setup_fish.sh: Sets up Fish shell
setup_tmux.sh: Sets up Tmux




configs/: Contains configuration files for various tools

nvim/: Neovim configuration
fish/: Fish shell configuration
tmux/: Tmux configuration
... (other tool configurations)


Makefile: Defines tasks for easy execution
README.md: Project documentation

## Makefile Tasks
```makefile
.PHONY: all install deploy update-tools

all: install deploy

install:
	@echo "Installing dotfiles..."

	@.bin/install.sh


deploy:
	@echo "Deploying dotfiles..."

	@.bin/deploy.sh

update-tools:

	@echo "Updating Cargo tools..."

	@.bin/utils/manage_cargo_tools.sh


setup-neovim:
	@echo "Setting up Neovim..."
	@.bin/utils/setup_neovim.sh

setup-fish:
	@echo "Setting up Fish shell..."
	@.bin/utils/setup_fish.sh

setup-tmux:
	@echo "Setting up Tmux..."
	@.bin/utils/setup_tmux.sh

```

## Key Features

- **Neovim Configuration**: Advanced setup with Dein plugin manager and LSP integration
- **Tmux**: Custom configuration for enhanced terminal multiplexing

- **Fish Shell**: Configured with Fisher package manager and custom functions
- **Window Manager**: i3 setup with Polybar, Rofi, and Picom for a customized desktop experience
- **Terminal**: Alacritty configuration for a modern terminal experience

- **Development Tools**: Integration of various Rust-based CLI tools (fd, ripgrep, exa, etc.)
- **Version Control**: Git setup with Delta for improved diffs

- **Package Managers**: Utilizes Cargo, Fisher, Dein, and others for managing various components
- **Automated Setup**: Makefile and scripts for easy deployment and environment setup

## Installation

**Warning**: If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don't want or need. Don't blindly use my settings unless you know what that entails. Use at your own risk!


### Prerequisites


- [Neovim](https://github.com/neovim/neovim/wiki/Installing-Neovim)
- [Tmux](https://github.com/tmux/tmux)
- [Fish](https://fishshell.com/)
- Make
- GCC

- pkg-config

### Setup Steps

1. Clone the repository:
   ```shell
   git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
   ```

2. Navigate to the dotfiles directory:

   ```shell
   cd ~/dotfiles
   ```

3. Run the installation command:
   ```shell
   make install
   ```

4. Deploy the configurations:
   ```shell
   make deploy

   ```

5. Set up Python environment (if needed):
   ```shell
   pyenv install <python3 version>
   pyenv virtualenv <python3 version> neovim3
   source ~/.pyenv/versions/neovim3/bin/activate.fish
   ```

6. Install pynvim:

   ```shell
   pip install pynvim
   ```

7. Open Neovim and install plugins:
   ```
   :call dein#install()
   ```

## Included Tools and Utilities


- Rust-based CLI tools:
  - [bat](https://github.com/sharkdp/bat)
  - [exa](https://github.com/ogham/exa)
  - [procs](https://github.com/dalance/procs)
  - [fd-find](https://github.com/sharkdp/fd)

  - [gitui](https://github.com/extrawurst/gitui)
  - [git-delta](https://github.com/dandavison/delta)

  - [ripgrep](https://github.com/BurntSushi/ripgrep)
  - And more...

## Usage


To see available commands, run `make` in the dotfiles directory:


```shell
~/dotfiles make
```

This will display a list of available commands for managing your dotfiles and development environment.

## Customization


Feel free to fork this repository and modify the configurations to suit your needs. The modular structure allows for easy customization of individual components.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT](https://github.com/tcnksm/tool/blob/master/LICENCE)


## Author

[1saver](https://github.com/music-brain88/)
