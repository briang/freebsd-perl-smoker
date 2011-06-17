#!/home/bri/perl5/perlbrew/perls/perl-5.12.3/bin/perl -w

eval 'exec /home/bri/perl5/perlbrew/perls/perl-5.12.3/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell
use strict;
$|=1;

# $Id: smokeperl.pl 1217 2008-12-30 08:51:27Z abeltje $
use vars qw( $VERSION );
$VERSION = Test::Smoke->VERSION;

use Cwd;
use File::Spec;
use File::Path;
use File::Copy;
my $findbin;
use File::Basename;
BEGIN { $findbin = File::Spec->rel2abs( dirname $0 ); }
use lib File::Spec->catdir( $findbin, 'lib' );
use lib File::Spec->catdir( $findbin, 'lib', 'inc' );
use lib $findbin;
use lib File::Spec->catdir( $findbin, 'inc' );
use Config;
use Test::Smoke::Syncer;
use Test::Smoke::Patcher;
use Test::Smoke;
use Test::Smoke::Reporter;
use Test::Smoke::Mailer;
use Test::Smoke::Util qw( get_patch calc_timeout do_pod2usage );

use Getopt::Long;
Getopt::Long::Configure( 'pass_through' );
my %options = (
    config       => 'smokecurrent_config',
    run          => 1,
    pfile        => undef,
    fetch        => 1,
    patch        => 1,
    mail         => undef,
    archive      => undef,
    continue     => 0,
    ccp5p_onfail => undef,
    killtime     => undef,
    is56x        => undef,
    defaultenv   => undef,
    smartsmoke   => undef,
    delay_report => undef,
    v            => undef,
    cfg          => undef
);

my $myusage = "Usage: $0 [-c configname]";
GetOptions( \%options, 
    'config|c=s', 
    'fetch!', 
    'patch!',
    'ccp5p_onfail!',
    'mail!',
    'delay_report!',
    'run!',
    'archive!',
    'is56x',
    'defaultenv!',
    'continue!',
    'smartsmoke!',
    'patchlevel=i',
    'snapshot|s=i',
    'killtime=s',
    'pfile=s',
    'cfg=s',

    'v|verbose=i',
    'help|h', 'man',
) or do_pod2usage(  verbose => 1, myusage => $myusage );

$options{ man} 
    and do_pod2usage( verbose => 2, exitval => 0, myusage => $myusage );
$options{help} 
    and do_pod2usage( verbose => 1, exitval => 0, myusage => $myusage );

=head1 NAME

smokeperl.pl - The perl Test::Smoke suite

=head1 SYNOPSIS

    $ ./smokeperl.pl [-c configname]

or

    C:\smoke>perl smokeperl.pl [-c configname]

=head1 OPTIONS

It can take these options

  --config|-c <configname> See configsmoke.pl (smokecurrent_config)
  --nofetch                Skip the synctree step
  --nopatch                Skip the patch step
  --nomail                 Skip the mail step
  --noarchive              Skip the archive step (if applicable)
  --[no]ccp5p_onfail       Do (not) send failure reports to perl5-porters
  --[no]delay_report       Do (not) create the report now

  --[no]continue           Try to continue an interrupted smoke
  --is56x                  This is a perl-5.6.x smoke
  --defaultenv             Run a smoke in the default environment
  --[no]smartsmoke         Don't smoke unless patchlevel changed
  --patchlevel <plevel>    Set old patchlevel for --smartsmoke --nofetch
  --snapshot <patchlevel>  Set a new patchlevel for snapshot smokes
  --killtime (+)hh::mm     (Re)set the guard-time for this smoke

  --pfile <patchesfile>    Set a patches-to-apply-file
  --cfg <buildcfg>         Set a Build Configurations File

All other arguments are passed to F<Configure>!

=head1 DESCRIPTION

F<smokeperl.pl> is the main program in this suite. It combines all the
front-ends internally and does some sanity checking.

=cut

# Try cwd() first, then $findbin
my $config_file = File::Spec->catfile( cwd(), $options{config} );
unless ( read_config( $config_file ) ) {
    $config_file = File::Spec->catfile( $findbin, $options{config} );
    read_config( $config_file );
}
defined Test::Smoke->config_error and 
    die "!!!Please run 'configsmoke.pl'!!!\nCannot find configuration: $!";

# smartsmoke doesn't make sense with nofetch (unless you say so)
defined $options{fetch} && !$options{fetch} && !defined $options{smartsmoke}
    and $options{smartsmoke} = 0;

# Correction for backward compatability
!defined $options{ $_ } && !exists $conf->{ $_ } and $options{ $_ } = 1
    for qw( run fetch patch mail archive v );
!defined $options{ $_ } && !exists $conf->{ $_ } and $options{ $_ } = 0
    for qw( delay_report );

# Make command-line options override configfile
defined $options{ $_ } and $conf->{ $_ } = $options{ $_ }
    for qw( is56x defaultenv continue killtime pfile cfg delay_report
            smartsmoke run fetch patch mail ccp5p_onfail archive v );

# Make sure the --pfile command-line override works
$options{pfile} and $conf->{patch_type} ||= 'multi';

if ( $options{continue} ) {
    $options{v} and print "Will try to continue current smoke\n";
} else {
    synctree();
    patchtree();
}

my $cwd = cwd();
chdir $conf->{ddir} or die "Cannot chdir($conf->{ddir}): $!";
call_mktest( $cwd );
chdir $cwd;
unless ( $conf->{delay_report} ) {
    genrpt();
    mailrpt();
} else {
    $conf->{v} and print "Delayed creation of the report. See 'mailrpt.pl'\n";
}
archiverpt();

