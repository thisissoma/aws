
# $Id$

.SILENT:

# NOTE: You should not have to change this makefile. Configuration options can
# be changed in makefile.conf

include makefile.conf

INCLUDES = $(EXTRA_INCLUDES)
LIBS     = $(EXTRA_LIBS)

ifdef ADASOCKETS
INCLUDES := -I$(ADASOCKETS)/lib/adasockets $(INCLUDES)
LIBS     := -L$(ADASOCKETS)/lib -ladasockets $(LIBS)
endif

ifdef XMLADA
INCLUDES := -I$(XMLADA)/include/xmlada -I$(XMLADA)/lib $(INCLUDES)
LIB_DOM  = -lxmlada_dom
LIB_UNIC = -lxmlada_unicode
LIB_SAX  = -lxmlada_sax
LIB_IS   = -lxmlada_input_sources
LIBS	 := -L$(XMLADA)/lib $(LIB_IS) $(LIB_DOM) $(LIB_UNIC) $(LIB_SAX) $(LIBS)
endif

ifdef POSIX
INCLUDES := $(INCLUDES) -I$(POSIX)
endif

ifdef ASIS
INCLUDES := $(INCLUDES) -I$(ASIS)
LIBS	 := $(LIBS) -L$(ASIS) -lasis
endif

ifeq (${OS}, Windows_NT)
EXEEXT = .exe
else
EXEEXT =
endif

ifeq (${GNAT_VERSION}, 3.15)
# On GNAT 3.15 pragma Obsolescent and -gnatwjmv options are not supported,
# so we do not use this option and furtheremore we do not treat warnings as
# errors.
STYLE_FLAGS     = -gnatwcfipru -gnaty3abcefhiklmnoprst
else
# This is not GNAT 3.15, let's hope it is a version above
STYLE_FLAGS	= -gnatwcfijmpruv -gnatwe -gnaty3abcefhiklmnoprst
# -gnatwk (constant) should be added but in GNAT 3.16a it reports problems on
# withed packages.
endif

# compiler
RELEASE_GFLAGS	= -q -O2 -gnatn
DEBUG_GFLAGS	= -g -m -gnata

# linker
RELEASE_LFLAGS	= -s
DEBUG_LFLAGS	=

ifdef DEBUG
GFLAGS		= $(DEBUG_GFLAGS) $(STYLE_FLAGS)
LFLAGS		= $(DEBUG_LFLAGS)
MAKE_OPT	=
else
GFLAGS		= $(RELEASE_GFLAGS) $(STYLE_FLAGS)
LFLAGS		= $(RELEASE_LFLAGS)
MAKE_OPT	= -s
endif

#############################################################################
# NO NEED TO CHANGE ANYTHING PAST THIS POINT
#############################################################################

all:
	echo ""
	echo "Targets :"
	echo ""
	echo "  Configurations :"
	echo ""
	echo "    gnatsockets:  Use GNAT.Sockets [default]"
	echo "    adasockets:   Use AdaSockets"
	echo ""
	echo "    gnat_oslib:   OS_Lib implementation for GNAT only [default]"
	echo "    posix_oslib:  OS_Lib implementation based on POSIX"
	echo "    win32_oslib:  OS_Lib implementation for Win32 only"
	echo ""
	echo "    display       Display current configuration"
	echo ""
	echo "  Build :"
	echo ""
	echo "    build:        build AWS library, tools and demos"
	echo "    build_lib:    build AWS library only"
	echo "    build_tools:  build AWS library and tools"
	echo "    build_doc:    build documentation (needs texinfo support)"
	echo "    build_soap:   build SOAP library (needs XMLAda package)"
	echo ""
	echo "  Support :"
	echo ""
	echo "    clean:        to clean directories"
	echo "    distrib:      to build a tarball distribution"
	echo "    install:      install AWS library"
	echo "    run_regtests: run tests"

EXTRA_TESTS = 1

