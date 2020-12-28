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
	bash .bin/init.sh

deploy:
	@echo '==> Start to deploy dotfiles to home directory.'
	@echo ''
	bash .bin/deploy.sh

update:
	git pull origin master
	git submodule init
	git submodule update
	git submodule foreach git pull origin master

# Use for Docker test

build:
	@docker build -t arch .

run:
	@docker run -itd --cpu-shares=4096 -m 16G --name arch arch:latest

start:
	@docker start arch

exec:
	@docker exec -it arch bash 

stop:
	docker stop arch

remove:
	make stop
	@docker rm arch

backup:
	sudo pacman -Qqe > .backup/pacman/pkglist.txt
