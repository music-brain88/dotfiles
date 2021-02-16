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
	@echo "build   => Build docker image."
	@echo "run     => run docker container"
	@echo "start   => start docker container."
	@echo "stop    => stop docker container."
	@echo "remove  => remove docker container."
	@echo "exec    => execute docker enviroment."
	@echo "backup  => export installed arch linux packages,this command for arch linux user"

init:
	bash .bin/init.sh

deploy:
	@echo '==> Start to deploy dotfiles to home directory.'
	@echo ''
	bash .bin/deploy.sh
	@echo '==> finish to deploy dotfiles'

update:
	git pull origin master
	git submodule init
	git submodule update
	git submodule foreach git pull origin master
	bash .bin/manage_cargo_tools.sh

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

# for arch linux user
backup:
	sudo pacman -Qne > .backup/pacman/pkglist.txt