ALL_OPTIONS	= $(MAKE_OPT) GFLAGS="$(GFLAGS)" INCLUDES="$(INCLUDES)" \
	LIBS="$(LIBS)" LFLAGS="$(LFLAGS)" MODE="$(MODE)" XMLADA="$(XMLADA)" \
	ASIS="$(ASIS)" EXEEXT="$(EXEEXT)" LDAP="$(LDAP)" DEBUG="$(DEBUG)" \
	RM="$(RM)" CP="$(CP)" MV="$(MV)" MKDIR="$(MKDIR)" AR="$(AR)" \
	GREP="$(GREP)" SED="$(SED)" DIFF="$(DIFF)" CHMOD="$(CHMOD)" \
	GZIP="$(GZIP)" TAR="$(TAR)" GNATMAKE="$(GNATMAKE)" \
	DLLTOOL="$(DLLTOOL)" DLL2DEF="$(DLL2DEF)" WINDRES="$(WINDRES)" \
	GNATMAKE_FOR_HOST="$(GNATMAKE_FOR_HOST)" ADASOCKETS="$(ADASOCKETS)" \
	EXTRA_TESTS="$(EXTRA_TESTS)" GCC="$(GCC)" \
	GCC_FOR_HOST="$(GCC_FOR_HOST)"

build_stdlib: build_ssllib build_include build_aws build_win32

ifdef XMLADA
build_soap_internal: build_soaplib
else
build_soap_internal:
endif

build: build_stdlib build_soap_internal build_lib build_demos

