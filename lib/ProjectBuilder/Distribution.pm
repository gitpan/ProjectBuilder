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
our @EXPORT = qw(pb_distro_conffile pb_distro_init pb_distro_get pb_distro_installdeps pb_distro_getdeps pb_distro_only_deps_needed pb_distro_setuprepo pb_distro_get_param);

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

=item B<pb_distro_conffile>

This function returns the mandatory configuration file used for distribution/OS detection

=cut

sub pb_distro_conffile {

return("CCCC/pb.conf");
}


=item B<pb_distro_init>

This function returns a list of 7 parameters indicating the distribution name, version, family, type of build system, suffix of packages, update command line and architecture of the underlying Linux distribution. The value of the 7 fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

As an example, Ubuntu and Debian are in the same "du" family. As well as RedHat, RHEL, CentOS, fedora are on the same "rh" family.
Mandriva, Open SuSE and Fedora have all the same "rpm" type of build system. Ubuntu ad Debian have the same "deb" type of build system. 
And "fc" is the extension generated for all Fedora packages (Version will be added by pb).
All these information are stored in an external configuration file typically at /etc/pb/pb.conf

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
my $darch = shift || undef;
my $dnover = "false";
my $drmdot = "false";

# Adds conf file for distribution description
# the location of the conf file is finalyzed at install time
# depending whether we deal with package install or tar file install
pb_conf_add(pb_distro_conffile());

# If we don't know which distribution we're on, then guess it
($ddir,$dver) = pb_distro_get() if ((not defined $ddir) || (not defined $dver));

# Initialize arch
$darch=pb_get_arch() if (not defined $darch);

my ($osfamily,$ostype,$osupd,$ossuffix,$osnover,$osremovedotinver) = pb_conf_get("osfamily","ostype","osupd","ossuffix","osnover","osremovedotinver");

# Dig into the tuple to find the best answer
$dfam = pb_distro_get_param($ddir,$dver,$darch,$osfamily);
$dtype = $ostype->{$dfam} if (defined $ostype->{$dfam});
$dupd = pb_distro_get_param($ddir,$dver,$darch,$osupd,$dfam,$dtype);
$dsuf = pb_distro_get_param($ddir,$dver,$darch,$ossuffix,$dfam,$dtype);
$dnover = pb_distro_get_param($ddir,$dver,$darch,$osnover,$dfam,$dtype);
$drmdot = pb_distro_get_param($ddir,$dver,$darch,$osremovedotinver,$dfam,$dtype);

# Some OS have no interesting version
$dver = "nover" if ($dnover eq "true");

# For some OS remove the . in version name
$dver =~ s/\.// if ($drmdot eq "true");

if ((not defined $dsuf) || ($dsuf eq "")) {
	# By default suffix is a concatenation of .ddir and dver
	$dsuf = ".$ddir$dver" 
} else {
	# concat just the version to what has been found
	$dsuf = ".$dsuf$dver";
}

#	if ($arch eq "x86_64") {
#	$opt="--exclude=*.i?86";
#	}
pb_log(2,"DEBUG: pb_distro_init: $ddir, $dver, $dfam, $dtype, $dsuf, $dupd, $darch\n");

return($ddir, $dver, $dfam, $dtype, $dsuf, $dupd, $darch);
}

=item B<pb_distro_get>

This function returns a list of 2 parameters indicating the distribution name and version of the underlying Linux distribution. The value of those 2 fields may be "unknown" in case the function was unable to recognize on which distribution it is running.

On my home machine it would currently report ("mandriva","2009.0").

=cut

sub pb_distro_get {

# 1: List of files that unambiguously indicates what distro we have
# 2: List of files that ambiguously indicates what distro we have
# 3: Should have the same keys as the previous one. If ambiguity, which other distributions should be checked
# 4: Matching Rg. Expr to detect distribution and version
my ($single_rel_files, $ambiguous_rel_files,$distro_similar,$distro_match) = pb_conf_get("osrelfile","osrelambfile","osambiguous","osrelexpr");

my $release;
my $distro;

# Begin to test presence of non-ambiguous files
# that way we reduce the choice
my ($d,$r);
while (($d,$r) = each %$single_rel_files) {
	if (-f "$r" && ! -l "$r") {
		my $tmp=pb_get_content("$r");
		# Found the only possibility. 
		# Try to get version and return
		if (defined ($distro_match->{$d})) {
			($release) = $tmp =~ m/$distro_match->{$d}/m;
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
foreach $d (reverse keys %$ambiguous_rel_files) {
	$r = $ambiguous_rel_files->{$d};
	if (-f "$r" && !-l "$r") {
		# Found one possibility. 
		# Get all distros concerned by that file
		my $tmp=pb_get_content("$r");
		my $found = 0;
		my $ptr = $distro_similar->{$d};
		pb_log(2,"amb: ".Dumper($ptr)."\n");
		$release = "unknown";
		foreach my $dd (split(/,/,$ptr)) {
			pb_log(2,"check $dd\n");
			# Try to check pattern
			if (defined $distro_match->{$dd}) {
				pb_log(2,"cmp: $distro_match->{$dd} - vs - $tmp\n");
				($release) = $tmp =~ m/$distro_match->{$dd}/m;
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
$deps = pb_distro_getdeps($f, $dtype) if (not defined $deps);
pb_log(2,"deps: $deps\n");
return if ((not defined $deps) || ($deps =~ /^\s*$/));
if ($deps !~ /^[ 	]*$/) {
	pb_system("$dupd $deps","Installing dependencies ($deps)");
	}
}

=item B<pb_distro_getdeps>

This function computes the dependencies indicated in the build file and return them as a string of packages to install

=cut

sub pb_distro_getdeps {

my $f = shift || undef;
my $dtype = shift || undef;

my $regexp = "";
my $deps = "";
my $sep = $/;

# Protection
return("") if (not defined $dtype);
return("") if (not defined $f);

pb_log(3,"entering pb_distro_getdeps: $dtype - $f\n");
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
	s/\(\s*[><=]+.*\)[^,]*,/,/g;
	s/\(\s*[><=]+.*$//g;
	# Same for rpm
	s/[><=]+[^,]*,/,/g;
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

=item B<pb_distro_get_param>

This function gets the parameter in the conf file from the most precise tuple up to default

=cut

sub pb_distro_get_param {

my $param = "";
my $ddir = shift;
my $dver = shift;
my $darch = shift;
my $opt = shift;
my $dfam = shift || "unknown";
my $dtype = shift || "unknown";

if (defined $opt->{"$ddir-$dver-$darch"}) {
	$param = $opt->{"$ddir-$dver-$darch"};
} elsif (defined $opt->{"$ddir-$dver"}) {
	$param = $opt->{"$ddir-$dver"};
} elsif (defined $opt->{"$ddir"}) {
	$param = $opt->{"$ddir"};
} elsif (defined $opt->{$dfam}) {
	$param = $opt->{$dfam};
} elsif (defined $opt->{$dtype}) {
	$param = $opt->{$dtype};
} elsif (defined $opt->{"default"}) {
	$param = $opt->{"default"};
} else {
	$param = "";
}

# Allow replacement of variables inside the parameter such as ddir, dver, darch for rpmbootstrap 
# but not shell variable which ae backslashed
if ($param =~ /[^\\]\$/) {
	pb_log(3,"Expanding variable on $param\n");
	eval { $param =~ s/(\$\w+)/$1/eeg };
}

pb_log(2,"DEBUG: pb_distro_get_param on $ddir-$dver-$darch returns ==$param==\n");
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
