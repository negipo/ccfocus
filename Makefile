.PHONY: build install test clean dev-install-logger dev-uninstall-logger

build:
	bash scripts/build-release.sh

install: build
	cargo install --path ccfocus-logger
	mise reshim
	cp -R dist/ccfocus.app /Applications/
	ccfocus-logger install
	@echo "ccfocus installed. Launch ccfocus from /Applications or reboot."

dev-install-logger:
	cargo install --path ccfocus-logger --force
	mise reshim
	@echo "dev ccfocus-logger installed via mise shim. Run 'make dev-uninstall-logger' to revert."

dev-uninstall-logger:
	cargo uninstall ccfocus-logger
	mise reshim
	@echo "dev ccfocus-logger removed. PATH now resolves to the release symlink again."

test:
	cargo test -p ccfocus-logger
	cargo clippy -p ccfocus-logger
	xcodegen generate --spec ccfocus/project.yml --project ccfocus/
	xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test

clean:
	cargo clean
	rm -rf build dist
