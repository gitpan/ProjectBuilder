#!/usr/bin/perl -w
#
# Creates common environment for distributions
#
# $Id$
#

package ProjectBuilder::Distribution;

use strict;
use Data::Dumper;
use ProjectBuilder::Base;
use ProjectBuilder::Conf;
use File::Basename;
use File::Copy;

# Inherit from the "Exporter" module which handles exporting functions.
 
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_distro_init pb_distro_get pb_distro_installdeps pb_distro_getdeps pb_distro_only_deps_needed pb_distro_setuprepo pb_distro_get_param);

=pod

=head1 NAME

ProjectBuilder::Distribution, part of the project-builder.org - module dealing with distribution detection

=head1 DESCRIPTION

This modules provides functions to allow detection of Linux distributions, and giving back some attributes concerning them.

=head1 SYNOPSIS

  use ProjectBuilder::Distribution;

  # 
  # Return information on the running distro
  #
  my ($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch) = pb_distro_init();
  print "distro tuple: ".Dumper($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch)."\n";
  # 
  # Return information on the requested distro
  #
  my ($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch) = pb_distro_init("ubuntu","7.10","x86_64");
  print "distro tuple: ".Dumper($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch)."\n";
  # 
  # Return information on the running distro
  #
  my ($ddir,$dver) = pb_distro_get();
  my ($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch) = pb_distro_init($ddir,$dver);
  print "distro tuple: ".Dumper($ddir, $dver, $dfam, $dtype, $pbsuf, $pbupd, $arch)."\n";

=head1 USAGE

=over 4

=item B<pb_distro_init>

This function returns a list of 7 parameters indicating the distribution name, version, family, type of build system, suffix of packages, update command line and architecture of the underlying Linux distribution. The value of the 7 fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

As an example, Ubuntu and Debian are in the same "du" family. As well as RedHat, RHEL, CentOS, fedora are on the same "rh" family.
Mandriva, Open SuSE and Fedora have all the same "rpm" type of build system. Ubuntu ad Debian have the same "deb" type of build system. 
And "fc" is the extension generated for all Fedora packages (Version will be added by pb).

When passing the distribution name and version as parameters, the B<pb_distro_init> function returns the parameter of that distribution instead of the underlying one.

Cf: http://linuxmafia.com/faq/Admin/release-files.html
Ideas taken from http://search.cpan.org/~kerberus/Linux-Distribution-0.14/lib/Linux/Distribution.pm

=cut


