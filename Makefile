MODE ?= install
PROJECT=reversi
MO_SRC:=src/$(PROJECT)/main.mo
JS_SRC:=src/$(PROJECT)_assets/public/index.js src/$(PROJECT)_assets/public/style.css
JS_CFG:=package-lock.json webpack.config.js
DFX_CFG:=dfx.json

CANISTER_TARGET:=canisters/$(PROJECT)/main.wasm
ASSETS_TARGET:=canisters/$(PROJECT)_assets/$(PROJECT)_assets.wasm
JS_TARGET:=canisters/$(PROJECT)_assets/assets/index.js
MANIFEST:=canisters/canister_manifest.json


all: $(CANISTER_TARGET) $(JS_TARGET) $(ASSETS_TARGET) node_modules

.PHONY: all

node_modules package-lock.json : package.json
	npm install

$(MANIFEST): $(DFX_CFG)
	dfx canister create --all

$(CANISTER_TARGET): $(MANIFEST) $(MO_SRC) $(DFX_CFG)
	dfx build --skip-frontend --skip-manifest

$(ASSETS_TARGET) $(JS_TARGET) : $(MANIFEST) $(MO_SRC) $(JS_SRC) $(JS_CFG) $(DFX_CFG) node_modules
	dfx build --skip-manifest

.PHONY: reinstall install install-canister install-assets

install-canister: $(MANIFEST) $(CANISTER_TARGET) $(DFX_CFG)
	dfx canister install --mode $(MODE) $(PROJECT)

install-assets: $(JS_TARGET) $(ASSETS_TARGET) $(DFX_CFG)
	dfx canister install --mode $(MODE) $(PROJECT)_assets

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
	rm -rf canisters

clean-state:
	rm -rf .dfx

cleanall: clean clean-state
