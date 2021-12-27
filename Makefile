.PHONY: all
all:
	make docs/setup.sh

.PHONY: clean
clean:
	rm docs/setup.sh

docs/setup.sh: setup.sh.tmpl lib/*.sh build/apply-template.sh
	build/apply-template.sh setup.sh.tmpl docs/setup.sh
	chmod a+x docs/setup.sh
