DOTPATH    := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
CANDIDATES := $(wildcard .??*) bin
EXCLUSIONS := .DS_Store .git .gitmodules
DOTFILES   := $(filter-out $(EXCLUSIONS), $(CANDIDATES))

.DEFAULT_GOAL := help

help:
	@echo "init    => Initialize enviroment settings."
	@echo "deploy  => Create symlinks to home directory."
	@echo "update  => Fetch all changes from remote repo."
	@echo "install => Run update, deploy, init"
	@echo "clean   => remove the dotfiles"
	@echo "destroy => remove the dotfiles and this repo"

init:
	@DOTPAH=$(DOTPATH) bash $(DOTPATH)/etc/init/init.sh
