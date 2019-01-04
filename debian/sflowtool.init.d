#!/bin/sh -e

### BEGIN INIT INFO
# Provides:          sflowtool
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Should-Start:      network-manager
# Should-Stop:       network-manager
# X-Start-Before:    $x-display-manager gdm kdm xdm wdm ldm sdm nodm
# X-Interactive:     true
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Sflowtool service
# Description: This script will start sflowtool instances as specified
#              in /etc/default/sflowtool and /etc/sflowtool/*.conf
### END INIT INFO

# Original version by Robert Leslie
# <rob@mars.org>, edited by iwj and cs
# Modified for openvpn by Alberto Gonzalez Iniesta <agi@inittab.org>
# Modified for restarting / starting / stopping single tunnels by Richard Mueller <mueller@teamix.net>
# Modified for sflowtool by Sergey Popovich <sergey.popovich@ordnance.co>

. /lib/lsb/init-functions

test $DEBIAN_SCRIPT_DEBUG && set -v -x

DAEMON=/usr/bin/sflowtool
DESC="sFlow serivce"
CONFIG_DIR=/etc/sflowtool
test -x $DAEMON || exit 0
test -d $CONFIG_DIR || exit 0

# Source defaults file; edit that file to configure this script.
AUTOSTART="all"
if test -e /etc/default/sflowtool ; then
  . /etc/default/sflowtool
fi

start_sflowtool () {
  log_progress_msg "$NAME"
  STATUS=0

  . $CONFIG_DIR/$NAME.conf

  start-stop-daemon --start --quiet --oknodo \
      --pidfile /run/sflowtool/$NAME.pid --background --make-pidfile \
      --exec $DAEMON -- $OPTARGS \
      || STATUS=1
}
stop_sflowtool () {
  . $CONFIG_DIR/$NAME.conf

  start-stop-daemon --stop --quiet --oknodo \
      --pidfile $PIDFILE --exec $DAEMON --retry 10

  if [ "$?" -eq 0 ]; then
    rm -f $PIDFILE
  fi
}

case "$1" in
start)
  log_daemon_msg "Starting $DESC"

  # first create /run directory so it's present even
  # when no sflowtool(s) are autostarted by this script, but later
  # by systemd sflowtool@.service
  mkdir -p /run/sflowtool

  # autostart instances
  if test -z "$2" ; then
    # check if automatic startup is disabled by AUTOSTART=none
    if test "x$AUTOSTART" = "xnone" -o -z "$AUTOSTART" ; then
      log_warning_msg " Autostart disabled."
      exit 0
    fi
    if test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
      # all sflowtool(s) shall be started automatically
      for CONFIG in `cd $CONFIG_DIR; ls *.conf 2> /dev/null`; do
        NAME=${CONFIG%%.conf}
        start_sflowtool
      done
    else
      # start only specified sflowtool(s)
      for NAME in $AUTOSTART ; do
        if test -e $CONFIG_DIR/$NAME.conf ; then
          start_sflowtool
        else
          log_failure_msg "No such instance: $NAME"
          STATUS=1
        fi
      done
    fi
  #start sflowtool(s) from command line
  else
    while shift ; do
      [ -z "$1" ] && break
      if test -e $CONFIG_DIR/$1.conf ; then
        NAME=$1
        start_sflowtool
      else
       log_failure_msg " No such instance: $1"
       STATUS=1
      fi
    done
  fi
  log_end_msg ${STATUS:-0}
  ;;

stop)
  log_daemon_msg "Stopping $DESC"

  if test -z "$2" ; then
    for PIDFILE in `ls /run/sflowtool/*.pid 2> /dev/null`; do
      NAME=`echo $PIDFILE | cut -c16-`
      NAME=${NAME%%.pid}
      stop_sflowtool
      log_progress_msg "$NAME"
    done
  else
    while shift ; do
      [ -z "$1" ] && break
      if test -e /run/sflowtool/$1.pid ; then
        PIDFILE=`ls /run/sflowtool/$1.pid 2> /dev/null`
        NAME=`echo $PIDFILE | cut -c16-`
        NAME=${NAME%%.pid}
        stop_sflowtool
        log_progress_msg "$NAME"
      else
        log_failure_msg " (failure: No such instance is running: $1)"
      fi
    done
  fi
  log_end_msg 0
  ;;

reload|force-reload)
  log_daemon_msg "Reloading $DESC"
  log_end_msg 255
  ;;

soft-restart)
  log_daemon_msg "$DESC sending SIGUSR1"
  log_end_msg 255
 ;;

restart)
  shift
  $0 stop ${@}
  $0 start ${@}
  ;;

cond-restart)
  log_daemon_msg "Restarting $DESC."
  for PIDFILE in `ls /run/sflowtool/*.pid 2> /dev/null`; do
    NAME=`echo $PIDFILE | cut -c16-`
    NAME=${NAME%%.pid}
    stop_sflowtool
    start_sflowtool
  done
  log_end_msg 0
  ;;

status)
  GLOBAL_STATUS=0
  if test -z "$2" ; then
    # We want status for all defined sflowtool(s)
    # Returns success if all autostarted sflowtool(s) are defined and running
    if test "x$AUTOSTART" = "xnone" ; then
      # Consider it a failure if AUTOSTART=none
      log_warning_msg "No sflowtools autostarted"
      GLOBAL_STATUS=1
    else
      if ! test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
        # Consider it a failure if one of the autostarted sflowtool(s) is not defined
        for SF in $AUTOSTART ; do
          if ! test -f $CONFIG_DIR/$SF.conf ; then
            log_warning_msg "sflowtool '$SF' is in AUTOSTART but is not defined"
            GLOBAL_STATUS=1
          fi
        done
      fi
    fi
    for CONFIG in `cd $CONFIG_DIR; ls *.conf 2> /dev/null`; do
      NAME=${CONFIG%%.conf}
      # Is it an autostarted sflowtool ?
      if test -z "$AUTOSTART" -o "x$AUTOSTART" = "xall" ; then
        AUTOSF=1
      else
        if test "x$AUTOSTART" = "xnone" ; then
          AUTOSF=0
        else
          AUTOSF=0
          for SF in $AUTOSTART; do
            if test "x$SF" = "x$NAME" ; then
              AUTOSF=1
            fi
          done
        fi
      fi
      if test "x$AUTOSF" = "x1" ; then
        # If it is autostarted, then it contributes to global status
        status_of_proc -p /run/sflowtool/${NAME}.pid sflowtool "sflowtool '${NAME}'" || GLOBAL_STATUS=1
      else
        status_of_proc -p /run/sflowtool/${NAME}.pid sflowtool "sflowtool '${NAME}' (non autostarted)" || true
      fi
    done
  else
    # We just want status for specified sflowtool(s).
    # Returns success if all specified sflowtool(s) are defined and running
    while shift ; do
      [ -z "$1" ] && break
      NAME=$1
      if test -e $CONFIG_DIR/$NAME.conf ; then
        # Config exists
        status_of_proc -p /run/sflowtool/${NAME}.pid sflowtool "sflowtool '${NAME}'" || GLOBAL_STATUS=1
      else
        # Config does not exist
        log_warning_msg "sflowtool '$NAME': missing $CONFIG_DIR/$NAME.conf file !"
        GLOBAL_STATUS=1
      fi
    done
  fi
  exit $GLOBAL_STATUS
  ;;

*)
  echo "Usage: $0 {start|stop|reload|restart|force-reload|cond-restart|soft-restart|status}" >&2
  exit 1
  ;;
esac

exit 0

# vim:set ai sts=2 sw=2 tw=0:
