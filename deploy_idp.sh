#!/bin/sh
# UTF-8
##############################################################################
# Shibboleth deployment script by Anders Lördal                              #
# Högskolan i Gävle and SWAMID                                               #
#                                                                            #
# Version 1.0                                                                #
#                                                                            #
# Deploys a working IDP for SWAMID on an Ubuntu system                       #
# Uses: jboss-as-distribution-6.1.0.Final                                    #
#       shibboleth-identityprovider-2.3.4                                    #
#       cas-client-3.2.1-release                                             #
#                                                                            #
# Templates are provided for CAS and LDAP authentication                     #
#                                                                            #
# To add a new template for another authentication, just add a new directory #
# under the "prep" directory, add the neccesary .diff files and add any      #
# special hanling of those files to the script.                              #
#                                                                            #
# You can pre-set configuration values in the file "config"                  #
#                                                                            #
# Please send questions and improvements to: anders.lordal@hig.se            #
##############################################################################

# Set cleanUp to 0 (zero) for debugging of created files
cleanUp=1
files=""

if [ "$USERNAME" != "root" ]
then
	echo "Run as root!"
	exit
fi

# set JAVA_HOME and script path
export JAVA_HOME=/usr/lib/jvm/java-6-openjdk/jre/
if [ -z "`grep 'JAVA_HOME' /root/.bashrc`" ]
then
	echo "export JAVA_HOME=/usr/lib/jvm/java-6-openjdk/jre/" >> /root/.bashrc
fi
Spath="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${Spath}/config" ]
then
	. ${Spath}/config
fi

if [ -z "$type" ]
then
	echo "Authentication [ `ls ${Spath}/prep |grep -v common | perl -npe 's/\n/\ /g'`]"
	read type
	echo ""
fi
prep="prep/$type"

if [ -z "$google" ]
then
	echo "Release attributes to Google? [Y/n]: (Swamid, Swamid-test and testshib.org installed as standard)"
	read google
	echo ""
fi

if [ "$google" != "n" -a -z "$googleDom" ]
then
	echo "Your Google domain name: (student.xxx.yy)"
	read googleDom
	echo ""
fi

if [ -z "$ntpserver" ]
then
	echo "Specify NTP server:"
	read ntpserver
	echo ""
fi

if [ -z "$ldapserver" ]
then
	echo "Specify LDAP URL: (ldap.xxx.yy)"
	read ldapserver
	echo ""
fi

if [ -z "$ldapbasedn" ]
then
	echo "Specify LDAP Base DN:"
	read ldapbasedn
	echo ""
fi

if [ -z "$ldapbinddn" ]
then
	echo "Specify LDAP Bind DN:"
	read ldapbinddn
	echo ""
fi

if [ -z "$ldappass" ]
then
	echo "Specify LDAP Password:"
	read ldappass
	echo ""
fi

if [ "$type" = "ldap" -a -z "$subsearch" ]
then
	echo "LDAP Subsearch: [ true | false ]"
	read subsearch
	echo ""
fi

if [ -z "$idpurl" ]
then
	echo "Specify IDP URL: (https://idp.xxx.yy)"
	read idpurl
	echo ""
fi

if [ "$type" = "cas" ]
then
	if [ -z "$caslogurl" ]
	then
		echo "Specify CAS Login URL server: (https://cas.xxx.yy/cas/login)"
		read caslogurl
		echo ""
	fi

	if [ -z "$casurl" ]
	then
		echo "Specify CAS URL server: (https://cas.xxx.yy/cas)"
		read casurl
		echo ""
	fi
fi

if [ -z "$certOrg" ]
then
	echo "Organisation name string for certificate request:"
	read certOrg
	echo ""
fi

if [ -z "$certC" ]
then
	echo "Country string for certificate request: (empty string for 'SE')"
	read certC
	echo ""
fi
if [ -z "$certC" ]
then
	certC="SE"
fi

echo "IDP keystore password (empty string generates new password)"
read pass


# install depends
echo ""
echo ""
echo ""
echo "Starting deployment!"
echo "Updating apt and installing dependancies"
apt-get -qq update
apt-get -qq install unzip default-jre apache2 apg wget

# generate keystore pass
if [ -z "$pass" ]
then
	pass=`apg -m20 -n 1`
fi
idpfqdn=`echo $idpurl | awk -F\/ '{print $3}'`

# get depens if needed
if [ ! -f "${Spath}/files/jboss-as-distribution-6.1.0.Final.zip" ]
then
	echo "Jboss not found, fetching from web"
	wget -q -O ${Spath}/files/jboss-as-distribution-6.1.0.Final.zip http://download.jboss.org/jbossas/6.1/jboss-as-distribution-6.1.0.Final.zip
fi

