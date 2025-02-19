## Makefile.am -- Config file for GNU Automake.
##
## Copyright (C) 2021 Artyom V. Poptsov <poptsov.artyom@gmail.com>
##
## This file is part of Guile-SMC.
##
## Guile-SMC is free software: you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation, either version 3 of the
## License, or (at your option) any later version.
##
## Guile-SMC is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Guile-SMC.  If not, see <http://www.gnu.org/licenses/>.

include $(top_srcdir)/build-aux/am/guilec

SUBDIRS = core . context cli

SOURCES = \
	version.scm	\
	fsm.scm 	\
	puml-context.scm \
	puml-fsm.scm	\
	puml.scm	\
	compiler.scm

EXTRA_DIST = \
	version.scm.in

GOBJECTS = $(SOURCES:%.scm=%.go)

moddir=$(guilesitedir)/smc/
nobase_dist_mod_DATA = $(SOURCES)

ccachedir=$(libdir)/guile/$(GUILE_EFFECTIVE_VERSION)/site-ccache/smc
nobase_nodist_ccache_DATA = $(GOBJECTS)

# Make sure source files are installed first, so that the mtime of
# installed compiled files is greater than that of installed source
# files.  See
# <http://lists.gnu.org/archive/html/guile-devel/2010-07/msg00125.html>
# for details.
guile_smc_install_go_files = install-nobase_dist_ccacheDATA
$(guile_smc_install_go_files): install-nobase_dist_modDATA

GUILE_WARNINGS = -Wunbound-variable -Warity-mismatch -Wformat
SUFFIXES = .scm .go .in

guilec_opts = --load-path=$(abs_top_srcdir)/modules/

guilec_env = GUILE_AUTO_COMPILE=0

.scm.go:
	$(AM_V_GUILEC)$(guilec_env) $(GUILEC) $(guilec_opts) \
	--output=$@ $<

puml-fsm.scm: puml.puml
	@echo "  SMC      $<"
	@cat $< | smc compile \
	    --fsm-name "puml-fsm" \
	    --fsm-module "(smc puml-fsm)" \
	    --modules "((smc context char-context)(smc puml-context))" > $@

substitute = sed -e 's,[@]VERSION[@],$(PACKAGE_VERSION),g'

version.scm: version.scm.in
	@echo "  GEN      $@"
	@$(substitute) "$^" > "$@"

clean-go:
	-$(RM) $(GOBJECTS)
.PHONY: clean-go

CLEANFILES = \
	$(GOBJECTS)	\
	version.scm
