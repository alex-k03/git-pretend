PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1

.PHONY: install uninstall test lint

install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)
	install -m 755 bin/git-pretend $(DESTDIR)$(BINDIR)/git-pretend
	install -m 644 man/git-pretend.1 $(DESTDIR)$(MANDIR)/git-pretend.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/git-pretend $(DESTDIR)$(MANDIR)/git-pretend.1

# Every POSIX-ish shell that is installed, since /bin/sh differs between systems
test:
	@for s in sh dash bash zsh; do \
		if command -v $$s >/dev/null 2>&1; then test/run.sh $$s || exit 1; fi; \
	done

lint:
	shellcheck bin/git-pretend test/run.sh
