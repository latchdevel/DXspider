#! /bin/sh
#
###################################################
#
# Edit the following lines
#
#
portnumber=$"1407"
tempdir=$"/usr/local/httpd/spider/client/"
clustercall=$"PA4AB-15"
#
#
#
# End of configurable part
#
####################################################
hostname=$"localhost"

echo "Content-type: text/html"
echo
echo "<HTML><HEAD>"
echo "<TITLE>Spider DX Cluster</TITLE>"
echo "</HEAD><BODY>"
echo '<BODY BGCOLOR="#d8d0c8">'
echo "<PRE>"

pattern=$(echo ${QUERY_STRING} | sed -e s,'call=',, | sed -e s/"&passwd="/" "/)
call=$(echo $pattern | cut -d' ' -f1)
passwd=$(echo $pattern | cut -s -d' ' -f2)


if [ ${call} = ""]  ; then
  echo "<BR>"
  echo "<CENTER>"
  echo "<STRONG><FONT SIZE=5>Welcome to the Spider DX Cluster</FONT></STRONG>"
  echo "<STRONG><FONT SIZE=5>"
  echo ${clustercall}
  echo "</FONT></STRONG>"
  echo "<P> &nbsp; </P>"
  echo '<FORM action="/cgi-bin/spider.cgi" method=get>'
  echo "<STRONG>Your Call Please: </STRONG> "
  echo '<INPUT name="call" size=10> '
  echo '<INPUT type=submit value="Click here to Login">'
  echo "</CENTER>"
  echo "<BR>"

else
  echo "<HTML>" > ${tempfile}${call}.html
  echo "<HEAD>" >> ${tempfile}${call}.html
  echo "</HEAD>" >> ${tempfile}${call}.html
  echo "<BODY>" >> ${tempfile}${call}.html
  echo '<APPLET code="spiderclient.class" width=800 height=130>'  >> ${tempdir}${call}.html
  echo '<PARAM NAME="CALL" VALUE='  >> ${tempdir}${call}.html
  echo ${call}  >> ${tempdir}${call}.html
  echo ">" >> ${tempdir}${call}.html
  echo ">"  >> ${tempdir}${call}.html 
  echo '<PARAM NAME="HOSTNAME" VALUE="'  >> ${tempdir}${call}.html
  echo ${hostname} >> ${tempdir}${call}.html
  echo '">' >> ${tempdir}${call}.html
  echo '<PARAM NAME="PORT" VALUE="'  >> ${tempdir}${call}.html
  echo ${portnumber} >> ${tempdir}${call}.html
  echo '">' >> ${tempdir}${call}.html
  echo "</APPLET>"  >> ${tempdir}${call}.html
  echo "</BODY>"  >> ${tempdir}${call}.html
  echo "</HTML>"  >> ${tempdir}${call}.html
  GOTO='<meta http-equiv="refresh"content="0;URL=http://'${hostname}'/client/'
  GOTO=$GOTO$call.html
  GOTO=$GOTO'">'
  echo ${GOTO}

fi
  echo "</PRE>"
  echo "</BODY></HTML>"

#  all *.html tempory files remove older than 10 min 
# 
cd ${tempdir}
files=$(find  *.html -mmin +10)
rm ${files}
