#
# Makefile for Ian, 2.1.2001
#

all:	../html/adminmanual.html ../txt/adminmanual.txt ../html/spiderFAQ.html ../txt/spiderFAQ.txt

#	../txt/adminmanual.txt: adminmanual.sgml
	sgml2txt adminmanual.sgml
	mv adminmanual.txt ../txt/

#	../html/adminmanual.html: adminmanual.sgml
	sgml2html adminmanual.sgml
	perl -p -e 's/<BODY>/<BODY BGCOLOR="#ffffff">/' *.html
	mv admin*.html ../html/	

#	../html/spiderFAQ.html: spiderFAQ.sgml 
	sgml2txt spiderFAQ.sgml
	mv spid*.txt ../txt

#	../html/spiderFAQ.html: spiderFAQ.sgml
	sgml2html spiderFAQ.sgml
	perl -pi.bak -e 's/<BODY>/<BODY BGCOLOR="#ffffff">/' *.html
	mv spid*.html ../html
	rm -f *.bak
