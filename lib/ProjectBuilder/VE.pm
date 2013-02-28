#!/usr/bin/perl -w
#
# Common functions for virtual environment
# 
# Copyright B. Cornec 2007-2012
# Eric Anderson's changes are (c) Copyright 2012 Hewlett Packard
# Provided under the GPL v2
#
# $Id$
#

package ProjectBuilder::VE;

use strict;
use Data::Dumper;
use Carp 'confess';
use English;
use ProjectBuilder::Version;
use ProjectBuilder::Base;
use ProjectBuilder::Conf;
use ProjectBuilder::Distribution;

# Global vars
# Inherit from the "Exporter" module which handles exporting functions.
 
use vars qw($VERSION $REVISION @ISA @EXPORT);
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_ve_launch);

($VERSION,$REVISION) = pb_version_init();

=pod

=head1 NAME

ProjectBuilder::VE, part of the project-builder.org - module dealing with Virtual Environment

=head1 DESCRIPTION

This modules provides functions to deal with Virtual Environements (VE), aka chroot.

=head1 SYNOPSIS

  use ProjectBuilder::VE;

  # 
  # Return information on the running distro
  #
  my $pbos = pb_ve_launch();

=head1 USAGE

=over 4

=item B<pb_ve_launch>

This function launch a VE, creating it if necessary using multiple external potential tools.

=cut

