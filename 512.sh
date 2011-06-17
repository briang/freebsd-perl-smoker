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
continue=''
if test -f "$LOCKFILE" && test -s "$LOCKFILE" ; then
    echo "We seem to be running (or remove $LOCKFILE)" >& 2
    exit 200

fi
echo "$CFGNAME" > "$LOCKFILE"


PATH=.:/home/bri/perl5/perlbrew/bin:/home/bri/perl5/perlbrew/perls/perl-5.12.3/bin:~/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin
export PATH
umask 0
/home/bri/perl5/perlbrew/perls/perl-5.12.3/bin/perl ./smokeperl.pl -c "$CFGNAME" $continue $* > 512.log 2>&1

rm "$LOCKFILE"
