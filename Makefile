PROVIDER ?= local
MODE ?= install
PROJECT=reversi
MO_SRC:=src/$(PROJECT)/main.mo src/$(PROJECT)/game.mo
JS_SRC:=src/$(PROJECT)_assets/public/index.js src/$(PROJECT)_assets/public/style.css src/$(PROJECT)_assets/public/logo.png
JS_CFG:=package-lock.json webpack.config.js
DFX_CFG:=dfx.json

OBJ_DIR:=.dfx/$(PROVIDER)/canisters

CANISTER_IDS:=.dfx/$(PROVIDER)/canister_ids.json
CANISTER_TARGET:=$(OBJ_DIR)/$(PROJECT)/$(PROJECT).wasm
ASSETS_TARGET:=$(OBJ_DIR)/$(PROJECT)_assets/$(PROJECT)_assets.wasm
JS_TARGET:=$(OBJ_DIR)/$(PROJECT)_assets/assets/index.js

help:
	@echo 'USAGE: make [PROVIDER=...] [install|reinstall|upgrade|clean|canister|assets]'
	@echo
	@echo 'Build & install instructions:'
	@echo
	@echo '  install|reinstall|upgrade -- Build and install canisters with different mode.'
	@echo '  clean                     -- Remove build products.'
	@echo '  canister                  -- Only build the main canister'
	@echo '  assets                    -- Build both the main and assets canisters.'
	@echo 
	@echo 'The PROVIDER variable is optional. It corresponds to "networks" configuration in'
	@echo 'the dfx.json file. The default is "local".'

.PHONY: help

canister: $(CANISTER_TARGET)

assets: $(ASSETS_TARGET)

.PHONY: reinstall install install-canister install-assets

install-canister: $(CANISTER_IDS) $(CANISTER_TARGET) $(DFX_CFG)
	dfx canister --network $(PROVIDER) install --mode $(MODE) $(PROJECT)

install-assets: $(JS_TARGET) $(ASSETS_TARGET) $(DFX_CFG)
	dfx canister --network $(PROVIDER) install --mode $(MODE) $(PROJECT)_assets

install: install-assets install-canister

reinstall:
	$(MAKE) MODE=reinstall install

.PHONY: upgrade upgrade-canister upgrade-assets

upgrade:
	$(MAKE) MODE=upgrade install

upgrade-canister:
	$(MAKE) MODE=upgrade install-canister

upgrade-assets:
	$(MAKE) MODE=upgrade install-assets

.PHONY: clean clean-npm clean-state clean-all

clean: 
	rm -rf .dfx/$(PROVIDER)

clean-npm:
	rm -rf node_modules package-lock.json

clean-state:
	rm -rf .dfx/state

cleanall: clean clean-state clean-npm

######################

node_modules package-lock.json : package.json
	npm install

$(CANISTER_IDS): $(DFX_CFG)
	dfx canister --network $(PROVIDER) create --all

$(CANISTER_TARGET): $(CANISTER_IDS) $(MO_SRC) $(DFX_CFG)
	dfx build --network $(PROVIDER) --skip-frontend

$(ASSETS_TARGET) $(JS_TARGET) : $(CANISTER_IDS) $(MO_SRC) $(JS_SRC) $(JS_CFG) $(DFX_CFG) node_modules
	dfx build --network $(PROVIDER)
