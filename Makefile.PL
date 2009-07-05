use 5.006001;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'ProjectBuilder',
    DISTNAME     => 'ProjectBuilder',
    VERSION      => '0.9.7.1',
    INST_SCRIPT  => 'blib/bin',
	INSTALLDIRS  => 'perl',
    PREREQ_PM    => {
			#HTTP::Headers                    => 1.59,
			#Template                         => 0,
    },    # e.g., Module::Name => 1.1
	#ABSTRACT_FROM => 'bin/pb',   # retrieve abstract from module
    AUTHOR        => 'Bruno Cornec <bruno#project-builder.org>',
	EXE_FILES     => [ qw( bin/pbdistrocheck ) ],
	MAN3PODS      => {	'lib/ProjectBuilder/Distribution.pm' => '$(INST_MAN3DIR)/ProjectBuilder::Distribution.$(MAN3EXT)',
						'lib/ProjectBuilder/Conf.pm' => '$(INST_MAN3DIR)/ProjectBuilder::Conf.$(MAN3EXT)',
						'lib/ProjectBuilder/Display.pm' => '$(INST_MAN3DIR)/ProjectBuilder::Display.$(MAN3EXT)',
						'lib/ProjectBuilder/Base.pm' => '$(INST_MAN3DIR)/ProjectBuilder::Base.$(MAN3EXT)', },
);
