#! /bin/sh
#
# Written by ./configsmoke.pl v0.072
# Thu Jun 16 21:27:22 2011
# NOTE: Changes made in this file will be *lost*
#       after rerunning ./configsmoke.pl
#
# 
# Uncomment this to be as nice as possible. (Jarkko)
# (renice -n 20 $$ >/dev/null 2>&1) || (renice 20 $$ >/dev/null 2>&1)

cd /usr/home/bri/smoke
CFGNAME=${CFGNAME:-512_config}
LOCKFILE=${LOCKFILE:-512.lck}
PIDFILE=${PIDFILE:-512.pid}
continue=''
if test -f "$LOCKFILE" && test -s "$LOCKFILE" ; then
    echo "We seem to be running (or remove $LOCKFILE)" >& 2
    exit 200
fi
echo "$CFGNAME" > "$LOCKFILE"
echo "$$"       > "$PIDFILE"

export PATH=/bin:/usr/bin:/usr/local/bin
umask 0
/usr/bin/perl ./smokeperl.pl -c "$CFGNAME" $continue $* > 512.log 2>&1

rm "$LOCKFILE" "$PIDFILE"
