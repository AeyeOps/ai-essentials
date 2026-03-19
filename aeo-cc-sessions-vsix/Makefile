.PHONY: validate package install clean ci ci-patch

validate:
	npm run check-types
	npx vsce ls

package: validate
	npx vsce package

install: package
	bash scripts/make_install.sh

ci:
	bash scripts/make_ci.sh

ci-patch:
	bash scripts/make_ci_patch.sh

clean:
	rm -rf dist/ out/ *.vsix
