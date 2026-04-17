.PHONY: build install test clean

build:
	bash scripts/build-release.sh

install: build
	cargo install --path ccsplit-logger
	cp -R dist/ccsplit-app.app /Applications/
	ccsplit-logger install
	@echo "ccsplit installed. Launch ccsplit-app from /Applications or reboot."

test:
	cargo test -p ccsplit-logger
	cargo clippy -p ccsplit-logger
	xcodegen generate --spec ccsplit-app/project.yml --project ccsplit-app/
	xcodebuild -project ccsplit-app/ccsplit-app.xcodeproj -scheme ccsplit-appTests -configuration Debug test

clean:
	cargo clean
	rm -rf build dist
