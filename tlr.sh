#
# Configure TLrealms
setup_tlr() {
  local session="" syscfg="/etc/syscfg.sh" sysargs=""
  while [ $# -gt 0 ]
  do
    case "$1" in
      --syscfg=*)
	syscfg=${1#--syscfg=}
	shift
	;;
      --sysargs=*)
	sysargs=${1#--sysargs=}
	shift
	;;
      --mkhome)
	shift
	session="$session
		session optional pam_mkhomedir.so skel=/etc/skel/ umask=0022"
	;;
      *)
	break
    esac
  done

  local domain="$1" kdc="$2"
  local \
    DOMAIN="$(echo $domain | tr a-z A-Z)" \
    KDC="$(echo $kdc | tr a-z A-Z)"

  <?= instree(PKG_TLREALMS.'/client','/usr/lib/tlr') ?>
  (
    cd /usr/bin
    for f in chpwd tlr-adm tlr-agent tlr-ed
    do
      fixlnk ../lib/tlr/loader $f
    done
  )
  mkdir -p /etc/tlr.d
  fixfile /etc/nsswitch.conf <<-EOF
	# /etc/nsswitch.conf
	#
	#	nisplus			Use NIS+ (NIS version 3)
	#	nis			Use NIS (NIS version 2), also called YP
	#	dns			Use DNS (Domain Name Service)
	#	files			Use the local files
	#	db			Use the local database (.db) files
	#	compat			Use NIS on compat mode
	#	hesiod			Use Hesiod for user lookups
	#	[NOTFOUND=return]	Stop searching if not found so far
	#
	passwd:	db files
	shadow:	db files
	group:	db files
	ethers: files

	bootparams: files

	ethers:     files
	netmasks:   files
	networks:   files
	protocols:  files
	rpc:        files
	services:   files

	netgroup:   files sss

	#publickey:  nisplus

	automount:  files
	aliases:    files
	EOF

  fixfile /etc/tlr.mk <<-EOF
	ETCDIR = /etc
	SRCDIR = /etc/tlr.d
	VAR_DB = /var/db
	ROOT_KEYS = /root/.ssh/authorized_keys
	TLRLIB = /usr/lib/tlr
	GRN_USERS = users
	GRI_USERS = 11000
	GRI_ADMINS = 11001

	SYSCFG = $syscfg
	SYSCFG_ARGS = $sysargs

	EOF

  fixfile /etc/tlr.cfg <<-EOF
	#
	# Global options
	#
	\$dsrv = '$kdc';
	\$verbose = 1;

	[agent]
	\$dbdir = '/etc/tlr.d';
	\$etcdir = '/etc';
	\$keyfile = undef;
	\$postproc = 'make -f /usr/lib/tlr/pwfix.mk';

	#  \$t_uid = getpwnam(name);
	#  \$t_gid = getgrnam(name);
	# \$min_sleep = 3600;
	# \$max_sleep = 4800;
	# \$port = 9989
	EOF

  fixfile /etc/krb5.conf <<-EOF
	[libdefaults]
	  default_realm = $DOMAIN
	  dns_lookup_realm = false
	  dns_lookup_kdc = false
	  ticket_lifetime = 24h
	  forwardable = yes

	[realms]
	  $DOMAIN = {
	    kdc = $KDC:88
	    admin_server = $KDC:749
	    default_domain = $domain
	  }

	[domain_realm]
	  .$domain = $DOMAIN
	  $domain = $DOMAIN
	EOF

  yinst krb5-workstation pam_krb5
  # We would prefer this, but doesn't do it quite the way we want it!
  : authconfig \
    --update \
    --enableshadow \
    --enablekrb5 \
    --passalgo=sha512

  [ -L /etc/pam.d/system-auth ] && rm /etc/pam.d/system-auth
  fixfile /etc/pam.d/system-auth <<-EOF
	#%PAM-1.0
	auth	required	pam_env.so
	auth	optional	pam_krb5.so try_first_pass
	auth	sufficient	pam_unix.so nullok use_first_pass
	auth	requisite	pam_succeed_if.so uid >= 1000 quiet_success
	auth	required	pam_deny.so

	account	required	pam_unix.so broken_shadow
	account	sufficient	pam_localuser.so
	account	sufficient	pam_succeed_if.so uid < 1000 quiet
	account	[default=bad success=ok user_unknown=ignore] pam_krb5.so
	account	required	pam_permit.so

	password requisite	pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
	password sufficient	pam_unix.so sha512 shadow nullok try_first_pass use_authtok
	password sufficient	pam_krb5.so use_authtok
	password required	pam_deny.so

	session	optional	pam_keyinit.so revoke
	session	required	pam_limits.so
	-session optional	pam_systemd.so
	session	[success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
	session	required	pam_unix.so
	$( [ -n "$session" ] && echo "$session" )
	session	optional	pam_krb5.so
	EOF

  fixfile /lib/systemd/system/tlr-agent.service <<-EOF
	[Unit]
	Description=TLR Agent
	After=network.target

	[Service]
	Type=simple
	ExecStart=/usr/bin/tlr-agent
	NotifyAccess=all

	[Install]
	WantedBy=multi-user.target

	EOF
}

setup_keytab() {
  local owner=""
  if [ x"$1" = x"-o" ] ; then
    local owner="$2"
    shift ; shift
  fi

  local kdc="$1" princ="$2" keytab="$3"
  [ -f $keytab ] && return 0

  local sshkey=/etc/ssh/ssh_host_rsa_key

  if [ ! -f $sshkey ] ; then
    warn Missing $sshkey, unable to set keytab $keytab
    return 1
  fi

  rm -f $keytab
  ssh -l root -i $sshkey $kdc addprinc $princ > $keytab

  if [ ! -s $keytab ] ; then
    rm $keytab
    warn "ERROR: Unable to create keytab $keytab"
    return 2
  fi
  chmod 400 $keytab
  [ -n "$owner" ] && chown $owner $keytab

  return 0
}

apache_tlr() {
  swinst httpd mod_auth_kerb
  setup_keytab -o apache "$1" "HTTP/$2" /etc/httpd/http.keytab
}

ssh_tlr() {
  if setup_keytab "$1" "host/$2" /etc/krb5.keytab ; then
    fixfile --filter /etc/ssh/sshd_config <<-EOF
	    grep -v KerberosAuthentication | \
	      grep -v GSSAPIAuthentication | \
	      grep -v GSSAPICleanupCredentials
	    echo "KerberosAuthentication yes"
	    echo "GSSAPIAuthentication yes"
	    echo "GSSAPICleanupCredentials yes"
	EOF
  fi
  runsrv sshd
}
