protocol.1 : protocol.pod
	podchecker protocol.pod
	pod2man protocol.pod > protocol.1
	pod2html protocol.pod > protocol.html
	groff -mandoc protocol.1 | ps2pdf - protocol.pdf
