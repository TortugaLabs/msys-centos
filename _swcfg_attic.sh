#
# Old configuration
#
######################################################################
#
_grpdata() {
  yum groupinfo "$1" 2>/dev/null | (
    out=no
    while read line
    do
      if [ x"$line" = x"Mandatory Packages:" ] ; then
	out=yes
	continue
      fi
      if [ x"$line" = x"Default Packages:" ] ; then
	out=yes
	continue
      fi
      if [ x"$line" = x"Optional Packages:" ] ; then
	out=no
	continue
      fi
      if [ x"$line" = x"Conditional Packages:" ] ; then
	out=no
	continue
      fi
      [ $out = yes ] && echo $line
    done
  ) | sed 's/^[-=+]//'
}

ginst() {
  local g p
  local rpms=()
  for g in "$@"
  do
    [ -z "$g" ] && continue
    if [ x$(expr substr "$g" 1 1) = x"-" ] ; then
      # Remove rpms from the list
      local x=()
      g=$(expr substr "$g" 2 4096)
      for p in "${rpms[@]}"
      do
	[ "$p" = "$g" ] && continue
	x+=( "$p" )
      done
      rpms=( "${x[@]}" )
    else
      rpms+=( $(_grpdata "$g") )
    fi
  done
  yinst "${rpms[@]}"
}
#
######################################################################
#
_ygrpinf() {
  yum groupinfo "$@" | grep -v '^\s*-' | sed -e 's/^\(\s*\)[=+]/\1/'
  # -e 's/^\(\s*\)[0-9]*:/\1/'
}

swg_groupinit() {
  # Check if there is a cached file...
  local cache=$HOME/.swg_cache
  if [ -f $cache ] ; then
    local tstamp=$(stat --format '%Y' $cache)
    local now=$(date +%s)
    if [ $(expr $now - $tstamp) -lt $(expr 86400) ] ; then
      # Use cache...
      echo "Using cached group definitions" 1>&2
      . $cache
      return
    fi
  fi
  _swg__lockfile=$(mktemp)
  echo "Retrieving group definitions" 1>&2

  on_exit rm -f $_swg__lockfile
  exec 9>$_swg__lockfile
  flock 9 || exit 1
  (
    exec 1>&9
    yum grouplist | _swg_groupinv | sort -u | _swg_allgrps \
      | tee $HOME/.swg_cache
    exit
  ) &
  exec 9>&-
}

swg_import() {
  eval "$(_swg_allgrps <<<"$*")"
}

_swg_lookup() {
  _swg_groupinit_done
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
_swg_grdef() {
  local id="$1" ; shift
  local state="" i
  local vm= vo= vd=

  while read line
  do
    case "$(tr A-Z a-z <<<"$line")" in
      group-id:*)
	[ x"$id" = x"-" ] && id=$(echo $line | cut -d: -f2 | tr 'x-' 'x_' | tr -d ' ')
	;;
      mandatory*:)
	state="m"
	continue
	;;
      conditional*:)
	# We handle conditional just like optional...
	state="o"
	continue
	;;
      optional*:)
	state="o"
	continue
	;;
      default*:)
	state="d"
	continue
	;;
      -*)
	: $line
	continue
	;;
      +*)
	line=${line#+}
	;;
      =*)
	line=${line#=}
	;;
    esac
    [ x"$state" = x"" ] && continue
    for i in $*
    do
      [ x"$i" = x"$line" ] && continue 2
    done
    eval v${state}=\"\$v${state} \$line\"
  done
  [ x"$id" = x"-" ] && return
  [ -z "$vm" ] && [ -z "$vo" ] && [ -z "$vd" ] && return
  echo "# grp $id"
  [ -n "$vm" -o -n "$vd" ] && echo "_swg_${id}=\"$(echo $vm $vd)\""
  echo "_swg_${id}_a=\"$(echo $vm $vd $vo)\""
  [ -n "$vm" ] && echo "_swg_${id}_m=\"$(echo $vm)\""
  [ -n "$vd" ] && echo "_swg_${id}_d=\"$(echo $vd)\""
  [ -n "$vo" ] && echo "_swg_${id}_o=\"$(echo $vo)\""
}

_swg_egrp() {
  local egrp="$1"
  _ygrpinf "$line" 2>/dev/null |(
    cmd=":"
    while read line
    do
      case "$(tr A-Z a-z <<<"$line")" in
	*groups:)
	  cmd="echo"
	  continue
	  ;;
      esac
      $cmd $line
    done
  )
}

_swg_groupinv() {
  local cmd=":"
  while read line
  do
    case "$(tr A-Z a-z <<<"$line")" in
      *environment*groups:)
	cmd="_swg_egrp"
	continue
	;;
      *groups:)
	cmd="echo"
	continue
	;;
      done)
	break
    esac
    $cmd "$line"
  done
}
_swg_allgrps() {
  while read line
  do
    _ygrpinf "$line" 2>/dev/null | _swg_grdef -
  done
}
_swg_groupinit_done() {
  [ -z "$_swg__lockfile" ] && return
  echo "Waiting for group retrieval" 1>&2
  exec 9>>$_swg__lockfile
  flock 9  || exit 1
  . $_swg__lockfile
  _swg__lockfile=""
}
