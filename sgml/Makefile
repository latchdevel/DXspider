#
# Makefile for Ian, 2.1.2001
#

all:	sgml ../html/adminmanual_en.html ../txt/adminmanual_en.txt ../html/installation_en.html ../txt/installation_en.txt ../html/spiderFAQ_en.html ../txt/spiderFAQ_en.txt ../html/usermanual_en.html ../txt/usermanual_en.txt ../html/spiderCVS_en.html ../txt/spiderCVS_en.txt ../html/filtering_en.html ../txt/filtering_en.txt

sgml: ../cmd/Commands_en.hlp adminmanual.sgml usermanual.sgml
	# Create the admin manual sgml file
	cat ../cmd/Commands_en.hlp  | ./commands2sgml.pl 9 > ./adminmanual-cmd.sgml
	cat adminmanual.sgml adminmanual-cmd.sgml > ./adminmanual_en.sgml

	# Create the user manual sgml file
	cat ../cmd/Commands_en.hlp | ./commands2sgml.pl > usermanual-cmd.sgml
	cat usermanual.sgml usermanual-cmd.sgml > usermanual_en.sgml

#	../txt/adminmanual_en.txt: adminmanual_en.sgml
	sgml2txt -f adminmanual_en.sgml

#	../html/adminmanual_en.html: adminmanual_en.sgml
	sgml2html adminmanual_en.sgml

#	../txt/installation_en.txt: installation_en.sgml
	sgml2txt -f installation_en.sgml

#	../html/installation_en.html: installation_en.html
	sgml2html installation_en.sgml

#	../html/spiderFAQ_en.html: spiderFAQ_en.sgml 
	sgml2txt -f spiderFAQ_en.sgml

#	../html/spiderFAQ_en.html: spiderFAQ_en.sgml
	sgml2html spiderFAQ_en.sgml

#	../html/usermanual_en.html: usermanual_en.sgml
	sgml2html usermanual_en.sgml

#	../txt/usermanual_en.txt: usermanual_en.sgml
	sgml2txt -f usermanual_en.sgml

#	../html/spiderCVS_en.html: spiderCVS_en.sgml
	sgml2html spiderCVS_en.sgml

#	../txt/spiderCVS_en.txt: spiderCVS_en.sgml
	sgml2txt -f spiderCVS_en.sgml

#	../html/filtering_en.html: filtering_en.sgml
	sgml2html filtering_en.sgml

#	../txt/filtering_en.txt: filtering_en.sgml
	sgml2txt -f filtering_en.sgml

	perl -pi.bak -e 's|</HEAD>|<link rel=stylesheet href="style.css" type="text/css" title="default stylesheet">\n</HEAD>|' *.html
	mv *.html ../html
	mv *.txt ../txt
	rm -f *.bak
	rm -f *cmd.sgml