sub synctree {
    my $now_patchlevel = get_patch( $conf->{ddir} )->[0] || -1;
    my $was_patchlevel = $options{smartsmoke} && $options{patchlevel}
        ? $options{patchlevel}
        : $now_patchlevel;
    FETCHTREE: {
        unless ( $options{fetch} && $options{run} ) {
            $conf->{v} and print "Skipping synctree\n";
            last FETCHTREE;
        }
        if ( $options{snapshot} ) {
            if ( $conf->{sync_type} eq 'snapshot' ||
               ( $conf->{sync_type} eq 'forest'   && 
                 $conf->{fsync} eq 'snapshot' ) ) {

                $conf->{sfile} = snapshot_name();
            } else {
                die "<--snapshot> is not valid now, please reconfigure!";
            }
            $conf->{sfile} = snapshot_name();
        }
        my $syncer = Test::Smoke::Syncer->new( $conf->{sync_type}, $conf );
        $now_patchlevel = $syncer->sync;
        $conf->{v} and 
            print "$conf->{ddir} now up to patchlevel $now_patchlevel\n";
    }

    if ( $conf->{smartsmoke} && ($was_patchlevel eq $now_patchlevel) ) {
        $conf->{v} and 
            print "Skipping this smoke, patchlevel ($was_patchlevel)" .
                  " did not change.\n";
        exit(0);
    }
}

sub patchtree {
    PATCHAPERL: {
        unless ( $options{patch} && $options{run} ) {
            $conf->{v} && exists $conf->{patch_type} &&
            $conf->{patch_type} eq 'multi' and
                print "Skipping patching ($conf->{pfile})\n";
            last PATCHAPERL;
        }
        last PATCHAPERL unless exists $conf->{patch_type} && 
                               $conf->{patch_type} eq 'multi' && 
                               $conf->{pfile};
        my $patcher = Test::Smoke::Patcher->new( $conf->{patch_type}, $conf );
        eval { $patcher->patch };
    }
}

sub call_mktest {
    my $cwd = shift;
    my $timeout = 0;
    if ( $Config{d_alarm} && $conf->{killtime} ) {
        $timeout = calc_timeout( $conf->{killtime} );
        $conf->{v} and printf "Setup alarm: %s\n",
                              scalar localtime( time() + $timeout );
    }
    $timeout and local $SIG{ALRM} = sub {
        warn "This smoke is aborted ($conf->{killtime})\n";
        chdir $cwd;
        genrpt();
        mailrpt();
        exit(42);
    };
    $Config{d_alarm} and alarm $timeout;

    run_smoke( $conf->{continue}, @ARGV );
}

sub genrpt {
    return unless $options{run};
    my $reporter = Test::Smoke::Reporter->new( $conf );
    $reporter->write_to_file;
}

sub mailrpt {
    unless ( $conf->{mail} && $options{run} ) {
        $conf->{v} and print "Skipping mailrpt\n";
        return;
    }
    my $mailer = Test::Smoke::Mailer->new( $conf->{mail_type}, $conf );
    $mailer->mail or warn "[$conf->{mail_type}] " . $mailer->error;
}

sub archiverpt {
    return unless $conf->{archive};
    return unless exists $conf->{adir};
    return if $conf->{adir} eq "";
    -d $conf->{adir} or do {
        mkpath( $conf->{adir}, 0, 0775 ) or 
            die "Cannot create '$conf->{adir}': $!";
    };

    my $patch_level = get_patch( $conf->{ddir} )->[0];
    $patch_level =~ tr/ //sd;

    SKIP_RPT: {
        my $archived_rpt = "rpt${patch_level}.rpt";
        # Do not archive if it is already done
        last SKIP_RPT
            if -f File::Spec->catfile( $conf->{adir}, $archived_rpt );

        copy( File::Spec->catfile( $conf->{ddir}, 'mktest.rpt' ),
              File::Spec->catfile( $conf->{adir}, $archived_rpt ) ) or
            die "Cannot copy to '$archived_rpt': $!";
    }

    SKIP_OUT: {
        my $archived_out = "out${patch_level}.out";
        # Do not archive if it is already done
        last SKIP_OUT
            if -f File::Spec->catfile( $conf->{adir}, $archived_out );

        copy( File::Spec->catfile( $conf->{ddir}, 'mktest.out' ),
              File::Spec->catfile( $conf->{adir}, $archived_out ) ) or
            die "Cannot copy to '$archived_out': $!";
    }

    SKIP_LOG: {
        my $archived_log = "log${patch_level}.log";
        last SKIP_LOG unless defined $conf->{lfile};
        last SKIP_LOG 
            unless -f $conf->{lfile};
        copy( $conf->{lfile},
              File::Spec->catfile( $conf->{adir}, $archived_log ) ) or
            die "Cannot copy to '$archived_log': $!";
    }
}

sub snapshot_name {
    my( $plevel ) = $options{snapshot} =~ /(\d+)/;
    my $sfile = $conf->{sfile};
    if ( $sfile ) {
        $sfile =~ s/([-@])\d+\./$1$plevel./;
    } else {
        my $sep = $conf->{is56x} ? '562-' : '@';
        my $ext = $conf->{snapext} || 'tar.gz';
        $sfile = "perl${sep}${plevel}.$ext";
    }
    return $sfile;
}

=head1 SEE ALSO

L<README>, L<FAQ>, L<configsmoke.pl>, L<mktest.pl>, L<mkovz.pl>

=head1 REVISION

$Id: smokeperl.pl 1217 2008-12-30 08:51:27Z abeltje $

=head1 COPYRIGHT

(c) 2002-2003, All rights reserved.

  * Abe Timmerman <abeltje@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

See:

=over 4

=item * L<http://www.perl.com/perl/misc/Artistic.html>

=item * L<http://www.gnu.org/copyleft/gpl.html>

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
