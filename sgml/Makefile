#
# Makefile for Ian, 2.1.2001
#

all:	../html/adminmanual.html ../txt/adminmanual.txt ../html/spiderFAQ.html ../txt/spiderFAQ.txt ../html/usermanual.html ../txt/usermanual.txt

#	../txt/adminmanual.txt: adminmanual.sgml
	sgml2txt adminmanual.sgml

#	../html/adminmanual.html: adminmanual.sgml
	sgml2html adminmanual.sgml

#	../html/spiderFAQ.html: spiderFAQ.sgml 
	sgml2txt spiderFAQ.sgml

#	../html/spiderFAQ.html: spiderFAQ.sgml
	sgml2html spiderFAQ.sgml

#	../html/usermanual.html: usermanual.sgml
	sgml2html usermanual.sgml

#	../txt/usermanual.txt: usermanual.sgml
	sgml2txt usermanual.sgml

	perl -pi.bak -e 's|</HEAD>|<link rel=stylesheet href="style.css" type="text/css" title="default stylesheet">\n</HEAD>|' *.html
	mv *.html ../html
	mv *.txt ../txt
	rm -f *.bak