build_lib: build_scripts build_stdlib build_soap_internal
	$(AR) cr lib/libaws.a src/*.o
	$(AR) cr lib/libaws.a ssl/*.o
ifdef XMLADA
	-$(AR) cr lib/libaws.a soap/*.o
endif
ifeq (${OS}, Windows_NT)
	-$(AR) cr lib/libaws.a win32/*.o
endif

build_scripts:
	echo ""
	echo "=== Build AWS support scripts"
	echo "  for UNIX"
	echo "export ADA_INCLUDE_PATH=\$$ADA_INCLUDE_PATH:"$(XMLADA)/include/xmlada > set-aws.sh
	echo "export ADA_INCLUDE_PATH=\$$ADA_INCLUDE_PATH:"$(INSTALL)/AWS/components >> set-aws.sh
	echo "export ADA_INCLUDE_PATH=\$$ADA_INCLUDE_PATH:"$(INSTALL)/AWS/include >> set-aws.sh
	echo "export ADA_OBJECTS_PATH=\$$ADA_OBJECTS_PATH:"$(INSTALL)/AWS/lib >> set-aws.sh
	echo "export ADA_OBJECTS_PATH=\$$ADA_OBJECTS_PATH:"$(XMLADA)/lib >> set-aws.sh
	echo "export ADA_OBJECTS_PATH=\$$ADA_OBJECTS_PATH:"$(XMLADA)/include/xmlada >> set-aws.sh
	echo "export ADA_OBJECTS_PATH=\$$ADA_OBJECTS_PATH:"$(INSTALL)/AWS/components >> set-aws.sh
	echo "export ADA_OBJECTS_PATH=\$$ADA_OBJECTS_PATH:"$(INSTALL)/AWS/include >> set-aws.sh
	echo "export PATH=\$$PATH:"$(INSTALL)/AWS/tools  >> set-aws.sh
	echo "  for Windows"
	echo "@echo off" > set-aws.cmd
	echo "set ADA_INCLUDE_PATH=%ADA_INCLUDE_PATH%;"$(XMLADA)/include/xmlada >> set-aws.cmd
	echo "set ADA_INCLUDE_PATH=%ADA_INCLUDE_PATH%;"$(INSTALL)/AWS/components >> set-aws.cmd
	echo "set ADA_INCLUDE_PATH=%ADA_INCLUDE_PATH%;"$(INSTALL)/AWS/include >> set-aws.cmd
	echo "set ADA_OBJECTS_PATH=%ADA_OBJECTS_PATH%;"$(INSTALL)/AWS/lib >> set-aws.cmd
	echo "set ADA_OBJECTS_PATH=%ADA_OBJECTS_PATH%;"$(XMLADA)/lib >> set-aws.cmd
	echo "set ADA_OBJECTS_PATH=%ADA_OBJECTS_PATH%;"$(XMLADA)/include/xmlada >> set-aws.cmd
	echo "set ADA_OBJECTS_PATH=%ADA_OBJECTS_PATH%;"$(INSTALL)/AWS/components >> set-aws.cmd
	echo "set ADA_OBJECTS_PATH=%ADA_OBJECTS_PATH%;"$(INSTALL)/AWS/include >> set-aws.cmd
	echo "set PATH=%PATH%;"$(INSTALL)/AWS/tools  >> set-aws.cmd

build_aws:
	echo ""
	echo "=== Build AWS library"
	${MAKE} -C src build $(ALL_OPTIONS)

build_tools:
	echo ""
	echo "=== Build tools"
	${MAKE} -C tools build $(ALL_OPTIONS)

build_demos: build_stdlib build_tools
	echo ""
	echo "=== Build demos"
	${MAKE} -C demos build $(ALL_OPTIONS)

build_ssllib:
	echo ""
	echo "=== Build SSL support"
	${MAKE} -C ssl build $(ALL_OPTIONS)

build_soaplib: build_include build_stdlib
	echo ""
	echo "=== Build SOAP library"
	${MAKE} -C soap build $(ALL_OPTIONS)

build_soap: build_soaplib

gnatsockets:
	${MAKE} -C src gnatsockets $(ALL_OPTIONS)

adasockets:
	${MAKE} -C src adasockets $(ALL_OPTIONS)

gnat_oslib:
	${MAKE} -C src gnat_oslib $(ALL_OPTIONS)

posix_oslib:
	${MAKE} -C src posix_oslib $(ALL_OPTIONS)

win32_oslib:
	${MAKE} -C src win32_oslib $(ALL_OPTIONS)

build_doc:
	echo ""
	echo "=== Build doc"
	${MAKE} -C docs build $(ALL_OPTIONS)

build_include:
	echo ""
	echo "=== Build components"
	${MAKE} -C include build $(ALL_OPTIONS)

build_win32:
	echo ""
	echo "=== Build win32 specific packages"
	${MAKE} -C win32 build $(ALL_OPTIONS)

build_apiref:
	echo ""
	echo "=== Build API References"
	${MAKE} -s -C docs apiref $(ALL_OPTIONS)

run_regtests: build_tools
	echo ""
	echo "=== Run regression tests"
	${MAKE} -C regtests run $(ALL_OPTIONS) GDB_REGTESTS="$(GDB_REGTESTS)"

clean: clean_noapiref
	${MAKE} -C docs clean_apiref $(ALL_OPTIONS)
	${MAKE} -C lib clean $(ALL_OPTIONS)

clean_noapiref:
	${MAKE} -C include clean $(ALL_OPTIONS)
	${MAKE} -C config clean $(ALL_OPTIONS)
	${MAKE} -C src clean $(ALL_OPTIONS)
	${MAKE} -C demos clean $(ALL_OPTIONS)
	${MAKE} -C ssl clean $(ALL_OPTIONS)
	${MAKE} -C docs clean $(ALL_OPTIONS)
	${MAKE} -C soap clean $(ALL_OPTIONS)
	${MAKE} -C regtests clean $(ALL_OPTIONS)
	${MAKE} -C win32 clean $(ALL_OPTIONS)
	${MAKE} -C tools clean $(ALL_OPTIONS)
	-rm -f *.~*.*~ set-aws.*

display:
	echo ""
	echo AWS current configuration
	echo ""
ifeq (${OS}, Windows_NT)
	echo "Windows OS detected"
	echo "   To build AWS on this OS you need to have a set of UNIX like"
	echo "   tools (cp, mv, mkdir, chmod...) You should install"
	echo "   Cygwin or Msys toolset."
	echo ""
else
	echo "UNIX like OS detected"
endif
	echo "Install directory     : " $(INSTALL)
ifdef XMLADA
	echo "XMLada activated      : " $(XMLADA)
else
	echo "XMLada not activated, SOAP will not be built"
endif
ifdef ADASOCKETS
	echo "AdaSockets package in : " $(ADASOCKETS)
else
	echo "Using GNAT.Sockets"
endif

common_tarball:
	$(CHMOD) uog+rx win32/*.dll
	(VERSION=`grep " Version" src/aws.ads | cut -d\" -f2`; \
	AWS=aws-$${VERSION}; \
	$(MKDIR) $${AWS}; \
	$(MKDIR) $${AWS}/src; \
	$(MKDIR) $${AWS}/demos; \
	$(MKDIR) $${AWS}/regtests; \
	$(MKDIR) $${AWS}/docs; \
	$(MKDIR) $${AWS}/docs/html; \
	$(MKDIR) $${AWS}/icons; \
	$(MKDIR) $${AWS}/include; \
	$(MKDIR) $${AWS}/include/zlib; \
	$(MKDIR) $${AWS}/lib; \
	$(MKDIR) $${AWS}/ssl; \
	$(MKDIR) $${AWS}/win32; \
	$(MKDIR) $${AWS}/tools; \
	$(MKDIR) $${AWS}/config; \
	$(MKDIR) $${AWS}/config/src; \
	$(MKDIR) $${AWS}/config/projects; \
	$(MKDIR) $${AWS}/support; \
	\
	for file in \
           `$(AWK) '$$1!="--" && $$1!="" {print $$0} \
		    $$2=="FULL" {exit}' MANIFEST`; \
        do \
		$(CP) $$file $${AWS}/$$file; \
	done;\
	\
	$(CP) -r docs/html/* $${AWS}/docs/html)

build_tarball:
	(VERSION=`grep " Version" src/aws.ads | cut -d\" -f2`; \
	AWS=aws-$${VERSION}; \
	$(RM) -f $${AWS}.tar.gz; \
	$(MKDIR) $${AWS}/xsrc; \
	$(MKDIR) $${AWS}/soap; \
	\
	for file in \
           `$(AWK) 'BEGIN{p=0} \
		    p==1 && $$1!="--" && $$1!="" {print $$0} \
		    $$2=="FULL"{p=1}' MANIFEST`; \
        do \
		$(CP) $$file $${AWS}/$$file; \
	done;\
	\
	$(TAR) cf $${AWS}.tar $${AWS};\
	$(GZIP) -9 $${AWS}.tar;\
	$(RM) -fr $${AWS})

build_http_tarball:
	(VERSION=`grep " Version" src/aws.ads | cut -d\" -f2`; \
	AWS=aws-http-$${VERSION}; \
	$(MV) aws-$${VERSION} $${AWS}; \
	$(RM) -f $${AWS}.tar.gz; \
	$(SED) 's/$$(LIBSSL) $$(LIBCRYPTO)//' \
	   win32/makefile > $${AWS}/win32/makefile;\
	$(SED) 's/sha.ads sha-process_data.adb sha-strings.adb//' \
	   include/makefile > $${AWS}/include/makefile;\
	$(TAR) cf $${AWS}.tar $${AWS};\
	$(GZIP) -9 $${AWS}.tar;\
	$(CP) win32/makefile $${AWS}/win32/makefile;\
	$(CP) include/makefile $${AWS}/include/makefile;\
	$(MV) $${AWS} aws-$${VERSION})

build_tarballs: common_tarball build_http_tarball build_tarball

distrib: build_apiref clean_noapiref build_doc build_tarballs

force:

install: force
	-rm -fr $(INSTALL)/AWS
	$(MKDIR) $(INSTALL)/AWS
	$(MKDIR) $(INSTALL)/AWS/obj
	$(MKDIR) $(INSTALL)/AWS/lib
	$(MKDIR) $(INSTALL)/AWS/include
	$(MKDIR) $(INSTALL)/AWS/icons
	$(MKDIR) $(INSTALL)/AWS/images
	$(MKDIR) $(INSTALL)/AWS/templates
	$(MKDIR) $(INSTALL)/AWS/docs
	$(MKDIR) $(INSTALL)/AWS/docs/html
	$(MKDIR) $(INSTALL)/AWS/components
	$(MKDIR) $(INSTALL)/AWS/tools
	$(CP) -p src/[at]*.ad[sb] ssl/*.ad[sb] $(INSTALL)/AWS/include
	-$(CP) -p soap/*.ad[sb] $(INSTALL)/AWS/include
	$(CP) -p src/[at]*.ali $(INSTALL)/AWS/lib
	-$(CP) -p ssl/*.ali $(INSTALL)/AWS/lib
	-$(CP) -p soap/*.ali $(INSTALL)/AWS/lib
	$(CP) lib/libaws.a $(INSTALL)/AWS/lib
	$(CP) lib/libnosslaws.a $(INSTALL)/AWS/lib
	$(CP) lib/libz.a $(INSTALL)/AWS/lib
	-$(CP) docs/aws.html $(INSTALL)/AWS/docs
	$(CP) docs/templates_parser.html $(INSTALL)/AWS/docs
	-$(CP) docs/aws.txt $(INSTALL)/AWS/docs
	-$(CP) docs/*.info* $(INSTALL)/AWS/docs
	-$(CP) -r docs/html/* $(INSTALL)/AWS/docs/html
	$(CP) demos/*.thtml $(INSTALL)/AWS/templates
	$(CP) demos/wm_login.html $(INSTALL)/AWS/templates
	$(CP) icons/*.gif $(INSTALL)/AWS/icons
	$(CP) demos/aws_*.png $(INSTALL)/AWS/images
	-$(CP) -p include/*.ad? $(INSTALL)/AWS/components
	-$(CP) -p include/*.o include/*.ali $(INSTALL)/AWS/components
	-$(CP) tools/awsres${EXEEXT} $(INSTALL)/AWS/tools
	-$(CP) tools/wsdl2aws${EXEEXT} $(INSTALL)/AWS/tools
	-$(CP) tools/ada2wsdl${EXEEXT} $(INSTALL)/AWS/tools
	$(CP) -p $(INSTALL)/AWS/lib/*.ali $(INSTALL)/AWS/obj
	$(CP) set-aws.* $(INSTALL)/AWS
ifdef XMLADA
	$(CP) config/projects/aws.gpr $(INSTALL)/AWS
else
	$(SED) -e 's/with "xmlada";//' \
		< config/projects/aws.gpr \
		> $(INSTALL)/AWS/aws.gpr
endif
	$(CP) config/projects/components.gpr $(INSTALL)/AWS/components
	-$(CHMOD) -R og+r $(INSTALL)/AWS
	-$(CHMOD) uog-w $(INSTALL)/AWS/components/*.ali
	-$(CHMOD) uog-w $(INSTALL)/AWS/lib/*.ali
	-$(CHMOD) uog-w $(INSTALL)/AWS/obj/*.ali
ifeq (${OS}, Windows_NT)
	$(CP) lib/lib*.a $(INSTALL)/AWS/lib
	-$(CP) win32/*.dll $(INSTALL)/AWS/lib
endif

#############################################################################
# Configuration for GNAT Projet Files

MODULES = config win32 ssl include src tools demos

MODULES_BUILD = ${MODULES:%=%_build}

MODULES_SETUP = ${MODULES:%=%_setup}

MODULES_CLEAN = ${MODULES:%=%_clean}

ifdef XMLADA
PRJ_XMLADA=Installed
else
PRJ_XMLADA=Disabled
endif

ifdef ASIS
PRJ_ASIS=Installed
GEXT_MODULE := $(GEXT_MODULE) gasis
else
PRJ_ASIS=Disabled
GEXT_MODULE := gasis_dummy
endif

ifdef DEBUG
PRJ_BUILD=Debug
else
PRJ_BUILD=Release
endif

GALL_OPTIONS := $(ALL_OPTIONS) \
	PRJ_BUILD="$(PRJ_BUILD)" \
	PRJ_XMLADA="$(PRJ_XMLADA)" \
	PRJ_ASIS="$(PRJ_ASIS)"

${MODULES_BUILD}: force
	${MAKE} -C ${@:%_build=%} gbuild $(GALL_OPTIONS)

${MODULES_SETUP}: force
	${MAKE} -C ${@:%_setup=%} gsetup $(GALL_OPTIONS)

${MODULES_CLEAN}: force
	${MAKE} -C ${@:%_clean=%} gclean $(GALL_OPTIONS)

gbuild: $(MODULES_BUILD)

gclean: $(MODULES_CLEAN)
	-rm -fr .build asis.gpr

gasis:
	echo "project ASIS is" > asis.gpr
	echo " Path := \"$(ASIS)\";" >> asis.gpr
	echo " for Source_Dirs use (Path);" >> asis.gpr
	echo " for Object_Dir use Path;" >> asis.gpr
	echo " LIB_Path := \"-L\" & Path;" >> asis.gpr
	echo "end ASIS;" >> asis.gpr

gasis_dummy:
	echo "project ASIS is" > asis.gpr
	echo " for Source_Dirs use ();" >> asis.gpr
	echo " LIB_Path := \"\";" >> asis.gpr
	echo "end ASIS;" >> asis.gpr

gsetup: $(GEXT_MODULE) $(MODULES_SETUP)
