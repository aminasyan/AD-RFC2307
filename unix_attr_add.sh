#! /bin/bash
#
#   The folowing utilities are necessary for the functioning of this script
#          ---  LDAP tools & Kerberos utilities  --
#   This script assumes your have a proper krb5.conf and ldap configured
#   to work with TLS/GSSAPI
#   This script also assumes that kerberos authentication has been established
#   before running this script, also it is assumed the principal has permission
#   to read & modify the neccessary attributes in Active Directory
#
#

USER_BASE='OU=Users,DC=example,DC=com'
DC_SERVER='dc.example.com'
SAM_NAME=$1
UID_NEXT=0
declare -A LDAP_ATTR
declare -A VALID
declare -A DEF_VAL
declare -A DESC
declare -A E_MSG

VALID['uid']='^[a-z0-9]+$'
VALID['uidNumber']='^[0-9]+$'
VALID['gidNumber']='^[0-9]+$'
VALID['unixHomeDirectory']='^[/a-zA-Z0-9]+$'
VALID['loginShell']='^[/a-zA-Z0-9]+$'

DESC['uid']="UNIX username"
DESC['uidNumber']="UNIX uid number"
DESC['gidNumber']="UNIX gid number"
DESC['unixHomeDirectory']="UNIX Home Driectory"                                                                                                   
DESC['loginShell']="UNIX login shell"                                                                                                             
                                                                                                                                                  
E_MSG['uid']="lowercase letters & numbers"                                                                                                        
E_MSG['uidNumber']="number"                                                                                                                       
E_MSG['gidNumber']="number"                                                                                                                       
E_MSG['unixHomeDirectory']="letters, numbers & \"/\" character"                                                                                   
E_MSG['loginShell']="letters, numbers & \"/\" character"                                                                                          
                                                                                                                                                  
DEF_VAL['gidNumber']=100                                                                                                                          
DEF_VAL['loginShell']='/bin/bash'                                                                                                                 
                                                                                                                                                  
                                                                                                                                                  
                                                                                                                                                  
                                                                                                                                                  
LDAP_QUERY=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$SAM_NAME))" dn uid uidNumber gidNumber displayName unixHomeDirectory loginShell|grep "^dn: \|^uid: \|^uidNumber: \|^gidNumber: \|^displayName: \|^unixHomeDirectory: \|^loginShell: "`                                                                                                       
                                                                                                                                                  
if [ -z "$LDAP_QUERY" ]                                                                                                                           
then                                                                                                                                              
    echo "User not found"                                                                                                                         
    exit 0                                                                                                                                        
fi                                                                                                                                                

for ATTR in dn uid uidNumber gidNumber displayName unixHomeDirectory loginShell
do
    LDAP_ATTR[${ATTR}]=`echo "$LDAP_QUERY"|grep "^$ATTR: "|cut -d " " -f 2-`
done

for ATTR in dn uid uidNumber gidNumber displayName unixHomeDirectory loginShell
do
    echo "$ATTR: ${LDAP_ATTR[$ATTR]}"
done

echo
echo "===================================================="
echo

read -p "Verify the user information is correct, enter \"yes\" to continue or \"quit\" to exit: " CONFIRM
if [ "$CONFIRM" != "yes" ]
then
    exit 0
fi

UID_MX=`ldapsearch -o ldif-wrap=no -h $DC_SERVER -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)(uidNumber=*))" "uidNumber"|grep "^uidNumber: "|cut -d " " -f 2|sort -n|tail -n 1`
((DEF_VAL['uidNumber']=UID_MX+1))

ATTR_LIST=''

for ATTR in uid uidNumber gidNumber unixHomeDirectory loginShell
do
    echo
    echo "----------------------------------------------------"
    echo
    if [ -z "${LDAP_ATTR[$ATTR]}" ]
    then
        CONFIRM=''
        until [[ $CONFIRM =~ ${VALID[$ATTR]} ]] && [[ -n $CONFIRM ]]
        do
            PROMPT="LDAP attribute \"$ATTR\" is empty, please input the value for ${DESC[$ATTR]}"$'\n'
            if [ -z "${DEF_VAL[$ATTR]}" ]
            then
                PROMPT="${PROMPT}Please enter the value or \"quit\" to exit: "
            else
                PROMPT="${PROMPT}The default value for \"$ATTR\" is ${DEF_VAL[$ATTR]}, enter \"yes\" to accept, \"quit\" to exit or enter different value: "
            fi
            read -p "$PROMPT" CONFIRM
            case "$CONFIRM" in
            "yes")
                CONFIRM=${DEF_VAL[$ATTR]}
                ;;
            "quit")
                echo "Exiting ...... "
                exit 0
                ;;
            *)
                if [[ $CONFIRM =~ ${VALID[$ATTR]} ]]
                then
                    if [ "$ATTR" = "uid" ] || [ "$ATTR" = "uidNumber" ]
                    then
                        echo "Checking LDAP for conflicts, this may take a while......."
                        LD_TST=`ldapsearch -o ldif-wrap=no -h "$DC_SERVER" -Y GSSAPI -Q -N -b "$USER_BASE" -s sub "(&(objectCategory=person)(objectClass=user)($ATTR=$CONFIRM))" "$ATTR"|grep "^$ATTR: "|cut -d " " -f 2`
                        if [ -n "$LD_TST" ]
                        then
                            echo "The $ATTR: $CONFIRM already exists, please use a different value."
                            CONFIRM=''
                        fi
                    fi
                else
                    echo "Invalid input. The \"$ATTR\" is limited to ${E_MSG[$ATTR]}"
                    CONFIRM=''
                fi
                ;;
            esac
        done
        echo
        echo "Accepted the value of $CONFIRM for \"$ATTR\""
        LDAP_ATTR[$ATTR]=$CONFIRM
        ATTR_LIST="$ATTR_LIST $ATTR"
        if [ -n "${LDAP_ATTR['uid']}" ]
        then
            DEF_VAL['unixHomeDirectory']="/home/${LDAP_ATTR['uid']}"
        fi
    else
        echo "User already has LDAP \"$ATTR\" set, skipping"
    fi
done

LDIF_STR="dn: ${LDAP_ATTR['dn']}"$'\n'
LDIF_STR=$LDIF_STR"changetype: modify"$'\n'

for ATTR in `echo "$ATTR_LIST"`
do
    LDIF_STR=$LDIF_STR"add: $ATTR"$'\n'
    LDIF_STR=$LDIF_STR"${ATTR}: ${LDAP_ATTR[$ATTR]}"$'\n'
    LDIF_STR=$LDIF_STR"-"$'\n'
done
echo
echo "$LDIF_STR"|ldapmodify -v -n -h $DC_SERVER -Y GSSAPI