if [ ! -f "${Spath}/files/shibboleth-identityprovider-2.3.4-bin.zip" ]
then
	echo "Shibboleth not found, fetching from web"
	wget -q -O ${Spath}/files/shibboleth-identityprovider-2.3.4-bin.zip http://www.shibboleth.net/downloads/identity-provider/2.3.4/shibboleth-identityprovider-2.3.4-bin.zip
fi

if [ "$type" = "cas" ]
then
	if [ ! -f "${Spath}/files/cas-client-3.2.1-release.zip" ]
	then
		echo "Cas-client not found, fetching from web"
		wget -q -O ${Spath}/files/cas-client-3.2.1-release.zip http://downloads.jasig.org/cas-clients/cas-client-3.2.1-release.zip
	fi
fi

# unzip all files
cd /opt
echo "Unzipping dependancies"
unzip -q ${Spath}/files/jboss-as-distribution-6.1.0.Final.zip
unzip -q ${Spath}/files/shibboleth-identityprovider-2.3.4-bin.zip
if [ "$type" = "cas" ]
then
	unzip -q ${Spath}/files/cas-client-3.2.1-release.zip
fi

chmod 755 shibboleth-identityprovider-2.3.4
chmod 755 jboss-6.1.0.Final

# create links
ln -s jboss-6.1.0.Final jboss
ln -s shibboleth-identityprovider-2.3.4 shibboleth-identityprovider

# copy shibboleth depend into java
# cp /opt/shibboleth-identityprovider/lib/shibboleth-jce-1.1.0.jar /usr/lib/jvm/java-6-openjdk/jre/lib/ext/

if [ "$type" = "cas" ]
then
# copy cas depends into shibboleth
	cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/lib/
	cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/lib/
	mkdir /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
	cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
	cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
fi

# create a default website for port 80
cp ${Spath}/xml/index.html /var/www

# Get TCS CA chain, import ca-certs java and create cert request
mkdir -p /etc/apache2/ssl/
cd /etc/apache2/ssl/
echo "Fetching TCS CA chain from web"
wget -q -O /etc/apache2/ssl/server.chain http://webkonto.hig.se/chain.pem

echo "Installing TCS CA chain i java testcacert keystore"
cnt=1
for i in `cat /etc/apache2/ssl/server.chain | perl -npe 's/\ /\*\*\*/g'`
do
	n=`echo $i | perl -npe 's/\*\*\*/\ /g'`
	echo $n >> /etc/apache2/ssl/${cnt}.root
	ltest=`echo $n | grep "END CERTIFICATE"`
	if [ ! -z "$ltest" ]
	then
		cnt=`expr $cnt + 1`
	fi
done
ccnt=1
while [ $ccnt -lt $cnt ]
do
	subject=`openssl x509 -noout -in $ccnt.root -subject | awk -F/ '{print $NF}' |cut -d= -f2`
	keytool -import -trustcacerts -alias "$subject" -file /etc/apache2/ssl/${ccnt}.root -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>/dev/null
	files="`echo $files` /etc/apache2/ssl/${ccnt}.root"
	ccnt=`expr $ccnt + 1`
done

echo "Generating SSL key and certificate request"
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr -config ${Spath}/files/openssl.cnf -subj "/CN=${idpfqdn}/O=${certOrg}/C=${certC}"


# prepare config from templates
cat ${Spath}/xml/server.xml.diff.template | perl -npe "s/Sup3rS3cr37/$pass/" > ${Spath}/xml/server.xml.diff
files="`echo $files` ${Spath}/xml/server.xml.diff"

cat ${Spath}/xml/attribute-resolver.xml.diff.template | perl -npe "s/LdApUrI/$ldapserver/" > ${Spath}/xml/11
cat ${Spath}/xml/11 | perl -npe "s/LdApBaSeDn/$ldapbasedn/" > ${Spath}/xml/12
cat ${Spath}/xml/12 | perl -npe "s/LdApCrEdS/$ldapbinddn/" > ${Spath}/xml/13
cat ${Spath}/xml/13 | perl -npe "s/LdApPaSsWoRd/$ldappass/" > ${Spath}/xml/attribute-resolver.xml.diff
files="`echo $files` ${Spath}/xml/11"
files="`echo $files` ${Spath}/xml/12"
files="`echo $files` ${Spath}/xml/13"
files="`echo $files` ${Spath}/xml/attribute-resolver.xml.diff"

if [ "$type" = "cas" ]
then
	cat ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff.template | perl -npe "s#IdPuRl#$idpurl#" > ${Spath}/${prep}/21
	cat ${Spath}/${prep}/21 | perl -npe "s#CaSuRl#$caslogurl#" > ${Spath}/${prep}/22
	cat ${Spath}/${prep}/22 | perl -npe "s#CaS2uRl#$casurl#" > ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff
	files="`echo $files` ${Spath}/${prep}/21"
	files="`echo $files` ${Spath}/${prep}/22"
	files="`echo $files` ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff"

	patch /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/web.xml -i ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff
fi
if [ "$type" = "ldap" ]
then
	cat ${Spath}/${prep}/login-config.xml.diff.template | perl -npe "s#LdApUrI#$ldapserver#" > ${Spath}/${prep}/21
	cat ${Spath}/${prep}/21 | perl -npe "s/LdApBaSeDn/$ldapbasedn/" > ${Spath}/${prep}/22
	cat ${Spath}/${prep}/22 | perl -npe "s/SuBsEaRcH/$subsearch/" > ${Spath}/${prep}/login-config.xml.diff
	files="`echo $files` ${Spath}/${prep}/21"
	files="`echo $files` ${Spath}/${prep}/22"
	files="`echo $files` ${Spath}/${prep}/login-config.xml.diff"
fi


# run shibboleth installer
cd /opt/shibboleth-identityprovider
echo ""
echo ""
echo ""
echo "Shibboleth install values:"
echo "Install to: /opt/shibboleth-idp"
echo "Server name: ${idpfqdn}"
echo "Use this password for the key store: ${pass}"
echo ""
echo ""
sh install.sh

# link war-file into the jboss
ln -s /opt/shibboleth-idp/war/idp.war /opt/jboss/server/default/deploy/
cp ${Spath}/files/md-signer.crt /opt/shibboleth-idp/credentials

# patch config files
echo "Patching config files"
cp /etc/apache2/sites-enabled/000-default /etc/apache2/sites-enabled/000-default.dist
cat ${Spath}/xml/apache2-000-default.add >> /etc/apache2/sites-enabled/000-default
patch /opt/shibboleth-idp/conf/handler.xml -i ${Spath}/${prep}/handler.xml.diff
patch /opt/shibboleth-idp/conf/relying-party.xml -i ${Spath}/xml/relying-party.xml.diff
patch /opt/shibboleth-idp/conf/attribute-filter.xml -i ${Spath}/xml/attribute-filter.xml.diff
patch /opt/shibboleth-idp/conf/attribute-resolver.xml -i ${Spath}/xml/attribute-resolver.xml.diff
patch /opt/jboss/server/default/deploy/jbossweb.sar/server.xml -i ${Spath}/xml/server.xml.diff
chmod o-rwx /opt/jboss/server/default/deploy/jbossweb.sar/server.xml

if [ "$type" = "ldap" ]
then
	patch /opt/jboss/server/default/conf/login-config.xml -i ${Spath}/${prep}/login-config.xml.diff
fi

if [ "$google" != "n" ]
then
	patch /opt/shibboleth-idp/conf/attribute-filter.xml -i ${Spath}/xml/google-filter.diff
	patch /opt/shibboleth-idp/conf/attribute-resolver.xml -i ${Spath}/xml/google-resolver.diff
	cat ${Spath}/xml/google-relay.diff.template | perl -npe "s/IdPfQdN/$idpfqdn/" > ${Spath}/xml/google-relay.diff
	files="`echo $files` ${Spath}/xml/google-relay.diff"
	patch /opt/shibboleth-idp/conf/relying-party.xml -i ${Spath}/xml/google-relay.diff
	cat ${Spath}/xml/google.xml | perl -npe "s/GoOgLeDoMaIn/$googleDom/" > /opt/shibboleth-idp/metadata/google.xml
fi

# enable apache modules required
echo "Enable apache modules"
a2enmod ssl
a2enmod proxy
a2enmod proxy_ajp

# install basic startup script for jboss
echo "Add basic jboss init script to start on boot"
cp ${Spath}/files/jboss /etc/init.d/
update-rc.d jboss defaults


# add crontab entry for ntpdate
echo "Adding crontab entry for ntpdate"
CRONTAB=`crontab -l | perl -npe 's/^$//'`
echo "$CRONTAB\n*/5 *  *   *   *     /usr/sbin/ntpdate $ntpserver > /dev/null 2>&1" | crontab


if [ $cleanUp -eq 1 ]
then
# remove configs with templates
	for i in $files
	do
		rm $i
	done
else
	echo "Files created by script"
	for i in $files
	do
		echo $i
	done
fi

echo ""
echo ""
echo ""
cat /etc/apache2/ssl/server.csr
echo "Here is the certificate request, go get at cert!"
echo "Or replace the cert files in /etc/apache2/ssl"
echo "For a self signed certificate run the following as root:"
echo "     openssl x509 -req -days 365 -in /etc/apache2/ssl/server.csr -signkey /etc/apache2/ssl/server.key -out /etc/apache2/ssl/server.crt"
echo "After the cert is in place (/etc/apache2/ssl/server.crt), reboot host and check if it works."
echo ""
echo "Register at testshib.org and register idp, and run a logon test."
echo "Certificate for testshib is in the file: /opt/shibboleth-idp/credentials/idp.crt"
if [ "$type" = "ldap" ]
then
	echo ""
	echo "Read this to customize the logon page: https://wiki.shibboleth.net/confluence/display/SHIB2/IdPAuthUserPassLoginPage"
fi