sub pb_distro_init {

my $ddir = shift || undef;
my $dver = shift || undef;
my $dfam = "unknown";
my $dtype = "unknown";
my $dsuf = "unknown";
my $dupd = "unknown";
my $arch = shift || undef;

# If we don't know which distribution we're on, then guess it
($ddir,$dver) = pb_distro_get() if ((not defined $ddir) || (not defined $dver));

# Initialize arch
$arch=pb_get_arch() if (not defined $arch);

# There should be unicity of names between ddir dfam and dtype
# In case of duplicate, bad things can happen
if (($ddir =~ /debian/) ||
	($ddir =~ /ubuntu/)) {
	$dfam="du";
	$dtype="deb";
	$dsuf=".$ddir$dver";
	# Chaining the commands allow to only test for what is able o be installed, 
	# not the update of the repo which may well be unaccessible if too old
	$dupd="sudo apt-get update ; sudo apt-get -y install ";
} elsif ($ddir =~ /gentoo/) {
	$dfam="gen";
	$dtype="ebuild";
	$dver="nover";
	$dsuf=".$ddir";
	$dupd="sudo emerge ";
} elsif ($ddir =~ /slackware/) {
	$dfam="slack";
	$dtype="tgz";
	$dsuf=".$dfam$dver";
} elsif (($ddir =~ /suse/) ||
		($ddir =~ /sles/)) {
	$dfam="novell";
	$dtype="rpm";
	$dsuf=".$ddir$dver";
	$dupd="export TERM=linux ; export PATH=\$PATH:/sbin:/usr/sbin ; sudo yast2 -i ";
} elsif (($ddir =~ /redhat/) ||
		($ddir =~ /rhel/) ||
		($ddir =~ /fedora/) ||
		($ddir =~ /vmware/) ||
		($ddir =~ /asianux/) ||
		($ddir =~ /centos/)) {
	$dfam="rh";
	$dtype="rpm";
	my $dver1 = $dver;
	$dver1 =~ s/\.//;

	# By defaut propose yum
	my $opt = "";
	if ($arch eq "x86_64") {
		$opt="--exclude=*.i?86";
	}
	$dupd="sudo yum clean all; sudo yum -y update ; sudo yum -y $opt install ";
	if ($ddir =~ /fedora/) {
		$dsuf=".fc$dver1";
	} elsif ($ddir =~ /redhat/) {
		$dsuf=".rh$dver1";
		$dupd="unknown";
	} elsif ($ddir =~ /asianux/) {
		$dsuf=".asianux$dver1";
	} elsif ($ddir =~ /vmware/) {
		$dsuf=".vwm$dver1";
		$dupd="unknown";
	} else {
		# older versions of rhel ran up2date
		if ((($dver eq "2.1") || ($dver eq "3") || ($dver eq "4")) && ($ddir eq "rhel")) {
			$dupd="sudo up2date -y ";
		}
		$dsuf=".$ddir$dver1";
	}
} elsif (($ddir =~ /mandrake/) ||
		($ddir =~ /mandrakelinux/) ||
		($ddir =~ /mandriva/)) {
	$dfam="md";
	$dtype="rpm";
	if ($ddir =~ /mandrakelinux/) {
		$ddir = "mandrake";
	}
	if ($ddir =~ /mandrake/) {
		my $dver1 = $dver;
		$dver1 =~ s/\.//;
		$dsuf=".mdk$dver1";
	} else {
		$dsuf=".mdv$dver";
	}
	# Chaining the commands allow to only test for what is able o be installed, 
	# not the update of the repo which may well be unaccessible if too old
	$dupd="sudo urpmi.update -a ; sudo urpmi --auto ";
} elsif ($ddir =~ /freebsd/) {
	$dfam="bsd";
	$dtype="port";
	my $dver1 = $dver;
	$dver1 =~ s/\.//;
	$dsuf=".$dfam$dver1";
} else {
	$dfam="unknown";
}

return($ddir, $dver, $dfam, $dtype, $dsuf, $dupd, $arch);
}

=item B<pb_distro_get>

This function returns a list of 2 parameters indicating the distribution name and version of the underlying Linux distribution. The value of those 2 fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

On my home machine it would currently report ("mandriva","2009.0").

=cut

