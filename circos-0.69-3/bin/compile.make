#!/bin/bash
#
# create batch file to compile Circos for Windows systems
#

LIBDIR="c:\\\Dwimperl\\\c\\\bin"
LINK="-l $LIBDIR\\\libgd-2_.dll -l $LIBDIR\\\libfreetype-6_.dll -l $LIBDIR\\\libpng12-0_.dll -l $LIBDIR\\\libpng15-15_.dll -l $LIBDIR\\\libXpm_.dll -l $LIBDIR\\\libz_.dll -l $LIBDIR\\\libiconv-2_.dll -l $LIBDIR\\\libjpeg-62_.dll" 
./circos -modules | shrinkwrap | c2 | sed 's/^/-M /g' | unsplit -delim " " | sed 's/::Font/::/' | awk -v LINK="$LINK" '{print "pp "$0,LINK" -o circos.exe circos"}'