sub pb_ve_launch {

my $v = shift || undef;
my $pbforce = shift || 0;		# By default do not rebuild VE
my $locsnap = shift || 0;		# By default do not snap VE

# Get distro context
my $pbos = pb_distro_get_context($v);

# Get VE context
my ($ptr,$vepath) = pb_conf_get("vetype","vepath");
my $vetype = $ptr->{$ENV{'PBPROJ'}};

confess "No vetype defined for $ENV{PBPROJ}" unless (defined $vetype);
pb_log(1, "Using vetype $vetype for $ENV{PBPROJ}\n");

if (($vetype eq "chroot") || ($vetype eq "schroot")) {

	# We need to avoid umask propagation to the VE
	umask 0022;

	# We can probably only get those params now we have the distro context
	my ($rbsb4pi,$rbspi,$vesnap,$oscodename,$osmindep,$verebuild,$rbsmirrorsrv) = pb_conf_get_if("rbsb4pi","rbspi","vesnap","oscodename","osmindep","verebuild","rbsmirrorsrv");

	# Architecture consistency
	my $arch = pb_get_arch();
	if ($arch ne $pbos->{'arch'}) {
		die "Unable to launch a VE of architecture $pbos->{'arch'} on a $arch platform" unless (($pbos->{'arch'} =~ /i?86/o) && ($arch eq "x86_64"));
	}

	# If we are already root (from pbmkbm e.g.) don't use sudo, just call the command
	my $sudocmd="";
	if ($EFFECTIVE_USER_ID != 0) {
		$sudocmd ="sudo ";
		foreach my $proxy (qw/http_proxy ftp_proxy/) {
			if (defined $ENV{$proxy}) {
				open(CMD,"sudo sh -c 'echo \$$proxy' |") or die "can't run sudo sh?: $!";
				$_ = <CMD>;
				chomp();
				die "sudo not passing through env var $proxy; '$ENV{$proxy}' != '$_'\nAdd line Defaults:`whoami` env_keep += \"$proxy\" to sudoers file?" unless $_ eq $ENV{$proxy};
				close(CMD);
			}
		}
	}

	# Handle cross arch on Intel based platforms
	$sudocmd = "setarch i386 $sudocmd" if (($pbos->{'arch'} =~ /i[3456]86/) && ($arch eq 'x86_64'));

	my $root = pb_path_expand($vepath->{$ENV{PBPROJ}});
	if (((defined $verebuild) && ($verebuild->{$ENV{'PBPROJ'}} =~ /true/i)) || ($pbforce == 1)) {
		my ($verpmtype,$vedebtype) = pb_conf_get("verpmtype","vedebtype");
		my ($rbsopt1) = pb_conf_get_if("rbsopt");

		# We have to rebuild the chroot
		if ($pbos->{'type'} eq "rpm") {
	
			# Which tool is used
			my $verpmstyle = $verpmtype->{$ENV{'PBPROJ'}};
			die "No verpmtype defined for $ENV{PBPROJ}" unless (defined $verpmstyle);
	
			# Get potential rbs option
			my $rbsopt = "";
			if (defined $rbsopt1) {
				if (defined $rbsopt1->{$verpmstyle}) {
					$rbsopt = $rbsopt1->{$verpmstyle};
				} elsif (defined $rbsopt1->{$ENV{'PBPROJ'}}) {
					$rbsopt = $rbsopt1->{$ENV{'PBPROJ'}};
				} else {
					$rbsopt = "";
				}
			}
	
			my $postinstall = pb_ve_get_postinstall($pbos,$rbspi,$verpmstyle);
			if ($verpmstyle eq "rinse") {
				# Need to reshape the mirrors generated with local before-post-install script
				my $b4post = "--before-post-install ";
				my $postparam = pb_distro_get_param($pbos,$rbsb4pi);
				if ($postparam eq "") {
					$b4post = "";
				} else {
					$b4post .= $postparam;
				}
	
				# Need to reshape the package list for pb
				my $addpkgs;
				$postparam = "";
				$postparam .= pb_distro_get_param($pbos,$osmindep);
				if ($postparam eq "") {
					$addpkgs = "";
				} else {
					my $pkgfile = "$ENV{'PBTMP'}/addpkgs.lis";
					open(PKG,"> $pkgfile") || die "Unable to create $pkgfile";
					foreach my $p (split(/,/,$postparam)) {
						print PKG "$p\n";
					}
					close(PKG);
					$addpkgs = "--add-pkg-list $pkgfile";
				}
	
				my $rinseverb = "";
				$rinseverb = "--verbose" if ($pbdebug gt 0);
				my ($rbsconf) = pb_conf_get("rbsconf");
	
				my $command = pb_check_req("rinse",0);
				pb_system("$sudocmd $command --directory \"$root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}\" --arch \"$pbos->{'arch'}\" --distribution \"$pbos->{'name'}-$pbos->{'version'}\" --config \"$rbsconf->{$ENV{'PBPROJ'}}\" $b4post $postinstall $rbsopt $addpkgs $rinseverb","Creating the rinse VE for $pbos->{'name'}-$pbos->{'version'} ($pbos->{'arch'})", "verbose");
			} elsif ($verpmstyle eq "rpmbootstrap") {
				my $rbsverb = "";
				foreach my $i (1..$pbdebug) {
					$rbsverb .= " -v";
				}
				my $addpkgs = "";
				my $postparam = "";
				$postparam .= pb_distro_get_param($pbos,$osmindep);
				if ($postparam eq "") {
					$addpkgs = "";
				} else {
					$addpkgs = "-a $postparam";
				}
				my $command = pb_check_req("rpmbootstrap",0);
				pb_system("$sudocmd $command $rbsopt $postinstall $addpkgs $pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'} $rbsverb","Creating the rpmbootstrap VE for $pbos->{'name'}-$pbos->{'version'} ($pbos->{'arch'})", "verbose");
				pb_system("$sudocmd /bin/umount $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}/proc","Umounting stale /proc","mayfail") if (-f "$root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}/proc/cpuinfo");
			} elsif ($verpmstyle eq "mock") {
				my ($rbsconf) = pb_conf_get("rbsconf");
				my $command = pb_check_req("mock",0);
				pb_system("$sudocmd $command --init --resultdir=\"/tmp\" --configdir=\"$rbsconf->{$ENV{'PBPROJ'}}\" -r $v $rbsopt","Creating the mock VE for $pbos->{'name'}-$pbos->{'version'} ($pbos->{'arch'})");
				# Once setup we need to install some packages, the pb account, ...
				pb_system("$sudocmd $command --install --configdir=\"$rbsconf->{$ENV{'PBPROJ'}}\" -r $v su","Configuring the mock VE");
			} else {
				die "Unknown verpmtype type $verpmstyle. Report to dev team";
			}
		} elsif ($pbos->{'type'} eq "deb") {
			my $vedebstyle = $vedebtype->{$ENV{'PBPROJ'}};
		
			my $codename = pb_distro_get_param($pbos,$oscodename);
			my $postparam = "";
			my $addpkgs;
			$postparam .= pb_distro_get_param($pbos,$osmindep);
			if ($postparam eq "") {
				$addpkgs = "";
			} else {
				$addpkgs = "--include $postparam";
			}
			my $debmir = "";
			$debmir .= pb_distro_get_param($pbos,$rbsmirrorsrv);
	
			# Get potential rbs option
			my $rbsopt = "";
			if (defined $rbsopt1) {
				if (defined $rbsopt1->{$vedebstyle}) {
					$rbsopt = $rbsopt1->{$vedebstyle};
				} elsif (defined $rbsopt1->{$ENV{'PBPROJ'}}) {
					$rbsopt = $rbsopt1->{$ENV{'PBPROJ'}};
				} else {
					$rbsopt = "";
				}
			}
	
			# debootstrap works with amd64 not x86_64
			my $debarch = $pbos->{'arch'};
			$debarch = "amd64" if ($pbos->{'arch'} eq "x86_64");
			if ($vedebstyle eq "debootstrap") {
				my $dbsverb = "";
				$dbsverb = "--verbose" if ($pbdebug gt 0);
		
				# Some perl modules are in Universe on Ubuntu
				$rbsopt .= " --components=main,universe" if ($pbos->{'name'} eq "ubuntu");
		
				my $cmd1 = pb_check_req("mkdir",0);
				my $cmd2 = pb_check_req("debootstrap",0);
				pb_system("$sudocmd $cmd1 -p $root/$pbos->{name}/$pbos->{version}/$pbos->{arch} ; $sudocmd $cmd2 $dbsverb $rbsopt --arch=$debarch $addpkgs $codename \"$root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}\" $debmir","Creating the debootstrap VE for $pbos->{'name'}-$pbos->{'version'} ($pbos->{'arch'})", "verbose");
				# debootstrap doesn't create an /etc/hosts file
				if (! -f "$root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}/etc/hosts" ) {
					my $cmd = pb_check_req("cp",0);
					pb_system("$sudocmd $cmd /etc/hosts $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}/etc/hosts");
				}
			} else {
				die "Unknown vedebtype type $vedebstyle. Report to dev team";
			}
		} elsif ($pbos->{'type'} eq "ebuild") {
			die "Please teach the dev team how to build gentoo chroot";
		} else {
			die "Unknown distribution type $pbos->{'type'}. Report to dev team";
		}
	}

	# Test if an existing snapshot exists and use it if appropriate
	# And also use it of no local extracted VE is present
	if ((-f "$root/$pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'}.tar.gz") &&
	(((defined $vesnap->{$v}) && ($vesnap->{$v} =~ /true/i)) ||
		((defined $vesnap->{$ENV{'PBPROJ'}}) && ($vesnap->{$ENV{'PBPROJ'}} =~ /true/i))) &&
		($locsnap eq 1) &&
		(! -d "$root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}")) {
			my $cmd1 = pb_check_req("rm",0);
			my $cmd2 = pb_check_req("mkdir",0);
			my $cmd3 = pb_check_req("tar",0);
			pb_system("$sudocmd $cmd1 -rf $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'} ; $sudocmd $cmd2 -p $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'} ; $sudocmd $cmd3 xz  -C $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'} -f $root/$pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'}.tar.gz","Extracting snapshot of $pbos->{'name'}-$pbos->{'version'}-$pbos->{'arch'}.tar.gz under $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}");
	}
	
	# Fix modes to allow access to the VE for pb user
	my $command = pb_check_req("chmod",0);
	pb_system("$sudocmd $command 755 $root/$pbos->{'name'} $root/$pbos->{'name'}/$pbos->{'version'} $root/$pbos->{'name'}/$pbos->{'version'}/$pbos->{'arch'}","Fixing permissions");

	# Nothing more to do for VE. No real launch
} else {
	die "VE of type $vetype not supported. Report to the dev team";
}
}

#
# Return the postinstall line if needed
#

sub pb_ve_get_postinstall {

my $pbos = shift;
my $rbspi = shift;
my $vestyle = shift;
my $post = "";

# Do we have a local post-install script
if ($vestyle eq "rinse") {
	$post = "--post-install ";
} elsif ($vestyle eq "rpmbootstrap") {
	$post = "-s ";
}

my $postparam = pb_distro_get_param($pbos,$rbspi);
if ($postparam eq "") {
	$post = "";
} else {
	$post .= $postparam;
}
return($post);
}


=head1 WEB SITES

The main Web site of the project is available at L<http://www.project-builder.org/>. Bug reports should be filled using the trac instance of the project at L<http://trac.project-builder.org/>.

=head1 USER MAILING LIST

None exists for the moment.

=head1 AUTHORS

The Project-Builder.org team L<http://trac.project-builder.org/> lead by Bruno Cornec L<mailto:bruno@project-builder.org>.

=head1 COPYRIGHT

Project-Builder.org is distributed under the GPL v2.0 license
described in the file C<COPYING> included with the distribution.

=cut


1;
