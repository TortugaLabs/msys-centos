#
# Centos macros
#
<?php
  require_once('centos/getgrp.php');
  require_once('centos/macros.php');
?>

<?php if (defined('BRIEF_OUTPUT')) { ?>
#
# SUPPRESED -- use TEST_SHOW_ALL=1 to show suppressed output
#
<?php } else { ?>

[ ! -f /etc/centos-release ] && fatal "Not a valid OS"
if [ -e /etc/os-release ] ; then
  . /etc/os-release
  [ x"$ID" != x"centos"  ] && fatal "Only centos OS supported"
  export centos_release="$VERSION_ID"
else
  read -r system_release < /etc/system-release
  export centos_version=$(tr -dc .0-9 < /etc/system-release)
  export centos_release=$(echo $centos_version | sed 's/\..*$//')
fi

<?php
  require_once('centos/swcfg.sh');
  require_once('centos/tlr.sh');
?>

now=$(date +%s)
# Update repo files...
repofix() {
  local \
    repo="$1" \
    rem_url="$2" \
    loc_url="$3"
  [ -f /etc/yum.repos.d/$repo ] || return 0
  local now=$(date +%s)
  fixfile --nobackup --filter /etc/yum.repos.d/$repo <<-EOF
	sed \
	    -e 's/^mirrorlist=/#mirrorlist=/' \
	    -e 's!^#*baseurl=http://.*/$rem_url/!baseurl=$loc_url/!'

	EOF
  nstamp=$(stat -c %Y /etc/yum.repos.d/$repo)
  [ $nstamp -ge $now ] && return 1
  return 0
}

set_hostname() {
  local name="$1"
  [ -z "$name" ] && name="<?=SYSNAME?>.<?=$cf['globs']['domain']?>"
  echo "$name" | fixfile /etc/hostname
}

static_resolv_conf() {
  [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
  fixfile /etc/resolv.conf <<-EOF
	domain <?=$cf['globs']['domain'].NL ?>
	nameserver <?= res('ip4','ns',NULL,0).NL ?>
	nameserver <?= res('ip6','ns',NULL,0).NL ?>
	EOF
}

runsrv() {
  local srv="$1"
  systemctl is-enabled "$srv" >/dev/null || systemctl enable "$srv"
  systemctl restart "$srv"
}

set_desktop() {
  local startexe="$1" ; shift
  [ -x $startexe ] || return

  if [ -n "$*" ] ; then
    startexe="$*"
  fi

  fixfile --mode=644 /etc/profile.d/z_startgui.sh <<-EOF
	#!/bin/sh
	umask 0002
	[[ -z \$DISPLAY && \$(tty) = /dev/tty1 && \$UID -ne 0 ]] \
	    && exec startx $startexe

	EOF
}

firefox_prefsdir() {
  for i in $(rpm -q firefox -l | grep preferences)
  do
    [ -L "$i" ] && continue
    dirname $i
    break
  done
}

setup_autofs() {
  swinst nfs-utils autofs # cachesfiled -- how to enable this?

  # Work-around for bug...
  fixfile --filter /etc/auto.master <<-EOF
	sed -e 's!/net[	 ][	 ]*-hosts!/net /etc/auto.net --timeout=60!'
	EOF

  runsrv autofs
  runsrv rpcbind
}


<?php } ?>
