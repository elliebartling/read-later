.PHONY: gen open test lint clean bootstrap

SCHEME ?= ReadLater
DESTINATION ?= platform=iOS Simulator,name=iPhone 17

bootstrap:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	@command -v swiftformat >/dev/null 2>&1 || echo "(optional) brew install swiftformat"

gen: bootstrap
	xcodegen generate

open: gen
	open ReadLater.xcodeproj

test: gen
	xcodebuild test \
		-project ReadLater.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		| xcbeautify || true

build: gen
	xcodebuild build \
		-project ReadLater.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		| xcbeautify || true

lint:
	swiftformat --lint . || true

format:
	swiftformat .

clean:
	rm -rf build DerivedData ReadLater.xcodeproj