sub pb_distro_get {

my $base="/etc";

# List of files that unambiguously indicates what distro we have
my %single_rel_files = (
# Tested
	'gentoo'			=>	'gentoo-release',		# >= 1.6
	'slackware'			=>	'slackware-version',	# >= 10.2
	'mandriva'			=>	'mandriva-release',		# >=2006.0
	'mandrakelinux'		=>	'mandrakelinux-release',# = 10.2
	'fedora'			=>	'fedora-release',		# >= 4
	'vmware'			=>	'vmware-release',		# >= 3
	'sles'				=>	'sles-release',			# Doesn't exist as of 10
	'asianux'			=>	'asianux-release',		# >= 2.2
# Untested
	'knoppix'			=>	'knoppix_version',		#
	'yellowdog'			=>	'yellowdog-release',	#
	'esmith'			=>	'e-smith-release',		#
	'turbolinux'		=>	'turbolinux-release',	#
	'blackcat'			=>	'blackcat-release',		#
	'aurox'				=>	'aurox-release',		#
	'annvix'			=>	'annvix-release',		#
	'cobalt'			=>	'cobalt-release',		#
	'redflag'			=>	'redflag-release',		#
	'ark'				=>	'ark-release',			#
	'pld'				=>	'pld-release',			#
	'nld'				=>	'nld-release',			#
	'lfs'				=>	'lfs-release',			#
	'mk'				=>	'mk-release',			#
	'conectiva'			=>	'conectiva-release',	#
	'immunix'			=>	'immunix-release',		#
	'tinysofa'			=>	'tinysofa-release',		#
	'trustix'			=>	'trustix-release',		#
	'adamantix'			=>	'adamantix_version',	#
	'yoper'				=>	'yoper-release',		#
	'arch'				=>	'arch-release',			#
	'libranet'			=>	'libranet_version',		#
	'valinux'			=>	'va-release',			#
	'yellowdog'			=>	'yellowdog-release',	#
	'ultrapenguin'		=>	'ultrapenguin-release',	#
	);

# List of files that ambiguously indicates what distro we have
my %ambiguous_rel_files = (
	'mandrake'			=>	'mandrake-release',		# <= 10.1
	'debian'			=>	'debian_version',		# >= 3.1
	'suse'				=>	'SuSE-release',			# >= 10.0
	'redhat'			=>	'redhat-release',		# >= 7.3
	'lsb'				=>	'lsb-release',			# ???
	);

# Should have the same keys as the previous one.
# If ambiguity, which other distributions should be checked
my %distro_similar = (
	'mandrake'			=> ['mandrake', 'mandrakelinux'],
	'debian'			=> ['debian', 'ubuntu'],
	'suse'				=> ['suse', 'sles', 'opensuse'],
	'redhat'			=> ['redhat', 'rhel', 'centos', 'mandrake', 'vmware'],
	'lsb'				=> ['ubuntu', 'lsb'],
	);

my %distro_match = (
# Tested
	'gentoo'				=> '.* version (.+)',
	'slackware'			 	=> 'S[^ ]* (.+)$',
# There should be no ambiguity between potential ambiguous distro
	'mandrakelinux'			=> 'Mandrakelinux release (.+) \(',
	'mandrake'				=> 'Mandr[^ ]* release (.+) \(',
	'mandriva'				=> 'Mandr[^ ]* [^ ]* release (.+) \(',
	'fedora'				=> 'Fedora .*release (\d+) \(',
	'vmware'				=> 'VMware ESX Server (\d+) \(',
	'rhel'					=> 'Red Hat (?:Enterprise Linux|Linux Advanced Server) .*release ([0-9.]+).* \(',
	'centos'				=> '.*CentOS .*release ([0-9]).* ',
	'redhat'				=> 'Red Hat Linux release (.+) \(',
	'sles'					=> 'SUSE .* Enterprise Server (\d+) \(',
	'suse'					=> 'SUSE LINUX (\d.+) \(',
	'opensuse'				=> 'openSUSE (\d.+) \(',
	'asianux'				=> 'Asianux (?:Server|release) ([0-9]).* \(',
	'lsb'					=> '.*[^Ubunt].*\nDISTRIB_RELEASE=(.+)',
# Ubuntu includes a /etc/debian_version file that creates an ambiguity with debian
# So we need to look at distros in reverse alphabetic order to treat ubuntu always first
	'ubuntu'				=> '.*Ubuntu.*\nDISTRIB_RELEASE=(.+)',
	'debian'				=> '(.+)',
# Not tested
	'arch'					=> '.* ([0-9.]+) .*',
	'redflag'				=> 'Red Flag (?:Desktop|Linux) (?:release |\()(.*?)(?: \(.+)?\)',
);

my $release;
my $distro;

# Begin to test presence of non-ambiguous files
# that way we reduce the choice
my ($d,$r);
while (($d,$r) = each %single_rel_files) {
	if (-f "$base/$r" && ! -l "$base/$r") {
		my $tmp=pb_get_content("$base/$r");
		# Found the only possibility. 
		# Try to get version and return
		if (defined ($distro_match{$d})) {
			($release) = $tmp =~ m/$distro_match{$d}/m;
		} else {
			print STDERR "Unable to find $d version in $r\n";
			print STDERR "Please report to the maintainer bruno_at_project-builder.org\n";
			$release = "unknown";
		}
		return($d,$release);
	}
}

# Now look at ambiguous files
# Ubuntu includes a /etc/debian_version file that creates an ambiguity with debian
# So we need to look at distros in reverse alphabetic order to treat ubuntu always first via lsb
foreach $d (reverse keys %ambiguous_rel_files) {
	$r = $ambiguous_rel_files{$d};
	if (-f "$base/$r" && !-l "$base/$r") {
		# Found one possibility. 
		# Get all distros concerned by that file
		my $tmp=pb_get_content("$base/$r");
		my $found = 0;
		my $ptr = $distro_similar{$d};
		pb_log(2,"amb: ".Dumper($ptr)."\n");
		$release = "unknown";
		foreach my $dd (@$ptr) {
			pb_log(2,"check $dd\n");
			# Try to check pattern
			if (defined $distro_match{$dd}) {
				pb_log(2,"cmp: $distro_match{$dd} - vs - $tmp\n");
				($release) = $tmp =~ m/$distro_match{$dd}/m;
				if ((defined $release) && ($release ne "unknown")) {
					$distro = $dd;
					$found = 1;
					last;
				}
			}
		}
		if ($found == 0) {
			print STDERR "Unable to find $d version in $r\n";
			print STDERR "Please report to the maintainer bruno_at_project-builder.org\n";
			$release = "unknown";
		} else {
			return($distro,$release);
		}
	}
}
return("unknown","unknown");
}


