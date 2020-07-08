PROVIDER ?= local
MODE ?= install
PROJECT=reversi
MO_SRC:=src/$(PROJECT)/main.mo src/$(PROJECT)/game.mo
JS_SRC:=src/$(PROJECT)_assets/public/index.js src/$(PROJECT)_assets/public/style.css
JS_CFG:=package-lock.json webpack.config.js
DFX_CFG:=dfx.json

OBJ_DIR:=canisters.$(PROVIDER)

CANISTER_TARGET:=$(OBJ_DIR)/$(PROJECT)/main.wasm
ASSETS_TARGET:=$(OBJ_DIR)/$(PROJECT)_assets/$(PROJECT)_assets.wasm
JS_TARGET:=$(OBJ_DIR)/$(PROJECT)_assets/assets/index.js
MANIFEST:=$(OBJ_DIR)/canister_manifest.json

# all: $(CANISTER_TARGET) $(JS_TARGET) $(ASSETS_TARGET) node_modules
help:
	@echo 'USAGE: make [PROVIDER=...] [install|reinstall|upgrade|clean|canister|assets]'
	@echo
	@echo 'Build & install instructions:'
	@echo
	@echo '  install|reinstall|upgrade -- Build and install canisters with different mode.'
	@echo '  clean                     -- Remove build products.'
	@echo '  canister                  -- Only build the main canister'
	@echo '  assets                    -- Build both the main and assets canister.'
	@echo 
	@echo 'The PROVIDER variable is optional. It corresponds to "networks" configuration in'
	@echo 'the dfx.json file. Default is "local".'

.PHONY: help all canisters

canisters.$(PROVIDER):
	mkdir canisters.$(PROVIDER)

canisters: canisters.$(PROVIDER)
	test $$(readlink canisters) = canisters.$(PROVIDER) || $$(rm -f canisters && ln -s canisters.$(PROVIDER) canisters)

.PHONY: canister assets

canister: $(CANISTER_TARGET)

assets: $(ASSETS_TARGET)

.PHONY: reinstall install install-canister install-assets

install-canister: $(MANIFEST) $(CANISTER_TARGET) $(DFX_CFG) canisters
	dfx canister --network $(PROVIDER) install --mode $(MODE) $(PROJECT)

install-assets: $(JS_TARGET) $(ASSETS_TARGET) $(DFX_CFG) canisters
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

.PHONY: clean clean-state clean-all

clean: 
	rm -rf $(OBJ_DIR)

clean-state:
	rm -rf .dfx

cleanall: clean clean-state

######################

node_modules package-lock.json : package.json
	npm install

$(MANIFEST): $(DFX_CFG) canisters
	dfx canister --network $(PROVIDER) create --all

$(CANISTER_TARGET): $(MANIFEST) $(MO_SRC) $(DFX_CFG)
	dfx build --network $(PROVIDER) --skip-frontend --skip-manifest

$(ASSETS_TARGET) $(JS_TARGET) : $(MANIFEST) $(MO_SRC) $(JS_SRC) $(JS_CFG) $(DFX_CFG) node_modules
	dfx build --network $(PROVIDER)
