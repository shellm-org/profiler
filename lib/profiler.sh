#!/usr/bin/env bash

# TODO: keep actual command
#    will be used in reports

PROFILER_PS4='- ${BASH_SOURCE}:${LINENO} :${FUNCNAME}\$\$'

__profiler_redirect_xtrace() {
  tee >(sed -ru 's/\$\$.*$//;s/^-+ //' >/tmp/profiler.$1.log) |
    sed -u 's/^.*$/now/' |
    date -f - '+%s.%N' >/tmp/profiler.$1.tim
}

__profiler_start() {
  local snapshot=${1:-$$}
  PROFILER_OLD_PS4=${PS4}
  PS4=${PROFILER_PS4}

  if [ ! -f /tmp/profiler.${snapshot}.cmd ]; then
    echo "$0" "$@" >/tmp/profiler.${snapshot}.cmd
  fi

  exec 4> >(__profiler_redirect_xtrace ${snapshot})
  export BASH_XTRACEFD=4
  set -x
}

__profiler_stop() {
  set +x
  unset BASH_XTRACEFD
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
  eval set -- "${options}"

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

  echo "$@" >/tmp/profiler.${snapshot}.cmd

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
      BASH_XTRACEFD=4 bash -x "$@" 4> >(__profiler_redirect_xtrace ${snapshot})
      PS4=${old_ps4}
    ;;
  esac

  (( noreport == 1 )) || profiler report "${snapshot}" -g "${groupby}"
}

profiler() {
  local command

  command=$1
  shift

  case ${command} in
    start|stop|run) __profiler_${command} "$@" ;;
    *) command profiler ${command} "$@" ;;
  esac
}
