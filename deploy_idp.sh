#!/bin/sh
# UTF-8
HELP="
##############################################################################
# Shibboleth deployment script by Anders Lördal                              #
# Högskolan i Gävle and SWAMID                                               #
#                                                                            #
# Version 2.0                                                                #
#                                                                            #
# Deploys a working IDP for SWAMID on an Ubuntu system                       #
# Uses: jboss-as-distribution-6.1.0.Final or tomcat6                         #
#       shibboleth-identityprovider-2.4.0                                    #
#       cas-client-3.2.1-release                                             #
#       mysql-connector-java-5.1.24 (for EPTID)                              #
#                                                                            #
# Templates are provided for CAS and LDAP authentication                     #
#                                                                            #
# To disable the whiptail gui run with argument '-c'                         #
# To keep generated files run with argument '-k'                             #
#    NOTE! some of theese files WILL contain cleartext passwords.            #
#                                                                            #
# To add a new template for another authentication, just add a new directory #
# under the 'prep' directory, add the neccesary .diff files and add any      #
# special hanlding of those files to the script.                             #
#                                                                            #
# You can pre-set configuration values in the file 'config'                  #
#                                                                            #
# Please send questions and improvements to: anders.lordal@hig.se            #
##############################################################################
"
mdSignerFinger="12:60:D7:09:6A:D9:C1:43:AD:31:88:14:3C:A8:C4:B7:33:8A:4F:CB"

# Set cleanUp to 0 (zero) for debugging of created files
cleanUp=1
# Default enable of whiptail UI
GUIen=y
# Version of shibboleth IDP
shibVer="2.4.0"

# Default values
upgrade=0
Spath="$(cd "$(dirname "$0")" && pwd)"
files=""
ts=`date "+%s"`
whiptailBin=`which whiptail`
whipSize="13 75"
certpath="/opt/shibboleth-idp/ssl/"
httpsP12="/opt/shibboleth-idp/credentials/https.p12"
certREQ="${certpath}tomcat.req"
FQDN=`hostname`
FQDN=`host -t A ${FQDN} | awk '{print $1}'`
Dname=`echo ${FQDN} | cut -d\. -f2-`
if [ "${FQDN}" = "Host" ]
then
	myInterface=`netstat -nr |grep "^0.0.0.0" |awk '{print $NF}'`
	myIP=`ip addr list ${myInterface} |grep "inet " |cut -d' ' -f6|cut -d/ -f1`
	Dname=`host -t A ${myIP} | awk '{print $NF}' | cut -d\. -f2- | sed 's/\.$//'`
	FQDN=`host -t A ${myIP} | awk '{print $NF}' | sed 's/\.$//'`
fi
passGenCmd="openssl rand -base64 20"
messages="${Spath}/msg.txt"
statusFile="${Spath}/status.log"
echo "" > ${statusFile}
bupFile="/opt/backup-shibboleth-idp.${ts}.tar.gz"
idpPath="/opt/shibboleth-idp/"
certificateChain="http://webkonto.hig.se/chain.pem"
tomcatDepend="https://build.shibboleth.net/nexus/content/repositories/releases/edu/internet2/middleware/security/tomcat6/tomcat6-dta-ssl/1.0.0/tomcat6-dta-ssl-1.0.0.jar"
dist=""
distCmdU=""
distCmd1=""
distCmd2=""
distCmd3=""
distCmd4=""
distCmd5=""
fetchCmd="curl --silent -k --output"
shibbURL="http://shibboleth.net/downloads/identity-provider/${shibVer}/shibboleth-identityprovider-${shibVer}-bin.zip"
casClientURL="http://downloads.jasig.org/cas-clients/cas-client-3.2.1-release.zip"

if [ ! -x "${whiptailBin}" ]
then
	GUIen="n"
fi

# parse options
options=$(getopt -o ckh -l "help" -- "$@")
eval set -- "${options}"
while [ $# -gt 0 ]
do
	case "$1" in
		-c)
			GUIen="n"
		;;
		-k)
			cleanUp="0"
		;;
		-h | --help)
			printf "%s\n" "${HELP}"
			exit
		;;
	esac
	shift
done

# guess linux dist
lsbBin=`which lsb_release`
if [ -x "${lsbBin}" ]
then
	dist=`lsb_release -i 2>/dev/null |cut -d':' -f2 | perl -npe 's/^\s+//g'`
	if [ ! -z "`echo ${dist} |grep -i 'ubuntu' |grep -v 'grep'`" ]
	then
		dist="ubuntu"
	elif [ ! -z "`echo ${dist} |grep -i 'redhat' |grep -v 'grep'`" ]
	then
		dist="redhat"
	fi
else
	if [ -s "/etc/centos-release" -o -s "/etc/redhat-release" ]
	then
		dist="redhat"
	fi
fi

# define commands
ubuntuCmdU="apt-get -qq update"
ubuntuCmd1="apt-get -y install patch unzip curl >> ${statusFile} 2>&1"
ubuntuCmd2="apt-get -y install git-core maven2 openjdk-6-jdk >> ${statusFile} 2>&1"
ubuntuCmd3="apt-get -y install default-jre >> ${statusFile} 2>&1"
ubuntuCmd4="apt-get -y install tomcat6 >> ${statusFile} 2>&1"
ubuntuCmd5="apt-get -y install mysql-server >> ${statusFile} 2>&1"
redhatCmdU="yum -q -y update"
redhatCmd1="yum -y install patch unzip curl"
redhatCmd2="yum -y install git-core"
redhatCmd3=""
redhatCmd4=""
redhatCmd5="yum -y install mysql-server"

if [ ${dist} = "ubuntu" ]
then
	distCmdU=${ubuntuCmdU}
	distCmd1=${ubuntuCmd1}
	distCmd2=${ubuntuCmd2}
	distCmd3=${ubuntuCmd3}
	distCmd4=${ubuntuCmd4}
	distCmd5=${ubuntuCmd5}
