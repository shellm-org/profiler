#!/usr/bin/env bash

PROFILER_MARKER=$'\035'  # group separator character

# shellcheck disable=SC2016
PROFILER_PS4='${PROFILER_MARKER} ${BASH_SOURCE[0]}${PROFILER_MARKER}${BASH_SOURCE[1]}${PROFILER_MARKER}${LINENO}${PROFILER_MARKER}${FUNCNAME}${PROFILER_MARKER}'

export PROFILER_MARKER

eval() {
  # . <(echo "$@")
  command eval "$@"
}

profiler_cache_function_contents() {
  for f in $(declare -F | cut -d" " -f3); do
    declare -f "$f" | head -n-1 | tail -n+3 > "/tmp/profiler-function-contents.$f"
  done
  exit &>/dev/null
}

export -f eval
export -f profiler_cache_function_contents

__profiler_redirect_xtrace() {
  tee "/tmp/profiler.$1.xtrace" | {
    sed -u 's/^.*$/now/'
    echo now
  } | date -f - '+%s.%N' >"/tmp/profiler.$1.timestamps"
  echo "${PROFILER_MARKER}" >>"/tmp/profiler.$1.xtrace"
}

__profiler_start() {
  local snapshot=${1:-$$}
  PROFILER_OLD_PS4=${PS4}
  PS4=${PROFILER_PS4}
  export PROFILER=1

  if [ ! -f "/tmp/profiler.${snapshot}.cmd" ]; then
    echo "$0" "$@" >"/tmp/profiler.${snapshot}.cmd"
  fi

  exec 4> >(__profiler_redirect_xtrace "${snapshot}")
  export BASH_XTRACEFD=4
  set -x
}

__profiler_stop() {
  set +x
  unset BASH_XTRACEFD
  unset PROFILER
  PS4=${PROFILER_OLD_PS4}
}

__profiler_run() {
  local snapshot
  local old_ps4
  local subshells
  local options
  local groupby=line
  local noreport=0

  options="$(getopt -n profiler-run -o "g:hi:ns" -l "group-by:,help,snapshot-id:,no-report,subshells" -- "$@")"
  command eval set -- "${options}"

  while (( $# != 0 )); do
    case $1 in
      -g|--group-by) groupby="$2"; shift ;;
      -h|--help) ;;
      -i|--snapshot-id) snapshot="$2"; shift ;;
      -n|--no-report) noreport=1 ;;
      -s|--subshells) subshells=1 ;;
      --) shift; break ;;
    esac
    shift
  done

  if [ -z "${snapshot}" ]; then
    snapshot="$1.$$"
  fi

  if (( $# == 0 )); then
    echo "usage: profiler run [-s] <COMMAND> [ARGS]" >&2
    return 1
  fi

  echo "$@" >"/tmp/profiler.${snapshot}.cmd"

  (( subshells == 1 )) && export SHELLOPTS

  case $(type -t "$1") in
    function)
      __profiler_start "${snapshot}"
      "$@"
      __profiler_stop
    ;;
    *)
      old_ps4=${PS4}
      export PS4=${PROFILER_PS4}
      [ "$1" = "bash" ] && shift
      export BASH_XTRACEFD
      export PROFILER
      BASH_XTRACEFD=4 PROFILER=1 bash -x "$@" 4> >(__profiler_redirect_xtrace "${snapshot}")
      PS4=${old_ps4}
    ;;
  esac

  if (( noreport != 1 )); then
    while lsof -c bash | grep -Fq "/tmp/profiler.${snapshot}.xtrace"; do
      sleep 0.1
    done
    sleep 0.2
    profiler collate "${snapshot}" >/dev/null
    profiler report "${snapshot}" -g "${groupby}"
  fi
}

profiler() {
  local command

  command=$1
  shift

  case ${command} in
    start|stop|run)
      # shellcheck disable=SC2086
      __profiler_${command} "$@"
    ;;
    *) command profiler "${command}" "$@" ;;
  esac
}