=over 4

=item B<pb_distro_installdeps>

This function install the dependencies required to build the package on an RPM based distro
dependencies can be passed as a parameter in which case they are not computed

=cut

sub pb_distro_installdeps {

# SPEC file
my $f = shift || undef;
my $dtype = shift || undef;
my $dupd = shift || undef;
my $deps = shift || undef;

# Protection
return if (not defined $dupd);

# Get dependecies in the build file if not forced
$deps = pb_distro_getdeps("$f", $dtype) if (not defined $deps);
pb_log(2,"deps: $deps\n");
return if ((not defined $deps) || ($deps =~ /^\s*$/));
if ($deps !~ /^[ 	]*$/) {
	pb_system("$dupd $deps","Installing dependencies ($deps)");
	}
}

=over 4

=item B<pb_distro_getdeps>

This function computes the dependencies indicated in the build file and return them as a string of packages to install

=cut

sub pb_distro_getdeps {

my $f = shift || undef;
my $dtype = shift || undef;

my $regexp = "";
my $deps = "";
my $sep = $/;

pb_log(3,"entering pb_distro_getdeps: $dtype - $f\n");
# Protection
return("") if (not defined $dtype);
if ($dtype eq  "rpm") {
	# In RPM this could include files, but we do not handle them atm.
	$regexp = '^BuildRequires:(.*)$';
} elsif ($dtype eq "deb") {
	$regexp = '^Build-Depends:(.*)$';
} elsif ($dtype eq "ebuild") {
	$sep = '"'.$/;
	$regexp = '^DEPEND="(.*)"\n'
} else {
	# No idea
	return("");
}
pb_log(2,"regexp: $regexp\n");


# Protection
return("") if (not defined $f);

# Preserve separator before using the one we need
my $oldsep = $/;
$/ = $sep;
open(DESC,"$f") || die "Unable to open $f";
while (<DESC>) {
	pb_log(4,"read: $_\n");
	next if (! /$regexp/);
	chomp();
	# What we found with the regexp is the list of deps.
	pb_log(2,"found deps: $_\n");
	s/$regexp/$1/i;
	# Remove conditions in the middle and at the end for deb
	s/\(\s*[><=]+.*\)\s*,/,/g;
	s/\(\s*[><=]+.*$//g;
	# Same for rpm
	s/[><=]+.*,/,/g;
	s/[><=]+.*$//g;
	# Improve string format (remove , and spaces at start, end and in double
	s/,/ /g;
	s/^\s*//;
	s/\s*$//;
	s/\s+/ /g;
	$deps .= " ".$_;
}
close(DESC);
$/ = $oldsep;
pb_log(2,"now deps: $deps\n");
my $deps2 = pb_distro_only_deps_needed($dtype,$deps);
return($deps2);
}


=over 4

=item B<pb_distro_only_deps_needed>

This function returns only the dependencies not yet installed

=cut

sub pb_distro_only_deps_needed {

my $dtype = shift || undef;
my $deps = shift || undef;

return("") if ((not defined $deps) || ($deps =~ /^\s*$/));
my $deps2 = "";
# Avoid to install what is already there
foreach my $p (split(/ /,$deps)) {
	if ($dtype eq  "rpm") {
		my $res = pb_system("rpm -q --whatprovides --quiet $p","","quiet");
		next if ($res eq 0);
	} elsif ($dtype eq "deb") {
		my $res = pb_system("dpkg -L $p","","quiet");
		next if ($res eq 0);
	} elsif ($dtype eq "ebuild") {
	} else {
		# Not reached
	}
	pb_log(2,"found deps2: $p\n");
	$deps2 .= " $p";
}

$deps2 =~ s/^\s*//;
pb_log(2,"now deps2: $deps2\n");
return($deps2);
}

=over 4

=item B<pb_distro_setuprepo>

This function sets up potential additional repository to the build environment

=cut

sub pb_distro_setuprepo {

my $ddir = shift || undef;
my $dver = shift;
my $darch = shift;
my $dtype = shift || undef;

my ($addrepo) = pb_conf_read("$ENV{'PBDESTDIR'}/pbrc","addrepo");
return if (not defined $addrepo);

my $param = pb_distro_get_param($ddir,$dver,$darch,$addrepo);
return if ($param eq "");

# Loop on the list of additional repo
foreach my $i (split(/,/,$param)) {

	my ($scheme, $account, $host, $port, $path) = pb_get_uri($i);
	my $bn = basename($i);

	# The repo file can be local or remote. download or copy at the right place
	if (($scheme eq "ftp") || ($scheme eq "http")) {
		pb_system("wget -O $ENV{'PBTMP'}/$bn $i","Donwloading additional repository file $i");
	} else {
		copy($i,$ENV{'PBTMP'}/$bn);
	}

	# The repo file can be a real file or a package
	if ($dtype eq "rpm") {
		if ($bn =~ /\.rpm$/) {
			my $pn = $bn;
			$pn =~ s/\.rpm//;
			if (pb_system("rpm -q --quiet $pn","","quiet") != 0) {
				pb_system("sudo rpm -Uvh $ENV{'PBTMP'}/$bn","Adding package to setup repository");
			}
		} elsif ($bn =~ /\.repo$/) {
			# Yum repo
			pb_system("sudo mv $ENV{'PBTMP'}/$bn /etc/yum.repos.d","Adding yum repository") if (not -f "/etc/yum.repos.d/$bn");
		} elsif ($bn =~ /\.addmedia/) {
			# URPMI repo
			# We should test that it's not already a urpmi repo
			pb_system("chmod 755 $ENV{'PBTMP'}/$bn ; sudo $ENV{'PBTMP'}/$bn 2>&1 > /dev/null","Adding urpmi repository");
		} else {
			pb_log(0,"Unable to deal with repository file $i on rpm distro ! Please report to dev team\n");
		}
	} elsif ($dtype eq "deb") {
		if (($bn =~ /\.sources.list$/) && (not -f "/etc/apt/sources.list.d/$bn")) {
			pb_system("sudo mv $ENV{'PBTMP'}/$bn /etc/apt/sources.list.d","Adding apt repository");
			pb_system("sudo apt-get update","Updating apt repository");
		} else {
			pb_log(0,"Unable to deal with repository file $i on deb distro ! Please report to dev team\n");
		}
	} else {
		pb_log(0,"Unable to deal with repository file $i on that distro ! Please report to dev team\n");
	}
}
return;
}

=over 4

=item B<pb_distro_get_param>

This function gets the parameter in the conf file from the most precise tuple up to default

=cut

sub pb_distro_get_param {

my $param = "";
my $ddir = shift;
my $dver = shift;
my $darch = shift;
my $opt = shift;

if (defined $opt->{"$ddir-$dver-$darch"}) {
	$param = $opt->{"$ddir-$dver-$darch"};
} elsif (defined $opt->{"$ddir-$dver"}) {
	$param = $opt->{"$ddir-$dver"};
} elsif (defined $opt->{"$ddir"}) {
	$param = $opt->{"$ddir"};
} elsif (defined $opt->{"default"}) {
	$param = $opt->{"default"};
} else {
	$param = "";
}
return($param);

}


=back 

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
