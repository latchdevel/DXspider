#!/usr/bin/perl

# cluster-web.pl - perl login script for cluster web interface.
# @author Ian Norton 
# - Based on clx-web by DL6DBH (ftp://clx.muc.de/pub/clx/clx-java_10130001.tgz)
# - Modified by PA4AB
# @version 0.2 beta.  20020519.

# Work out the hostname of this server.
use Sys::Hostname;
my $HOSTNAME = hostname();

# Please note that the HOSTNAME MUST be resolvable from the user end. Otherwise the
# web interface will NOT work.
# Uncomment and set the hostname manually here if the above fails.
# $HOSTNAME = "gb7mbc.spoo.org" ;
$PORT = "8000" ;
$NODECALL = "XX0XX" ;

# Send text/html header to the browser.
print "Content-type: text/html\n\n";

# Get the parameters passed to the script.
read (STDIN, $post_data, $ENV{CONTENT_LENGTH});

$callstart = index($post_data, "=") + 1 ;
$callend = index($post_data, "&") ;

$call = substr($post_data, $callstart, $callend - $callstart), 
$password = substr($post_data, index($post_data, "=", $callend) + 1, length($post_data)) ;

# Print the page header.
#print("Callsign : $call") ;
#print("Password : $password") ;
print <<'EOF';

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN">
<HTML LANG="EN">
    <HEAD>
        <TITLE>Cluster Web - DX Cluster Web Interface.</TITLE>
        <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=ISO-8859-1">
        <META NAME="Author" CONTENT="Ian Norton.">
        <META NAME="DESCRIPTION" CONTENT="DX Cluster web interface">
    </HEAD>
     
<BODY BGCOLOR="#FFFFFF" LINK="#008080" ALINK="#000099" VLINK="#000099">         

    <H1>
    <CENTER>
        <FONT FACE="arial, helvicta" COLOR="#008080" SIZE=+2>
        <B><BR>Cluster Web - DX Cluster Web Interface.</B><BR>
EOF

        print("Welcome to $NODECALL<BR>") ;

print <<'EOF';
        </FONT>
    </CENTER>
    </H1>

<BR CLEAR="ALL">

<HR>
EOF

if($ENV{CONTENT_LENGTH} > 0)
    {
    # Callsign is set - print the whole <APPLET> stuff....
    # print("Callsign is $call<BR>\n") ;

    print("<CENTER>\n") ;
    print("    <APPLET CODE=\"spiderclient.class\" CODEBASE=\"/client/\" width=800 height=130>\n") ;
    print("        <PARAM NAME=\"CALL\" VALUE=\"$call\">\n") ;
    print("        <PARAM NAME=\"PASSWORD\" VALUE=\"$password\">\n") ;
    print("        <PARAM NAME=\"HOSTNAME\" VALUE=\"$HOSTNAME\">\n") ;
    print("        <PARAM NAME=\"PORT\" VALUE=\"$PORT\">\n") ;
    print("        <PARAM NAME=\"NODECALL\" VALUE=\"$NODECALL\">\n") ;
    print("    </APPLET>\n") ;
    print("</CENTER>\n") ;
    }
else
    {
    # Callsign isn't set - print the login page.
    print <<'EOF';
    <CENTER>
    <FORM METHOD=POST>
        <STRONG>Please enter your callsign: </STRONG><BR>
        <INPUT name="call" size=10><BR>
        <STRONG>Please enter your password: </STRONG><BR>
        <INPUT name="password" size=10 TYPE=PASSWORD><BR>
        <INPUT type=submit value="Click here to Login">
    </FORM>
    <BR>If you do not have a password set - don't enter one :)
    </CENTER>
EOF
    }

print <<'EOF';
<HR>

<ADDRESS>
<A HREF="http://www.dxcluster.org/">Spider Homepage</A>.
</HTML>

EOF
