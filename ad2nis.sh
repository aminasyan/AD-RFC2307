#! /bin/bash


USER_BASE='OU=Users,DC=example,DC=com'
DC_SERVER='dc01.example.com'
KEYTAB_FILE='/etc/krb5.keytab'

MAP_LIST="passwd group auto.master auto.home"

# Uncomment the line below to enable shadow passwords.
# make sure the host AD account has permission to read "unixUserPassword" attribute, by default access is restricted to Domain Admins.

#MAP_LIST="shadow passwd group auto.master auto.home"
YPMAP_DIR="/var/yp"
YPBKP_DIR="/var/ypbkp"

HOST_NAME=`hostname -s|tr [:lower:] [:upper:]`
AD_DOMAIN=`hostname -d|tr [:lower:] [:upper:]`

# Uncomment the two lines below & configure to disable autotetect of hostname & AD domain

#HOST_NAME='ad-client'
#AD_DOMAIN='example.com'


function ad2nis_passwd
{
    for STATUS in disabled enabled
    do
        if [ "$STATUS" = "disabled" ]
        then
            LD_FILTER='userAccountControl:1.2.840.113556.1.4.803:=2'
            PW_MARK='!!'
        else
            LD_FILTER='!(userAccountControl:1.2.840.113556.1.4.803:=2)'
            PW_MARK='x'
        fi
        LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)($LD_FILTER)(sAMAccountName=*)(uid=*)(uidNumber=*))" uid uidNumber gidNumber displayName unixHomeDirectory loginShell |grep "^#\|^uid: \|^uidNumber: \|^gidNumber: \|^displayName: \|^unixHomeDirectory: \|^loginShell: "|sed -e "s/^#.*$/#/g"`
        if [ "$?" -ne 0 ]
        then
            echo "Error occured in LDAP communication"
            exit 1
        fi
        if [ -n "$LDAP_QUERY" ]
        then
            OLD_IFS=$IFS
            IFS='#'
            for USR_FLD in `echo "$LDAP_QUERY"`
            do
                USR_FLD=`echo "$USR_FLD"|grep -v "^$"`
                if [ -n "$USR_FLD" ]
                then
                    NIS_LN=''
                    for ATTR in uid uidNumber gidNumber displayName unixHomeDirectory loginShell
                    do
                        if [ "$ATTR" = "uid" ]
                        then
                            NIS_LN=`echo "$USR_FLD"|grep "^$ATTR: "|cut -d " " -f 2-`":$PW_MARK"
                        elif [ "$ATTR" = "loginShell" ] && [ "$STAUTS" = "disabled" ]
                        then
                            NIS_LN=$NIS_LN":/bin/false"
                        else
                            NIS_LN=$NIS_LN":"`echo "$USR_FLD"|grep "^$ATTR: "|cut -d " " -f 2-`
                        fi
                    done
                    echo "$NIS_LN"
                fi
            done
            IFS=$OLD_IFS
        fi
    done
}
function ad2nis_group
{
    LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=group)(objectClass=group)(gidNumber=*)(msSFU30Name=*))" dn gidNumber msSFU30Name|grep "^#\|^dn: \|^gidNumber: \|^msSFU30Name: "|sed -e "s/^#.*$/#/g"`
    if [ "$?" -ne 0 ]
    then
        echo "Error occured in LDAP communication"
        exit 1
    fi
    OLD_IFS=$IFS
    IFS='#'
    for LDAP_RECORD in `echo "$LDAP_QUERY"`
    do
        GROUP_DN=`echo $LDAP_RECORD|grep "^dn: "|cut -d " " -f 2-|sed -e 's,[()],\\\&,g'`
        if [ -n "$GROUP_DN" ]
        then
            GROUP_NAME=`echo $LDAP_RECORD|grep "^msSFU30Name: "|cut -d " " -f 2`
            GROUP_ID=`echo $LDAP_RECORD|grep "^gidNumber: "|cut -d " " -f 2`
            MEMBER_LIST=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)(sAMAccountName=*)(uid=*)(uidNumber=*)(memberOf:1.2.840.113556.1.4.1941:=${GROUP_DN}))" uid|grep "^uid: "|cut -d " " -f 2|sort|xargs|tr ' ' ','`
            if [ "$?" -ne 0 ]
            then
                echo "Error occured in LDAP communication"
                exit 1
            fi
            echo "$GROUP_NAME:x:$GROUP_ID:$MEMBER_LIST"
        fi
    done
    IFS=$OLD_IFS
}
function ad2nis_shadow
{
    for STATUS in disabled enabled
    do
        if [ "$STATUS" = "disabled" ]
        then
            LD_FILTER='userAccountControl:1.2.840.113556.1.4.803:=2'
        else
            LD_FILTER='!(userAccountControl:1.2.840.113556.1.4.803:=2)'
        fi
        LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)($LD_FILTER)(sAMAccountName=*)(uid=*)(uidNumber=*))" uid unixUserPassword |grep "^#\|^uid: \|^unixUserPassword: "|sed -e "s/^#.*$/#/g"`
        if [ "$?" -ne 0 ]
        then
            echo "Error occured in LDAP communication"
            exit 1
        fi
        if [ -n "$LDAP_QUERY" ]
        then
            OLD_IFS=$IFS
            IFS='#'
            for USR_FLD in `echo "$LDAP_QUERY"`
            do
                USR_FLD=`echo "$USR_FLD"|grep -v "^$"`
                if [ -n "$USR_FLD" ]
                then
                    NIS_LN=`echo "$USR_FLD"|grep "^uid: "|cut -d " " -f 2-`
                    PW_HASH=`echo "$USR_FLD"|grep "^unixUserPassword: "|cut -d " " -f 2-`
                    if [ -z $PW_HASH ] || [ "$STATUS" = "disabled" ]
                    then
                        NIS_LN=$NIS_LN':!!::0:99999:7:::'
                    else
                        NIS_LN="$NIS_LN:$PW_HASH::0:99999:7:::"
                    fi
                    echo "$NIS_LN"
                fi
            done
            IFS=$OLD_IFS
        fi
    done
}
function ad2nis_automount
{
    if [ "$#" -eq "1" ]
    then

        LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=NisObject)(objectClass=nisObject)(nisMapEntry=*)(nisMapName=$1))" name nisMapEntry |grep "^#\|^name: \|^nisMapEntry: "|sed -e "s/^#.*$/#/g"`
        if [ "$?" -ne 0 ]
        then
            echo "Error occured in LDAP communication"
            exit 1
        fi
        OLD_IFS=$IFS
        IFS='#'
        for MAP_RECORD in `echo "$LDAP_QUERY"`
        do
            MAP_NAME=`echo "$MAP_RECORD"|grep "^name: "|cut -d " " -f 2-`
            MAP_ENTRY=`echo "$MAP_RECORD"|grep "^nisMapEntry: "|cut -d " " -f 2-`
            if [ -n "$MAP_NAME" ]
            then
                echo "$MAP_NAME $MAP_ENTRY"
            fi
        done
        IFS=$OLD_IFS
    fi
}
kdestroy -A
kinit -k -t $KEYTAB_FILE $HOST_NAME'\$@'$AD_DOMAIN
YPMAKE_FLAG=false
for YP_MAP in `echo $MAP_LIST`
do
    YPBKP_FILE="$YPBKP_DIR/$YP_MAP"`date +_%Y-%b-%d_%H-%M.bkp`
    if [ "$YP_MAP" = "passwd" ] || [ "$YP_MAP" = "shadow" ] || [ "$YP_MAP" = "group" ]
    then
        ad2nis_$YP_MAP|sort -n -t ":" -k 3 > $YPBKP_FILE
        if [ "$?" -ne 0 ]
        then
            echo "Error occured in LDAP communication"
            exit 1
        fi

    else
        MAP_CHK=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=NisMap)(objectClass=nisMap)(nisMapName=*))" cn |grep "^cn: $YP_MAP$"`
        if [ "$?" -ne 0 ]
        then
            echo "Error occured in LDAP communication"
            exit 1
        fi
        if [ -n "$MAP_CHK" ]
        then
            ad2nis_automount $YP_MAP|sort > $YPBKP_FILE
            if [ "$?" -ne 0 ]
            then
                echo "Error occured in LDAP communication"
                exit 1
            fi
        fi
    fi
    if [ -f $YPBKP_FILE ]
    then
        YP_DIFF=`diff $YPMAP_DIR/$YP_MAP $YPBKP_FILE`
        if [ -n "$YP_DIFF" ]
        then
            cp $YPBKP_FILE $YPMAP_DIR/$YP_MAP
            YPMAKE_FLAG=true
        else
            rm -f $YPBKP_FILE
        fi
    fi
done
kdestroy -A

if $YPMAKE_FLAG
then
    cd $YPMAP_DIR
    make
fi
