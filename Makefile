# Bobber build helpers. `make help` lists the targets.
#
# The checks run under Neovim's built-in LuaJIT (`nvim -l`), which speaks
# Lua 5.1 like the game. Override with `make check LUA=luajit` if you have
# a standalone LuaJIT or Lua 5.1.

SHELL := /bin/bash
ADDON := Bobber
VERSION := $(shell sed -n 's/^\#\# Version: *//p' Bobber.toc)
LUA ?= nvim -l

# Where `make install` copies the addon. Override for another install:
#   make install WOW_ADDONS="/path/to/_forever_/Interface/AddOns"
WOW_ADDONS ?= /mnt/internal_1tb/BottlesLibrary/wow/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns

# The files that ship: the TOC, the bindings, the license, and every Lua
# file the TOC lists.
LUA_FILES := $(shell sed -n 's/^\([A-Za-z0-9_]*\.lua\)$$/\1/p' Bobber.toc)
ADDON_FILES := Bobber.toc Bindings.xml LICENSE $(LUA_FILES)

.PHONY: help check static smoke install package hooks clean

help:
	@echo "make check    static checks and the smoke test"
	@echo "make install  check, then copy the addon into WOW_ADDONS"
	@echo "make package  check, then build dist/$(ADDON)-$(VERSION).zip for CurseForge"
	@echo "make hooks    run 'make check' before every git push"
	@echo "make clean    remove dist/"

check: static smoke

static:
	@$(LUA) tools/check.lua

smoke:
	@$(LUA) tools/smoke.lua

install: check
	rm -rf "$(WOW_ADDONS)/$(ADDON)"
	mkdir -p "$(WOW_ADDONS)/$(ADDON)"
	cp $(ADDON_FILES) "$(WOW_ADDONS)/$(ADDON)/"
	@echo "Installed $(ADDON) $(VERSION). Type /reload in game (new files need a full restart)."

package: check
	rm -rf dist/$(ADDON) dist/$(ADDON)-$(VERSION).zip
	mkdir -p dist/$(ADDON)
	cp $(ADDON_FILES) dist/$(ADDON)/
	cd dist && zip -qr $(ADDON)-$(VERSION).zip $(ADDON)
	@echo "Built dist/$(ADDON)-$(VERSION).zip"

hooks:
	git config core.hooksPath .githooks
	@echo "make check now runs before every push."

clean:
	rm -rf dist