elif [ ${dist} -eq "redhat" ]
then
	Rmsg="Red Hat and CentOS ship with the GNU Java compiler and VM by default. These are not usable with Shibboleth so you must install another JVM. The Sun HotSpot VM is the most commonly used. On recent versions of these distros, you can also install a compatible version of OpenJDK 1.6 using yum. To find the appropriate package name, run yum makecache && yum search openjdk. You will also need to ensure that Tomcat is using OpenJDK rather than the GNU tools."
	if [ "${GUIen}" = "y" ]
	then
		${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Redhat/Centos" --defaultno --yesno --clear -- \
			"$Rmsg" ${whipSize} 3>&1 1>&2 2>&3
		continueFNum=$?
		continueF="n"
		if [ "${continueFNum}" -eq 0 ]
		then
			continueF="y"
		fi
	else
		echo $Rmsg
		echo "Make sure Maven2 is installed! Continue script [ y | N ]?"
		read continueF
		echo ""
	fi

	if [ "${continueF}" != "y" ]
	then
		cleanBadInstall
		exit
	fi

	distCmdU=${redhatCmdU}
	distCmd1=${redhatCmd1}
	distCmd2=${redhatCmd2}
	distCmd3=${redhatCmd3}
	distCmd4=${redhatCmd4}
	distCmd5=${redhatCmd5}
fi

if [ "${USERNAME}" != "root" ]
then
	echo "Run as root!"
	exit
fi

# cleanup function
cleanBadInstall() {
	if [ -d "/opt/shibboleth-identityprovider" ]
	then
		rm -rf /opt/shibboleth-identityprovider*
	fi
	if [ -L "/opt/jboss" ]
	then
		rm -rf /opt/jboss*
	fi
	if [ -d "/opt/cas-client-3.2.1" ]
	then
		rm -rf /opt/cas-client-3.2.1
	fi
	if [ -d "/opt/ndn-shib-fticks" ]
	then
		rm -rf /opt/ndn-shib-fticks
	fi
	if [ -d "/opt/shibboleth-idp" ]
	then
		rm -rf /opt/shibboleth-idp
	fi
	if [ -d "/opt/mysql-connector-java-5.1.24" ]
	then
		rm -rf /opt/mysql-connector-java-5.1.24
	fi
	if [ -f "/usr/share/tomcat6/lib/tomcat6-dta-ssl-1.0.0.jar" ]
	then
		rm /usr/share/tomcat6/lib/tomcat6-dta-ssl-1.0.0.jar
	fi
}

# find java home
setJavaHome () {
	javaBin=`which java`
	if [ -z "${JAVA_HOME}" ]
	then
		# check java
		if [ -L "${javaBin}" ]
		then
			export JAVA_HOME=`readlink -f ${javaBin} | awk -F'bin' '{print $1}'`
		else
			if [ -s "${javaBin}" ]
			then
				export JAVA_HOME=`${javaBin} -classpath ${Spath}/files/ getJavaHome`
			else
				echo "No java found, please install JRE"
				exit 1
			fi
		fi
		if [ -z "`grep 'JAVA_HOME' /root/.bashrc`" ]
		then
			echo "export JAVA_HOME=${JAVA_HOME}" >> /root/.bashrc
		fi
	fi
}

# read config file
if [ -f "${Spath}/config" ]
then
	. ${Spath}/config
fi
prep="prep/${type}"

# check for installed IDP
if [ -L "/opt/shibboleth-identityprovider" -a -d "/opt/shibboleth-idp" ]
then
	upgrade=1
fi

# get data from user for a new install
if [ "${upgrade}" -eq 0 ]
then
	if [ -z "${appserv}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			appserv=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Application server" --nocancel --menu --clear  -- "Which application server do you want to use?" ${whipSize} 2 \
				tomcat "Apache Tomcat 6" jboss "Jboss Application server 6" 3>&1 1>&2 2>&3)
		else
			echo "Application server [ tomcat | jboss ]"
			read appserv
			echo ""
		fi
	fi

	if [ -z "${type}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			tList="${whiptailBin} --backtitle \"SWAMID IDP Deployer\" --title \"Authentication type\" --nocancel --menu --clear -- \"Which authentication type do you want to use?\" ${whipSize} 2"
			for i in `ls ${Spath}/prep | perl -npe 's/\n/\ /g'`
			do
				tDesc=`cat ${Spath}/prep/${i}/.desc`
				tList="`echo ${tList}` \"${i}\" \"${tDesc}\""
			done
			type=$(eval "${tList} 3>&1 1>&2 2>&3")
		else
			echo "Authentication [ `ls ${Spath}/prep |grep -v common | perl -npe 's/\n/\ /g'`]"
			read type
			echo ""
		fi
	fi
	prep="prep/${type}"

	if [ -z "${google}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Attributes to Google" --yesno --clear -- \
				"Do you want to release attributes to google?\n\nSwamid, Swamid-test and testshib.org installed as standard" ${whipSize} 3>&1 1>&2 2>&3
			googleNum=$?
			google="n"
			if [ "${googleNum}" -eq 0 ]
			then
				google="y"
			fi
		else
			echo "Release attributes to Google? [Y/n]: (Swamid, Swamid-test and testshib.org installed as standard)"
			read google
			echo ""
		fi
	fi

	while [ "${google}" != "n" -a -z "${googleDom}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			googleDom=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Your Google domain name" --nocancel --inputbox --clear -- \
				"Please input your Google domain name (student.xxx.yy)." ${whipSize} "student.${Dname}" 3>&1 1>&2 2>&3)
		else
			echo "Your Google domain name: (student.xxx.yy)"
			read googleDom
			echo ""
		fi
	done

	while [ -z "${ntpserver}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ntpserver=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "NTP server" --nocancel --inputbox --clear -- \
				"Please input your NTP server address." ${whipSize} "ntp.${Dname}" 3>&1 1>&2 2>&3)
		else
			echo "Specify NTP server:"
			read ntpserver
			echo ""
		fi
	done

	while [ -z "${ldapserver}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ldapserver=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "LDAP server" --nocancel --inputbox --clear -- \
				"Please input yout LDAP server(s) (ldap.xxx.yy).\n\nSeparate multiple servers with spaces.\nLDAPS is used by default." ${whipSize} "ldap.${Dname}" 3>&1 1>&2 2>&3)
		else
			echo "Specify LDAP URL: (ldap.xxx.yy) (seperate servers with space). LDAPS is used by default."
			read ldapserver
			echo ""
		fi
	done

	while [ -z "${ldapbasedn}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ldapbasedn=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "LDAP Base DN" --nocancel --inputbox --clear -- \
				"Please input your LDAP Base DN" ${whipSize} 3>&1 1>&2 2>&3)
		else
			echo "Specify LDAP Base DN:"
			read ldapbasedn
			echo ""
		fi
	done

	while [ -z "${ldapbinddn}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ldapbinddn=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "LDAP Bind DN" --nocancel --inputbox --clear -- \
				"Please input your LDAP Bind DN" ${whipSize} 3>&1 1>&2 2>&3)
		else
			echo "Specify LDAP Bind DN:"
			read ldapbinddn
			echo ""
		fi
	done

	while [ -z "${ldappass}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ldappass=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "LDAP Password" --nocancel --passwordbox --clear -- \
				"Please input your LDAP Password:" ${whipSize} 3>&1 1>&2 2>&3)
		else
			echo "Specify LDAP Password:"
			read ldappass
			echo ""
		fi
	done

	while [ "${type}" = "ldap" -a -z "${subsearch}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "LDAP Subsearch" --nocancel --yesno --clear -- \
				"Do you want to enable LDAP subtree search?" ${whipSize} 3>&1 1>&2 2>&3
			subsearchNum=$?
			subsearch="false"
			if [ "${subsearchNum}" -eq 0 ]
			then
				subsearch="true"
			fi
		else
			echo "LDAP Subsearch: [ true | false ]"
			read subsearch
			echo ""
		fi
	done

	while [ -z "${ninc}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			ninc=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "norEduPersonNIN" --nocancel --inputbox --clear -- \
				"Please specify LDAP attribute for norEduPersonNIN (YYYYMMDDnnnn)." ${whipSize} "norEduPersonNIN" 3>&1 1>&2 2>&3)
		else
			echo "LDAP attribute for norEduPersonNIN (YYYYMMDDnnnn)? (empty string for 'norEduPersonNIN')"
			read ninc
			echo ""
			if [ -z "${ninc}" ]
			then
				ninc="norEduPersonNIN"
			fi
		fi
	done

	while [ -z "${idpurl}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			idpurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "IDP URL" --nocancel --inputbox --clear -- \
				"Please input the URL to this IDP (https://idp.xxx.yy)." ${whipSize} "https://${FQDN}" 3>&1 1>&2 2>&3)
		else
			echo "Specify IDP URL: (https://idp.xxx.yy)"
			read idpurl
			echo ""
		fi
	done

	if [ "${type}" = "cas" ]
	then
		while [ -z "${casurl}" ]
		do
			if [ "${GUIen}" = "y" ]
			then
				casurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "" --nocancel --inputbox --clear -- \
					"Please input the URL to yourCAS server (https://cas.xxx.yy/cas)." ${whipSize} "https://cas.${Dname}/cas" 3>&1 1>&2 2>&3)
			else
				echo "Specify CAS URL server: (https://cas.xxx.yy/cas)"
				read casurl
				echo ""
			fi
		done

		while [ -z "${caslogurl}" ]
		do
			if [ "${GUIen}" = "y" ]
			then
				caslogurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "" --nocancel --inputbox --clear -- \
					"Please input the Login URL to your CAS server (https://cas.xxx.yy/cas/login)." ${whipSize} "${casurl}/login" 3>&1 1>&2 2>&3)
			else
				echo "Specify CAS Login URL server: (https://cas.xxx.yy/cas/login)"
				read caslogurl
				echo ""
			fi
		done
	fi

	while [ -z "${certOrg}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			certOrg=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Certificate organisation" --nocancel --inputbox --clear -- \
				"Please input organisation name string for certificate request" ${whipSize} 3>&1 1>&2 2>&3)
		else
			echo "Organisation name string for certificate request:"
			read certOrg
			echo ""
		fi
	done

	while [ -z "${certC}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			certC=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Certificate country" --nocancel --inputbox --clear -- \
				"Please input country string for certificate request." ${whipSize} 'SE' 3>&1 1>&2 2>&3)
		else
			echo "Country string for certificate request: (empty string for 'SE')"
			read certC
			echo ""
			if [ -z "${certC}" ]
			then
				certC="SE"
			fi
		fi
	done

	while [ -z "${certAcro}" ]
	do
		acro=""
		for i in ${certOrg}
		do
			t=`echo ${i} | cut -c1`
			acro="${acro}${t}"
		done
		if [ "${GUIen}" = "y" ]
		then
			certAcro=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Organisation acronym" --nocancel --inputbox --clear -- \
				"Please input organisation Acronym (eg. 'HiG')" ${whipSize} "${acro}" 3>&1 1>&2 2>&3)
		else
			echo "norEduOrgAcronym: (eg. 'HiG')"
			read certAcro
			echo ""
		fi
	done

	while [ -z "${certLongC}" ]
	do
		if [ "${GUIen}" = "y" ]
		then
			certLongC=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Country descriptor" --nocancel --inputbox --clear -- \
				"Please input country descriptor (eg. 'Sweden')" ${whipSize} 'Sweden' 3>&1 1>&2 2>&3)
		else
			echo "Country descriptor (eg. 'Sweden')"
			read certLongC
			echo ""
		fi
	done

	if [ -z "${fticks}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Send anonymous data" --yesno --clear -- \
				"Do you want to send anonymous usage data to SWAMID?\nThis is recommended." ${whipSize} 3>&1 1>&2 2>&3
			fticsNum=$?
			fticks="n"
			if [ "${fticsNum}" -eq 0 ]
			then
				fticks="y"
			fi
		else
			echo "Send anonymous usage data to SWAMID [ y | n ]?"
			read fticks
			echo ""
		fi
	fi
	if [ "${fticks}" != "n" -a ${dist} = "redhat" -a ! -s "`which mvn`" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Maven2" --defaultno --yesno --clear -- \
				"Make sure Maven2 is installed?\nContinue?" ${whipSize} 3>&1 1>&2 2>&3
			continueFNum=$?
			continueF="n"
			if [ "${continueFNum}" -eq 0 ]
			then
				continueF="y"
			fi
		else
			echo "Make sure Maven2 is installed! Continue script [ y | n ]?"
			read continueF
			echo ""
		fi

		if [ "${continueF}" = "n" ]
		then
			cleanBadInstall
			exit
		fi
	fi

	if [ -z "${eptid}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "eduPersonTargetedID" --yesno --clear -- \
				"Do you want to install support for eduPersonTargetedID?\nThis is recommended." ${whipSize} 3>&1 1>&2 2>&3
			eptidNum=$?
			eptid="n"
			if [ "${eptidNum}" -eq 0 ]
			then
				eptid="y"
			fi
		else
			echo "Install support for eduPersonTargetedID [ y | n ]"
			read eptid
			echo ""
		fi
	fi

	if [ "${eptid}" != "n" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			mysqlPass=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "MySQL password" --nocancel --passwordbox --clear -- \
				"Please input the root password for MySQL\n\nEmpty string generates new password." ${whipSize} 3>&1 1>&2 2>&3)
		else
			echo "Root password for MySQL (empty string generates new password)?"
			read mysqlPass
			echo ""
		fi
	fi

	if [ -z "${selfsigned}" ]
	then
		if [ "${GUIen}" = "y" ]
		then
			${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Self signed certificate" --defaultno --yesno --clear -- \
				"Create a self signed certificate for HTTPS?\n\nThis is NOT recommended! Only for testing purposes" ${whipSize} 3>&1 1>&2 2>&3
			selfsignedNum=$?
			selfsigned="n"
			if [ "${selfsignedNum}" -eq 0 ]
			then
				selfsigned="y"
			fi
		else
			echo "Create a self signed certificate for https [ y | n ]"
			read selfsigned
			echo ""
		fi
	fi

	if [ "${GUIen}" = "y" ]
	then
		pass=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "IDP keystore password" --nocancel --passwordbox --clear -- \
			"Please input your IDP keystore password\n\nEmpty string generates new password." ${whipSize} 3>&1 1>&2 2>&3)
		httpspass=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "HTTPS Keystore password" --nocancel --passwordbox --clear -- \
			"Please input your Keystore password for HTTPS\n\nEmpty string generates new password." ${whipSize} 3>&1 1>&2 2>&3)
	else
		echo "IDP keystore password (empty string generates new password)"
		read pass
		echo ""
		echo "Keystore password for https (empty string generates new password)"
		read httpspass
		echo ""
	fi

# 	Confirmation
cat > ${Spath}/files/confirm.tx << EOM
Options passed to the installer:


Application server:        ${appserv}
Authentication type:       ${type}

Release to Google:         ${google}
Google domain name:        ${googleDom}

NTP server:                ${ntpserver}

LDAP server:               ${ldapserver}
LDAP Base DN:              ${ldapbasedn}
LDAP Bind DN:              ${ldapbinddn}
LDAP Subsearch:            ${subsearch}
norEduPersonNIN:           ${ninc}

IDP URL:                   ${idpurl}
CAS Login URL:             ${caslogurl}
CAS URL:                   ${casurl}

Cert org string:           ${certOrg}
Cert country string:       ${certC}
norEduOrgAcronym:          ${certAcro}
Country descriptor:        ${certLongC}

Usage data to SWAMID:      ${fticks}
EPTID support:             ${eptid}

Create self seigned cert:  ${selfsigned}
EOM

	cRet="1"
	if [ "${GUIen}" = "y" ]
	then
		${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Save config" --clear --yesno -- "Do you want to save theese config values?\n\nIf you save theese values the current config file will be ovverwritten.\n NOTE: No passwords will be saved." ${whipSize} 3>&1 1>&2 2>&3
		cRet=$?
	else
		cat ${Spath}/files/confirm.tx
		/bin/echo -e  "Do you want to save theese config values?\n\nIf you save theese values the current config file will be ovverwritten.\n NOTE: No passwords will be saved."
		read cAns
		echo ""
		if [ "$cAns" = "y" ]
		then
			cRet="0"
		else
			cRet="1"
		fi
	fi
	if [ "${cRet}" -eq 0 ]
	then
		cat > ${Spath}/config << EOM
appserv="${appserv}"
type="${type}"
google="${google}"
googleDom="${googleDom}"
ntpserver="${ntpserver}"
ldapserver="${ldapserver}"
ldapbasedn="${ldapbasedn}"
ldapbinddn="${ldapbinddn}"
subsearch="${subsearch}"
idpurl="${idpurl}"
caslogurl="${caslogurl}"
casurl="${casurl}"
certOrg="${certOrg}"
certC="${certC}"
fticks="${fticks}"
eptid="${eptid}"
selfsigned="${selfsigned}"
ninc="${ninc}"
certAcro="${certAcro}"
certLongC="${certLongC}"
EOM
	fi
	cRet="1"
	if [ "${GUIen}" = "y" ]
	then
		${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Confirm" --scrolltext --clear --textbox ${Spath}/files/confirm.tx 20 75 3>&1 1>&2 2>&3
		${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Confirm" --clear --yesno --defaultno -- "Do you want to install this IDP with theese options?" ${whipSize} 3>&1 1>&2 2>&3
		cRet=$?
	else
		cat ${Spath}/files/confirm.tx
		echo "Do you want to install this IDP with theese options [ y | n ]?"
		read cAns
		echo ""
		if [ "$cAns" = "y" ]
		then
			cRet="0"
		fi
	fi
	rm ${Spath}/files/confirm.tx
	if [ "${cRet}" -ge 1 ]
	then
		exit
	fi
fi

certCN=`echo ${idpurl} | cut -d/ -f3`

/bin/echo -e "\n\n\n"
echo "Starting deployment!"
if [ "${upgrade}" -eq 1 ]
then
	echo "Previous installation found, performing upgrade."

	eval ${distCmd1}
	cd /opt
	currentShib=`ls -l /opt/shibboleth-identityprovider |awk '{print $NF}'`
	currentVer=`echo ${currentShib} |awk -F\- '{print $NF}'`
	if [ "${currentVer}" = "${shibVer}" ]
	then
		mv ${currentShib} ${currentShib}.${ts}
	fi

	if [ ! -f "${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip" ]
	then
		echo "Shibboleth not found, fetching from web"
		${fetchCmd} ${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip ${shibbURL}
	fi
	unzip -q ${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip
	chmod -R 755 /opt/shibboleth-identityprovider-${shibVer}

	unlink /opt/shibboleth-identityprovider
	ln -s /opt/shibboleth-identityprovider-${shibVer} /opt/shibboleth-identityprovider

	if [ -d "/opt/cas-client-3.2.1" ]
	then
		while [ -z "${idpurl}" ]
		do
			if [ "${GUIen}" = "y" ]
			then
				idpurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "IDP URL" --nocancel --inputbox --clear -- \
				"Please input the URL to this IDP (https://idp.xxx.yy)." ${whipSize} "https://${FQDN}" 3>&1 1>&2 2>&3)
			else
				echo "Specify IDP URL: (https://idp.xxx.yy)"
				read idpurl
				echo ""
			fi
		done

		while [ -z "${casurl}" ]
		do
			if [ "${GUIen}" = "y" ]
			then
				casurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "" --nocancel --inputbox --clear -- \
					"Please input the URL to yourCAS server (https://cas.xxx.yy/cas)." ${whipSize} "https://cas.${Dname}/cas" 3>&1 1>&2 2>&3)
			else
				echo "Specify CAS URL server: (https://cas.xxx.yy/cas)"
				read casurl
				echo ""
			fi
		done

		while [ -z "${caslogurl}" ]
		do
			if [ "${GUIen}" = "y" ]
			then
				caslogurl=$(${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "" --nocancel --inputbox --clear -- \
					"Please input the Login URL to your CAS server (https://cas.xxx.yy/cas/login)." ${whipSize} "${casurl}/login" 3>&1 1>&2 2>&3)
			else
				echo "Specify CAS Login URL server: (https://cas.xxx.yy/cas/login)"
				read caslogurl
				echo ""
			fi
		done

		cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/lib/
		cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/lib/
		mkdir /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
		cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
		cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib

		prep="prep/${type}"
		cat ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff.template \
			| perl -npe "s#IdPuRl#${idpurl}#" \
			| perl -npe "s#CaSuRl#${caslogurl}#" \
			| perl -npe "s#CaS2uRl#${casurl}#" \
			> ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff
		files="`echo ${files}` ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff"

		patch /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/web.xml -i ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff >> ${statusFile} 2>&1
	fi

	if [ -d "/opt/ndn-shib-fticks" ]
	then
		if [ -z "`ls /opt/ndn-shib-fticks/target/*.jar`" ]
		then
			cd /opt/ndn-shib-fticks
			mvn >> ${statusFile} 2>&1
		fi
		cp /opt/ndn-shib-fticks/target/*.jar /opt/shibboleth-identityprovider/lib
	else
		${whiptailBin} --backtitle "SWAMID IDP Deployer" --title "Send anonymous data" --yesno --clear -- \
			"Do you want to send anonymous usage data to SWAMID?\nThis is recommended." ${whipSize} 3>&1 1>&2 2>&3
		fticsNum=$?
		fticks="n"
		if [ "${fticsNum}" -eq 0 ]
		then
			fticks="y"
		fi

		if [ "${fticks}" != "n" ]
		then
			echo "Installing ndn-shib-fticks"
			eval ${distCmd2}
			cd /opt
			git clone git://github.com/leifj/ndn-shib-fticks.git >> ${statusFile} 2>&1
			cd ndn-shib-fticks
			mvn >> ${statusFile} 2>&1
			cp /opt/ndn-shib-fticks/target/*.jar /opt/shibboleth-identityprovider/lib
		fi
	fi

	if [ -d "/opt/mysql-connector-java-5.1.24/" ]
	then
		cp /opt/mysql-connector-java-5.1.24/mysql-connector-java-5.1.24-bin.jar /opt/shibboleth-identityprovider/lib/
	fi

	cd /opt
	tar zcf ${bupFile} shibboleth-idp

	cp /opt/shibboleth-idp/metadata/idp-metadata.xml /opt/shibboleth-identityprovider/src/main/webapp/metadata.xml

	setJavaHome
	cd /opt/shibboleth-identityprovider
	/bin/echo -e "\n\n\n\nRunning shiboleth installer"
	sh install.sh -Dinstall.config=no -Didp.home.input="/opt/shibboleth-idp" >> ${statusFile} 2>&1

else

# 	install depends
	echo "Updating repositories and installing generic dependancies"
	eval ${distCmdU}
	eval ${distCmd1}

	# install java if needed
	javaBin=`which java`
	if [ ! -s "${javaBin}" ]
	then
		eval ${distCmd3}
		javaBin=`which java`
	fi
	if [ ! -s "${javaBin}" ]
	then
		echo "No java could be found! Install a working JRE and re-run this script."
		cleanBadInstall
		exit 1
	fi
	setJavaHome
# 	set path to ca cert file
	if [ -f "/etc/ssl/certs/java/cacerts" ]
	then
		javaCAcerts="/etc/ssl/certs/java/cacerts"
	else
		javaCAcerts="${JAVA_HOME}/lib/security/cacerts"
	fi


# 	generate keystore pass
	if [ -z "${pass}" ]
	then
		pass=`${passGenCmd}`
	fi
	if [ -z "${httpspass}" ]
	then
		httpspass=`${passGenCmd}`
	fi
	if [ -z "${mysqlPass}" ]
	then
		mysqlPass=`${passGenCmd}`
		/bin/echo -e "Mysql root password generated\nPassword is '${mysqlPass}'" >> ${messages}
	fi

	cd /opt
# 	get depens if needed
	if [ "${appserv}" = "jboss" ]
	then
		if [ ! -f "${Spath}/files/jboss-as-distribution-6.1.0.Final.zip" ]
		then
			echo "Jboss not found, fetching from web"
			${fetchCmd} ${Spath}/files/jboss-as-distribution-6.1.0.Final.zip http://download.jboss.org/jbossas/6.1/jboss-as-distribution-6.1.0.Final.zip
		fi
		unzip -q ${Spath}/files/jboss-as-distribution-6.1.0.Final.zip
		chmod 755 jboss-6.1.0.Final
		ln -s /opt/jboss-6.1.0.Final /opt/jboss
	fi

	if [ "${appserv}" = "tomcat" ]
	then
		test=`dpkg -s tomcat6 > /dev/null 2>&1`
		isInstalled=$?
		if [ "${isInstalled}" -ne 0 ]
		then
			eval ${distCmd4}
		fi
	fi

	if [ ! -f "${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip" ]
	then
		echo "Shibboleth not found, fetching from web"
		${fetchCmd} ${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip ${shibbURL}
	fi

	if [ "${type}" = "cas" ]
	then
		if [ ! -f "${Spath}/files/cas-client-3.2.1-release.zip" ]
		then
			echo "Cas-client not found, fetching from web"
			${fetchCmd} ${Spath}/files/cas-client-3.2.1-release.zip ${casClientURL}
		fi
		unzip -q ${Spath}/files/cas-client-3.2.1-release.zip
		if [ ! -s "/opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar" ]
		then
			echo "Unzip of cas-client failed, check zip file: ${Spath}/files/cas-client-3.2.1-release.zip"
			cleanBadInstall
			exit
		fi
	fi

# 	unzip all files
	echo "Unzipping dependancies"

	unzip -q ${Spath}/files/shibboleth-identityprovider-${shibVer}-bin.zip
	chmod -R 755 /opt/shibboleth-identityprovider-${shibVer}
	ln -s shibboleth-identityprovider-${shibVer} shibboleth-identityprovider

	if [ "${type}" = "cas" ]
	then
# 	copy cas depends into shibboleth
		cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/lib/
		cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/lib/
		mkdir /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
		cp /opt/cas-client-3.2.1/modules/cas-client-core-3.2.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib
		cp /opt/cas-client-3.2.1/modules/commons-logging-1.1.jar /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/lib

		cat ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff.template \
			| perl -npe "s#IdPuRl#${idpurl}#" \
			| perl -npe "s#CaSuRl#${caslogurl}#" \
			| perl -npe "s#CaS2uRl#${casurl}#" \
			> ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff
		files="`echo ${files}` ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff"

		patch /opt/shibboleth-identityprovider/src/main/webapp/WEB-INF/web.xml -i ${Spath}/${prep}/shibboleth-identityprovider-web.xml.diff >> ${statusFile} 2>&1
	fi

	if [ "${fticks}" != "n" ]
	then
		echo "Installing ndn-shib-fticks"
		eval ${distCmd2}
		if [ ! -s "`which mvn`" ]
		then
			echo "Maven2 not found! Install Maven2 and re-run this script."
			cleanBadInstall
			exit 1
		fi

		cd /opt
		git clone git://github.com/leifj/ndn-shib-fticks.git >> ${statusFile} 2>&1
		cd ndn-shib-fticks
		mvn >> ${statusFile} 2>&1
		cp /opt/ndn-shib-fticks/target/*.jar /opt/shibboleth-identityprovider/lib
	fi

	if [ "${eptid}" != "n" ]
	then
		echo "Installing EPTID support"
		test=`dpkg -s mysql-server > /dev/null 2>&1`
		isInstalled=$?
		if [ "${isInstalled}" -ne 0 ]
		then
			export DEBIAN_FRONTEND=noninteractive
			eval ${distCmd5}
			
			# set mysql root password
			tfile=`mktemp`
			if [ ! -f "$tfile" ]; then
				return 1
			fi
			cat << EOM > $tfile
USE mysql;
UPDATE user SET password=PASSWORD("${mysqlPass}") WHERE user='root';
FLUSH PRIVILEGES;
EOM

			mysql --no-defaults -u root -h localhost <$tfile
			retval=$?
			rm -f $tfile
			if [ "${retval}" -ne 0 ]
			then
				/bin/echo -e "\n\n\nAn error has occurred in the configuration of the MySQL installation."
				echo "Please correct the MySQL installation and make sure a root password is set and it is possible to log in using the 'mysql' command."
				echo "When MySQL is working, re-run this script."
				cleanBadInstall
				exit 1
			fi
		fi

		${fetchCmd} ${Spath}/files/mysql-connector-java-5.1.24.tar.gz http://ftp.sunet.se/pub/unix/databases/relational/mysql/Downloads/Connector-J/mysql-connector-java-5.1.24.tar.gz
		cd /opt
		tar zxf ${Spath}/files/mysql-connector-java-5.1.24.tar.gz >> ${statusFile} 2>&1
		cp /opt/mysql-connector-java-5.1.24/mysql-connector-java-5.1.24-bin.jar /opt/shibboleth-identityprovider/lib/

	fi

# 	prepare config from templates
	cat ${Spath}/xml/server.xml.${appserv} \
		| perl -npe "s#ShIbBKeyPaSs#${pass}#" \
		| perl -npe "s#HtTpSkEyPaSs#${httpspass}#" \
		| perl -npe "s#HtTpSJkS#${httpsP12}#" \
		| perl -npe "s#TrUsTsToRe#${javaCAcerts}#" \
		> ${Spath}/xml/server.xml
	files="`echo ${files}` ${Spath}/xml/server.xml"

	ldapServerStr=""
	for i in `echo ${ldapserver}`
	do
		ldapServerStr="`echo ${ldapServerStr}` ldaps://${i}"
	done
	ldapServerStr=`echo ${ldapServerStr} | perl -npe 's/^\s+//'`
	cat ${Spath}/xml/attribute-resolver.xml.diff.template \
		| perl -npe "s#LdApUrI#${ldapServerStr}#" \
		| perl -npe "s/LdApBaSeDn/${ldapbasedn}/" \
		| perl -npe "s/LdApCrEdS/${ldapbinddn}/" \
		| perl -npe "s/LdApPaSsWoRd/${ldappass}/" \
		| perl -npe "s/NiNcRePlAcE/${ninc}/" \
		| perl -npe "s/CeRtAcRoNyM/${certAcro}/" \
		| perl -npe "s/CeRtOrG/${certOrg}/" \
		| perl -npe "s/CeRtC/${certC}/" \
		| perl -npe "s/CeRtLoNgC/${certLongC}/" \
		> ${Spath}/xml/attribute-resolver.xml.diff
	files="`echo ${files}` ${Spath}/xml/attribute-resolver.xml.diff"

# 	Get TCS CA chain, import ca-certs into java and create https cert request
	mkdir -p ${certpath}
	cd ${certpath}
	echo "Fetching TCS CA chain from web"
	${fetchCmd} ${certpath}/server.chain ${certificateChain}
	if [ ! -s "${certpath}/server.chain" ]
	then
		echo "Can not get the certificate chain, aborting install."
		cleanBadInstall
		exit 1
	fi

	echo "Installing TCS CA chain in java cacert keystore"
	cnt=1
	for i in `cat ${certpath}server.chain | perl -npe 's/\ /\*\*\*/g'`
	do
		n=`echo ${i} | perl -npe 's/\*\*\*/\ /g'`
		echo ${n} >> ${certpath}${cnt}.root
		ltest=`echo ${n} | grep "END CERTIFICATE"`
		if [ ! -z "${ltest}" ]
		then
			cnt=`expr ${cnt} + 1`
		fi
	done
	ccnt=1
	while [ ${ccnt} -lt ${cnt} ]
	do
		md5finger=`keytool -printcert -file ${certpath}${ccnt}.root | grep MD5 | cut -d: -f2- | perl -npe 's/\s+//g'`
		test=`keytool -list -keystore ${javaCAcerts} -storepass changeit | grep ${md5finger}`
		subject=`openssl x509 -subject -noout -in ${certpath}${ccnt}.root | awk -F= '{print $NF}'`
		if [ -z "${test}" ]
		then
			keytool -import -noprompt -trustcacerts -alias "${subject}" -file ${certpath}${ccnt}.root -keystore ${javaCAcerts} -storepass changeit 2>/dev/null
		fi
		files="`echo ${files}` ${certpath}${ccnt}.root"
		ccnt=`expr ${ccnt} + 1`
	done

# 	Fetch certificates from LDAP servers
	lcnt=1
	capture=0
	ldapCert="ldapcert.pem"
	echo "Fetching and installing certificates from LDAP server(s)"
	for i in `echo ${ldapserver}`
	do
		#Get certificate info
		echo "QUIT" |openssl s_client -showcerts -connect ${i}:636 > ${certpath}${i}.raw 2>&1
		files="`echo ${files}` ${certpath}${i}.raw"

		for j in `cat ${certpath}${i}.raw | perl -npe 's/\ /\*\*\*/g'`
		do
			n=`echo ${j} | perl -npe 's/\*\*\*/\ /g'`
			if [ ! -z "`echo ${n} | grep 'BEGIN CERTIFICATE'`" ]
			then
				capture=1
				if [ -s "${certpath}${ldapCert}.${lcnt}" ]
				then
					lcnt=`expr ${lcnt} + 1`
				fi
			fi
			if [ ${capture} = 1 ]
			then
				echo ${n} >> ${certpath}${ldapCert}.${lcnt}
			fi
			if [ ! -z "`echo ${n} | grep 'END CERTIFICATE'`" ]
			then
				capture=0
			fi
		done
	done

	for i in `ls ${certpath}${ldapCert}.*`
	do
		md5finger=`keytool -printcert -file ${i} | grep MD5 | cut -d: -f2- | perl -npe 's/\s+//g'`
		test=`keytool -list -keystore ${javaCAcerts} -storepass changeit | grep ${md5finger}`
		subject=`openssl x509 -subject -noout -in ${i} | awk -F= '{print $NF}'`
		if [ -z "${test}" ]
		then
			keytool -import -noprompt -alias "${subject}" -file ${i} -keystore ${javaCAcerts} -storepass changeit 2>/dev/null
		fi
		files="`echo ${files}` ${i}"
	done

	if [ ! -s "${httpsP12}" ]
	then
		echo "Generating SSL key and certificate request"
		openssl genrsa -out ${certpath}server.key 2048 2>/dev/null
		openssl req -new -key ${certpath}server.key -out ${certREQ} -config ${Spath}/files/openssl.cnf -subj "/CN=${certCN}/O=${certOrg}/C=${certC}"
	fi
	if [ "${selfsigned}" = "n" ]
	then
		echo "Put the certificate from TCS in the file: ${certpath}server.crt" >> ${messages}
		echo "Run: openssl pkcs12 -export -in ${certpath}server.crt -inkey ${certpath}server.key -out ${httpsP12} -name tomcat -passout pass:${httpspass}" >> ${messages}
	else
		openssl x509 -req -days 365 -in ${certREQ} -signkey ${certpath}server.key -out ${certpath}server.crt
		openssl pkcs12 -export -in ${certpath}server.crt -inkey ${certpath}server.key -out ${httpsP12} -name tomcat -passout pass:${httpspass}
	fi

# 	run shibboleth installer
	cd /opt/shibboleth-identityprovider
	/bin/echo -e "Running shiboleth installer"
	sh install.sh -Didp.home.input="/opt/shibboleth-idp" -Didp.hostname.input="${certCN}" -Didp.keystore.pass="${pass}" >> ${statusFile} 2>&1

# 	application server specific
	if [ "${appserv}" = "jboss" ]
	then
		if [ "${type}" = "ldap" ]
		then
			ldapServerStr=""
			for i in `echo ${ldapserver}`
			do
				ldapServerStr="`echo ${ldapServerStr}` ldap://${i}"
			done
			ldapServerStr=`echo ${ldapServerStr} | perl -npe 's/^\s+//'`

			cat ${Spath}/${prep}/login-config.xml.diff.template \
				| perl -npe "s#LdApUrI#${ldapServerStr}#" \
				| perl -npe "s/LdApBaSeDn/${ldapbasedn}/" \
				| perl -npe "s/SuBsEaRcH/${subsearch}/" \
				> ${Spath}/${prep}/login-config.xml.diff
			files="`echo ${files}` ${Spath}/${prep}/login-config.xml.diff"
			patch /opt/jboss/server/default/conf/login-config.xml -i ${Spath}/${prep}/login-config.xml.diff >> ${statusFile} 2>&1
		fi

		ln -s /opt/shibboleth-idp/war/idp.war /opt/jboss/server/default/deploy/

		cp ${Spath}/xml/server.xml /opt/jboss/server/default/deploy/jbossweb.sar/server.xml
		chmod o-rwx /opt/jboss/server/default/deploy/jbossweb.sar/server.xml

		echo "Add basic jboss init script to start on boot"
		cp ${Spath}/files/jboss.init /etc/init.d/jboss
		update-rc.d jboss defaults
	fi

	if [ "${appserv}" = "tomcat" ]
	then
		if [ "${type}" = "ldap" ]
		then
			ldapServerStr=""
			for i in `echo ${ldapserver}`
			do
				ldapServerStr="`echo ${ldapServerStr}` ldap://${i}"
			done
			ldapServerStr="`echo ${ldapServerStr} | perl -npe 's/^\s+//'`"

			cat ${Spath}/${prep}/login.conf.diff.template \
				| perl -npe "s#LdApUrI#${ldapServerStr}#" \
				| perl -npe "s/LdApBaSeDn/${ldapbasedn}/" \
				| perl -npe "s/SuBsEaRcH/${subsearch}/" \
				> ${Spath}/${prep}/login.conf.diff
			files="`echo ${files}` ${Spath}/${prep}/login.conf.diff"
			patch /opt/shibboleth-idp/conf/login.config -i ${Spath}/${prep}/login.conf.diff >> ${statusFile} 2>&1
		fi

		if [ ! -d "/usr/share/tomcat6/endorsed" ]
		then
			mkdir /usr/share/tomcat6/endorsed
		fi
		for i in `ls /opt/shibboleth-identityprovider/endorsed/`
		do
			if [ ! -s "/usr/share/tomcat6/endorsed/${i}" ]
			then
				cp /opt/shibboleth-identityprovider/endorsed/${i} /usr/share/tomcat6/endorsed
			fi
		done

		. /etc/default/tomcat6
		if [ -z "`echo ${JAVA_OPTS} | grep '/usr/share/tomcat6/endorsed'`" ]
		then
			JAVA_OPTS="${JAVA_OPTS} -Djava.endorsed.dirs=/usr/share/tomcat6/endorsed"
			echo "JAVA_OPTS=\"${JAVA_OPTS}\"" >> /etc/default/tomcat6
		else
			echo "JAVA_OPTS for tomcat already configured" >> ${messages}
		fi
		if [ "${AUTHBIND}" != "yes" ]
		then
			echo "AUTHBIND=yes" >> /etc/default/tomcat6
		else
			echo "AUTHBIND for tomcat already configured" >> ${messages}
		fi

		${fetchCmd} /usr/share/tomcat6/lib/tomcat6-dta-ssl-1.0.0.jar ${tomcatDepend}
		if [ ! -s "/usr/share/tomcat6/lib/tomcat6-dta-ssl-1.0.0.jar" ]
		then
			echo "Can not get tomcat dependancy, aborting install."
			cleanBadInstall
			exit 1
		fi

		cp /etc/tomcat6/server.xml /etc/tomcat6/server.xml.${ts}
		cp ${Spath}/xml/server.xml /etc/tomcat6/server.xml
		chmod o-rwx /etc/tomcat6/server.xml

		if [ -d "/var/lib/tomcat6/webapps/ROOT" ]
		then
			mv /var/lib/tomcat6/webapps/ROOT /opt/disabled.tomcat6.webapps.ROOT
		fi

		chown tomcat6 /opt/shibboleth-idp/metadata
		chown -R tomcat6 /opt/shibboleth-idp/logs/

		cp /usr/share/tomcat6/lib/servlet-api.jar /opt/shibboleth-idp/lib/
	fi

	${fetchCmd} ${idpPath}/credentials/md-signer.crt http://md.swamid.se/md/md-signer.crt
	cFinger=`openssl x509 -noout -fingerprint -sha1 -in ${idpPath}/credentials/md-signer.crt | cut -d\= -f2`
	cCnt=1
	while [ "${cFinger}" != "${mdSignerFinger}" -a "${cCnt}" -le 10 ]
	do
		${fetchCmd} ${idpPath}/credentials/md-signer.crt http://md.swamid.se/md/md-signer.crt
		cFinger=`openssl x509 -noout -fingerprint -sha1 -in ${idpPath}/credentials/md-signer.crt | cut -d\= -f2`
		cCnt=`expr ${cCnt} + 1`
	done
	if [ "${cFinger}" != "${mdSignerFinger}" ]
	then
		 echo "Fingerprint error on md-signer.crt!\nGet ther certificate from http://md.swamid.se/md/md-signer.crt and verify it, then place it in the file: ${idpPath}/credentials/md-signer.crt" >> ${messages}
	fi

# 	patch shibboleth config files
	echo "Patching config files"
	mv /opt/shibboleth-idp/conf/attribute-filter.xml /opt/shibboleth-idp/conf/attribute-filter.xml.dist
	cp ${Spath}/files/attribute-filter.xml.swamid /opt/shibboleth-idp/conf/attribute-filter.xml
	patch /opt/shibboleth-idp/conf/handler.xml -i ${Spath}/${prep}/handler.xml.diff >> ${statusFile} 2>&1
	patch /opt/shibboleth-idp/conf/relying-party.xml -i ${Spath}/xml/relying-party.xml.diff >> ${statusFile} 2>&1
	patch /opt/shibboleth-idp/conf/attribute-resolver.xml -i ${Spath}/xml/attribute-resolver.xml.diff >> ${statusFile} 2>&1

	if [ "${google}" != "n" ]
	then
		repStr='<!-- PLACEHOLDER DO NOT REMOVE -->'
		sed -i "/^${repStr}$/{
			r ${Spath}/xml/google-filter.add
			d
			}" /opt/shibboleth-idp/conf/attribute-filter.xml
		cat ${Spath}/xml/google-relay.diff.template | perl -npe "s/IdPfQdN/${FQDN}/" > ${Spath}/xml/google-relay.diff
		files="`echo ${files}` ${Spath}/xml/google-relay.diff"
		patch /opt/shibboleth-idp/conf/relying-party.xml -i ${Spath}/xml/google-relay.diff >> ${statusFile} 2>&1
		cat ${Spath}/xml/google.xml | perl -npe "s/GoOgLeDoMaIn/${googleDom}/" > /opt/shibboleth-idp/metadata/google.xml
	fi

	if [ "${fticks}" != "n" ]
	then
		patch /opt/shibboleth-idp/conf/logging.xml -i ${Spath}/xml/fticks.diff >> ${statusFile} 2>&1
		touch /opt/shibboleth-idp/conf/fticks-key.txt
		if [ "${appserv}" = "tomcat" ]
		then
			chown tomcat6 /opt/shibboleth-idp/conf/fticks-key.txt
		fi
	fi

	if [ "${eptid}" != "n" ]
	then
		epass=`${passGenCmd}`
# 		grant sql access for shibboleth
		esalt=`openssl rand -base64 36 2>/dev/null`
		cat ${Spath}/xml/eptid.sql.template | perl -npe "s#SqLpAsSwOrD#${epass}#" > ${Spath}/xml/eptid.sql
		files="`echo ${files}` ${Spath}/xml/eptid.sql"

		echo "Create MySQL database and shibboleth user."
		mysql -uroot -p"${mysqlPass}" < ${Spath}/xml/eptid.sql
		retval=$?
		if [ "${retval}" -ne 0 ]
		then
			/bin/echo -e "Failed to create EPTID database, take a look in the file '${Spath}/xml/eptid.sql.template' and corect the issue." >> ${messages}
			/bin/echo -e "Password for the database user can be found in: /opt/shibboleth-idp/conf/attribute-resolver.xml" >> ${messages}
		fi
			
		cat ${Spath}/xml/eptid-AR.diff.template \
			| perl -npe "s#SqLpAsSwOrD#${epass}#" \
			| perl -npe "s#Large_Random_Salt_Value#${esalt}#" \
			> ${Spath}/xml/eptid-AR.diff
		files="`echo ${files}` ${Spath}/xml/eptid-AR.diff"

		patch /opt/shibboleth-idp/conf/attribute-resolver.xml -i ${Spath}/xml/eptid-AR.diff >> ${statusFile} 2>&1
		patch /opt/shibboleth-idp/conf/attribute-filter.xml -i ${Spath}/xml/eptid-AF.diff >> ${statusFile} 2>&1
	fi

	echo "Updating time from: ${ntpserver}"
	/usr/sbin/ntpdate ${ntpserver} > /dev/null 2>&1

# 	add crontab entry for ntpdate
	test=`crontab -l 2>/dev/null |grep "${ntpserver}" |grep ntpdate`
	if [ -z "${test}" ]
	then
		echo "Adding crontab entry for ntpdate"
		CRONTAB=`crontab -l 2>/dev/null | perl -npe 's/^$//'`
		if [ ! -z "${CRONTAB}" ]
		then
			CRONTAB="${CRONTAB}\n"
		fi
		/bin/echo -e "${CRONTAB}*/5 *  *   *   *     /usr/sbin/ntpdate ${ntpserver} > /dev/null 2>&1" | crontab
	fi

	if [ "${appserv}" = "tomcat" ]
	then
# 		add idp.war to tomcat
		cp ${Spath}/xml/tomcat.idp.xml /var/lib/tomcat6/conf/Catalina/localhost/idp.xml
	fi
fi

if [ "${appserv}" = "tomcat" ]
then
	service tomcat6 restart
fi

if [ "${cleanUp}" -eq 1 ]
then
# 	remove configs with templates
	for i in ${files}
	do
		rm ${i}
	done
else
	echo "Files created by script"
	for i in ${files}
	do
		echo ${i}
	done
fi

/bin/echo -e "\n\n\n"

if [ "${upgrade}" -eq 1 ]
then
	echo "Upgrade done."
	echo "A backup of the previos shibboleth installation is saved in: ${bupFile}"
else
	if [ "${selfsigned}" = "n" ]
	then
		cat ${certREQ}
		echo "Here is the certificate request, go get at cert!"
		echo "Or replace the cert files in ${certpath}"
		/bin/echo -e "\n\nNOTE!!! the keystore for https is a PKCS12 store\n\n"
	fi
	echo ""
	echo "Register at testshib.org and register idp, and run a logon test."
	echo "Certificate for idp metadata is in the file: /opt/shibboleth-idp/credentials/idp.crt"
fi

if [ "${type}" = "ldap" ]
then
	/bin/echo -e "\n\n"
	echo "Read this to customize the logon page: https://wiki.shibboleth.net/confluence/display/SHIB2/IdPAuthUserPassLoginPage"
fi

if [ -s "${messages}" ]
then
	cat ${messages}
	rm ${messages}
fi
