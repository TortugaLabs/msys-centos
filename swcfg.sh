#######################################################################
<?=mkgrps('x86_64',7)?>

#
# yum groupinfo [-v]
# Will give another column but also changes the package info
# kickstart --nobase
#
#    %packages --nobase
#    @core --nodefaults
#    %end
#
#######################################################################
#

#
# Configure software
#
# Macros
INST_LIST=()
yinst() {
  local rpms y z
  rpms=()
  for y in "$@"
  do
    if grep -q '\.rpm$' <<<"$y" ; then
      z=$(basename $y | sed 's/-[^-]*-[^-]*$//')
    else
      z=$y
    fi
    INST_LIST+=( "$z" )
    rpm -q "$z" >/dev/null 2>&1|| rpms+=( "$y" )
    # rpm -q "$z" || rpms+=( "$y" )
  done
  [ ${#rpms[@]} -gt 0 ] && yum -y install "${rpms[@]}"
}

swg_define() {
  local grname="$1" ; shift
  eval _swg_${grname}=\"\$*\"
}

swg_get() {
  local i j res="" rm=""
  for i in "$@"
  do
    if [ x"$(expr substr "$i" 1 1)" = x"-" ] ; then
      rm="$rm $(_swg_lookup ${i#-})"
      continue
    fi
    res="$res $(_swg_lookup "$i")"
  done
  # Remove duplicates
  res="$(echo "$res" | tr ' ' '\n' | sort -u)"

  # Remove exceptions...
  for i in $rm
  do
    local xres=""
    for j in $res
    do
      [ x"$j" = x"$i" ] && continue
      xres="$xres $j"
    done
    res="$xres"
  done
  echo $res
}

_swg_lookup() {
  local i
  for i in "$@"
  do
    local j=$(tr x- x_ <<<"$i")
    eval local gc=\"\$_swg_${j}\"
    if [ -z "$gc" ] ; then
      echo $i
    else
      echo $gc
    fi
  done
}

swinst() {
  yinst $(swg_get "$@")
}

swcat() {
  (
    for i in "${INST_LIST[@]}"
    do
      echo $i
    done
  ) > "$1"
}

<?= fixfile_inc('centos/swsn','/sbin/swsn',['mode'=>755]) ?>
<?php post_text('swcat $HOME/swcfg.txt'.NL); ?>
