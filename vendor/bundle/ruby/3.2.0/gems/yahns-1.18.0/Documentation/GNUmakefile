# Copyright (C) 2013-2016 all contributors <yahns-public@yhbt.net>
# License: GPL-3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
all::

INSTALL = install
POD2MAN = pod2man
-include ../GIT-VERSION-FILE
release := yahns $(VERSION)
POD2MAN_OPTS = -v -r '$(release)' --stderr -d 1994-10-02 -c 'yahns user manual'
pod2man = $(POD2MAN) $(POD2MAN_OPTS)
POD2TEXT = pod2text
POD2TEXT_OPTS = --stderr
pod2text = $(POD2TEXT) $(POD2TEXT_OPTS)

m1 =
m1 += yahns
m1 += yahns-rackup

m5 =
m5 += yahns_config

m7 =

man1 := $(addsuffix .1, $(m1))
man5 := $(addsuffix .5, $(m5))
man7 := $(addsuffix .7, $(m7))

all:: man

man: $(man1) $(man5) $(man7)

prefix ?= $(HOME)
mandir ?= $(prefix)/share/man
man1dir = $(mandir)/man1
man5dir = $(mandir)/man5
man7dir = $(mandir)/man7

gem-man: man
	$(INSTALL) -d -m 755 ../man
	$(INSTALL) -m 644 $(man1) ../man
	$(INSTALL) -m 644 $(man5) ../man
	test -z "$(man7)" || $(INSTALL) -m 644 $(man7) ../man

install-man: man
	$(INSTALL) -d -m 755 $(DESTDIR)$(man1dir)
	$(INSTALL) -d -m 755 $(DESTDIR)$(man5dir)
	test -z "$(man7)" || $(INSTALL) -d -m 755 $(DESTDIR)$(man7dir)
	$(INSTALL) -m 644 $(man1) $(DESTDIR)$(man1dir)
	$(INSTALL) -m 644 $(man5) $(DESTDIR)$(man5dir)
	test -z "$(man7)" || $(INSTALL) -m 644 $(man7) $(DESTDIR)$(man7dir)

%.1 %.5 %.7 : %.pod
	$(pod2man) -s $(subst .,,$(suffix $@)) $< $@+ && mv $@+ $@

mantxt = $(addsuffix .txt, $(m1) $(m5) $(m7))

txt :: $(mantxt)

all :: txt

%.txt : %.pod
	$(pod2text) $< $@+
	touch -r $< $@+
	mv $@+ $@

clean::
	$(RM) $(man1) $(man5) $(man7)
	$(RM) $(addsuffix .txt.gz, $(m1) $(m5) $(m7))
