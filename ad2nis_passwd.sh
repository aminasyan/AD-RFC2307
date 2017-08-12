#! /bin/bash
#
#   The folowing utilities are necessary for the functioning of this script
#          ---  LDAP tools & Kerberos utilities  --
#   This script assumes your have a proper krb5.conf and ldap configured
#   to work with TLS/GSSAPI
#   This script also assumes that kerberos authentication has been established
#   before running this script, also it is assumed the principal has permission
#   to read user attributes from Active Directory
#

USER_BASE='OU=Users,DC=example,DC=com'
DC_SERVER='dc.example.com'
declare -A NIS_LN

LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)(sAMAccountName=*)(uid=*)(uidNumber=*))" uid uidNumber gidNumber displayName unixHomeDirectory loginShell|grep -v "^dn: \|^search: \|^result: \|^$"|sed -e "s/^#.*$/#/g"|tr "\n" "|"|tr "#" "\n"`

if [ -z "$LDAP_QUERY" ]
then
    echo "No user info found"
    exit 0
fi

#echo "$LDAP_QUERY"

OLD_IFS=$IFS
IFS=$'\n'

for USR_LN in `echo "$LDAP_QUERY"|grep -v "^|$"`
do
    USR_FLD=`echo "$USR_LN"|tr "|" "\n"`
    NIS_LN=''
    for ATTR in uid uidNumber gidNumber unixHomeDirectory loginShell
    do
        if [ "$ATTR" = "uid" ]
        then
            NIS_LN=`echo "$USR_FLD"|grep "^$ATTR: "|cut -d " " -f 2-`":x"
        else
            NIS_LN=$NIS_LN":"`echo "$USR_FLD"|grep "^$ATTR: "|cut -d " " -f 2-`
        fi
    done

    echo "$NIS_LN"
done
