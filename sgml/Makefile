#
# Makefile for Ian, 2.1.2001
#

all:	../html/adminmanual.html ../txt/adminmanual.txt ../html/installation.html ../txt/installation.txt ../html/spiderFAQ.html ../txt/spiderFAQ.txt ../html/usermanual.html ../txt/usermanual.txt ../html/spiderCVS.html ../txt/spiderCVS.txt

#	../txt/adminmanual.txt: adminmanual.sgml
	sgml2txt -f adminmanual.sgml

#	../html/adminmanual.html: adminmanual.sgml
	sgml2html adminmanual.sgml

#	../txt/installation.txt: installation.sgml
	sgml2txt -f installation.sgml

#	../html/installation.html: installation.html
	sgml2html installation.sgml

#	../html/spiderFAQ.html: spiderFAQ.sgml 
	sgml2txt spiderFAQ.sgml

#	../html/spiderFAQ.html: spiderFAQ.sgml
	sgml2html spiderFAQ.sgml

#	../html/usermanual.html: usermanual.sgml
	sgml2html usermanual.sgml

#	../txt/usermanual.txt: usermanual.sgml
	sgml2txt usermanual.sgml

#	../html/spiderCVS.html: spiderCVS.sgml
	sgml2html spiderCVS.sgml

#	../txt/spiderCVS.txt: spiderCVS.sgml
	sgml2txt spiderCVS.sgml

	perl -pi.bak -e 's|</HEAD>|<link rel=stylesheet href="style.css" type="text/css" title="default stylesheet">\n</HEAD>|' *.html
	mv *.html ../html
	mv *.txt ../txt
	rm -f *.bak
