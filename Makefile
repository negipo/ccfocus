.PHONY: build install test clean

build:
	bash scripts/build-release.sh

install: build
	cargo install --path ccfocus-logger
	mise reshim
	cp -R dist/ccfocus.app /Applications/
	ccfocus-logger install
	@echo "ccfocus installed. Launch ccfocus from /Applications or reboot."

test:
	cargo test -p ccfocus-logger
	cargo clippy -p ccfocus-logger
	xcodegen generate --spec ccfocus/project.yml --project ccfocus/
	xcodebuild -project ccfocus/ccfocus.xcodeproj -scheme ccfocusTests -configuration Debug test

clean:
	cargo clean
	rm -rf build dist
