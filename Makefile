PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: install uninstall

install:
	install -d "$(BINDIR)"
	install -m 0755 foodroid "$(BINDIR)/foodroid"
	install -m 0755 logq "$(BINDIR)/logq"

uninstall:
	rm -f "$(BINDIR)/foodroid" "$(BINDIR)/logq"
