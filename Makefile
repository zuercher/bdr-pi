.SUFFIXES:

.PHONY: all
all:
	make docs/setup.sh imager.sh

.PHONY: clean
clean:
	rm docs/setup.sh imager.sh

docs/setup.sh: setup.sh.tmpl lib/*.sh build/apply-template.sh
	build/apply-template.sh setup.sh.tmpl docs/setup.sh
	chmod a+x docs/setup.sh

imager.sh: imager.sh.tmpl lib/*.sh build/apply-template.sh
	build/apply-template.sh imager.sh.tmpl imager.sh
	chmod a+x imager.sh
