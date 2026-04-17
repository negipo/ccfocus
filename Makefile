.PHONY: build install test clean

build:
	bash scripts/build-release.sh

install: build
	cargo install --path ccfocus-logger
	cp -R dist/ccfocus-app.app /Applications/
	ccfocus-logger install
	@echo "ccfocus installed. Launch ccfocus-app from /Applications or reboot."

test:
	cargo test -p ccfocus-logger
	cargo clippy -p ccfocus-logger
	xcodegen generate --spec ccfocus-app/project.yml --project ccfocus-app/
	xcodebuild -project ccfocus-app/ccfocus-app.xcodeproj -scheme ccfocus-appTests -configuration Debug test

clean:
	cargo clean
	rm -rf build dist
