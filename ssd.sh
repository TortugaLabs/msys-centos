#!/bin/sh
#
# SSD related tweaks
#
ssd_tweaks() {
  [ -f /etc/lvm/lvm.conf ] && fixfile --filter /etc/lvm/lvm.conf <<-'EOF'
	sed -e 's/ *issue_discards *=.*/ issue_discards = 1/'
	EOF
  local noatime=""
  if [ x"$1" = x"--noatime" ] ; then
    shift
    noatime=",noatime"
  fi
  [ $# -eq 0 ] && set - / /boot
  local awk_script="{ if (" q="" i
  for i in "$@"
  do
    awk_script="$awk_script$q\$2 == \"$i\""
    q=" || "
  done
  awk_script="$awk_script) {"
  awk_script="$awk_script
	  o=\$4 \",discard$noatime\"
	  print \$1,\$2,\$3,o,\$5,\$6
	} else {
	  print
	}"
  awk_script="$awk_script }"
  echo "awk '$awk_script'" | fixfile --filter /etc/fstab
}
