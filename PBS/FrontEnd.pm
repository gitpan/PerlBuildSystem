
package PBS::FrontEnd ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Carp ;
use Time::HiRes qw(gettimeofday tv_interval) ;

require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.30_1' ;

use PBS::PBSConfig ;
use PBS::PBS ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Documentation ;
use PBS::Plugin ;

#-------------------------------------------------------------------------------

my $pbs_root_index = 0 ; # uniq identifier
my $pbs_run_index = 0 ; # depth of the PBS run
my $display_pbs_run ;

sub Pbs
{
my $t0 = [gettimeofday];

my %pbs_arguments = @_ ;
my @switches = @{$pbs_arguments{COMMAND_LINE_ARGUMENTS}} ;

PBS::Plugin::ScanForPlugins(@switches) ; # plugins might add switches

my ($parse_result, $pbs_config, @unparsed_arguments) = PBS::PBSConfig::ParseSwitches(@switches) ;

if(exists $pbs_arguments{PBS_CONFIG})
	{
	$pbs_config = {%$pbs_config, %{$pbs_arguments{PBS_CONFIG}} } ;
	}

$pbs_config->{PBSFILE_CONTENT} = $pbs_arguments{PBSFILE_CONTENT} if exists $pbs_arguments{PBSFILE_CONTENT} ;

my $display_help              = $pbs_config->{DISPLAY_HELP} ;
my $display_switch_help       = $pbs_config->{DISPLAY_SWITCH_HELP} ;
my $display_help_narrow       = $pbs_config->{DISPLAY_HELP_NARROW_DISPLAY} || 0 ;
my $display_version           = $pbs_config->{DISPLAY_VERSION} ;
my $display_user_help         = $pbs_config->{DISPLAY_USER_HELP} ;
my $display_raw_user_help     = $pbs_config->{DISPLAY_RAW_USER_HELP} ;
my $display_pod_documentation = $pbs_config->{DISPLAY_POD_DOCUMENTATION} ;

if($display_help || $display_switch_help || $display_version || $display_user_help || $display_raw_user_help || defined $display_pod_documentation)
	{
	PBS::PBSConfigSwitches::DisplayHelp($display_help_narrow) if $display_help ;
	PBS::PBSConfigSwitches::DisplaySwitchHelp($display_switch_help) if $display_switch_help ;
	PBS::PBSConfigSwitches::DisplayUserHelp($pbs_config->{PBSFILE} , $display_raw_user_help) if $display_user_help || $display_raw_user_help ;
	DisplayVersion() if $display_version ;
	
	PBS::Documentation::DisplayPodDocumentation($pbs_config, $display_pod_documentation) if defined $display_pod_documentation ;
	
	return(1) ;
	}

if(defined $pbs_config->{DISPLAY_LAST_LOG})
	{
	PBS::Log::DisplayLastestLog($pbs_config->{DISPLAY_LAST_LOG}) ;
	return(1) ;
	}

if(defined $pbs_config->{WIZARD})
	{
	eval "use PBS::Wizard;" ;
	die $@ if $@ ;

	PBS::Wizard::RunWizard
		(
		  $pbs_config->{LIB_PATH}
		, undef
		, $pbs_config->{WIZARD}
		, $pbs_config->{DISPLAY_WIZARD_INFO}
		, $pbs_config->{DISPLAY_WIZARD_HELP}
		) ;
		
	return(1) ;
	}

unless($parse_result->[PARSE_SWITCH_SUCCESS])
	{
	return(0, $parse_result->[PARSE_SWITCH_MESSAGE]) ;
	}

#-------------------------------------------------------------------------------------------
# run PBS
#-------------------------------------------------------------------------------------------

$display_pbs_run++ if defined $pbs_config->{DISPLAY_PBS_RUN} ;
PrintInfo2 "** PBS run $pbs_run_index **\n" if $display_pbs_run ;

if(defined $pbs_config->{CREATE_LOG})
	{
	my $lh = $pbs_config->{CREATE_LOG} ;
	print $lh "** PBS run $pbs_run_index **\n";
	}

$pbs_run_index++ ;

PrintInfo($parse_result->[PARSE_SWITCH_MESSAGE]) ;

my $targets =
	[
	map
				{
				my $target = $_ ;
				
				$target = $_ if File::Spec->file_name_is_absolute($_) ; # full path
				$target = $_ if /^.\// ; # current dir (that's the build dir)
				$target = "./$_" unless /^[.\/]/ ;
				
				$target ;
				} @unparsed_arguments
	] ;

$pbs_config->{PACKAGE} = 'PBS' ;

# make the variables bellow accessible from a post pbs script
our $build_success = 1 ;
our ($dependency_tree, $inserted_nodes) = ({}, {}) ;

if(@$targets)
	{
	$DB::single = 1 ;

	$pbs_root_index++ ;

	eval
		{
		if(defined $pbs_config->{USE_WARP_FILE})
			{
			eval "use PBS::Warp ;" ;
			die $@ if $@ ;
			
			($dependency_tree, $inserted_nodes) = PBS::Warp::WarpPbs
						(
						  $targets
						, $pbs_config
						) ;
			}
		elsif(defined $pbs_config->{USE_WARP1_5_FILE})
			{
			eval "use PBS::Warp1_5 ;" ;
			die $@ if $@ ;
			
			($dependency_tree, $inserted_nodes) = PBS::Warp1_5::WarpPbs
						(
						  $targets
						, $pbs_config
						) ;
			}
		else
			{
			($dependency_tree, $inserted_nodes) = PBS::PBS::Pbs
				(
				$pbs_config->{PBSFILE}
				, ''    # parent package
				, $pbs_config
				, {}    # parent config
				, $targets
				, undef # inserted files
				, "root_${pbs_root_index}_pbs_$pbs_config->{PBSFILE}" # tree name
				, DEPEND_CHECK_AND_BUILD
				) ;
			}
		#else
			# warp run pbs itself
		} ;

	$build_success = 0 if($@) ;

	if($@ && $@ !~ /BUILD_FAILED/)
		{
		print STDERR $@ ;
		}
	}
else
	{
	PrintError("No targets given on the command line!\n") ;
	$build_success = 0 ;
	}

$pbs_run_index-- ;
PrintInfo2 "** PBS run $pbs_run_index Done **\n" if $display_pbs_run ;

if(defined $pbs_config->{CREATE_LOG})
	{
	my $lh = $pbs_config->{CREATE_LOG} ;
	print $lh "** PBS run $pbs_run_index Done **\n";
	}

RunPluginSubs('PostPbs', $build_success, $pbs_config, $dependency_tree, $inserted_nodes) ;

my $run = 0 ;
for my $post_pbs (@{$pbs_config->{POST_PBS}})
	{
	$run++ ;
	
	eval
		{
		PBS::PBS::LoadFileInPackage
			(
			''
			, $post_pbs
			, "PBS::POST_PBS_$run"
			, $pbs_config
			, "use strict ;\nuse warnings ;\n"
			  . "use PBS::Output ;\n"
			  . "my \$pbs_config = \$PBS::FrontEnd::pbs_config ;\n"
			  . "my \$build_success = \$PBS::FrontEnd::build_success ;\n"
			  . "my \$dependency_tree = \$PBS::FrontEnd::dependency_tree ;\n"
			  . "my \$inserted_nodes = \$PBS::FrontEnd::inserted_nodes ; \n"
			) ;
		} ;

	PrintError("Couldn't run post pbs script '$post_pbs':\n   $@") if $@ ;
	}


if($pbs_config->{DISPLAY_PBS_TOTAL_TIME})
	{
	PrintInfo(sprintf("Total time in PBS: %0.2f s.\n", tv_interval ($t0, [gettimeofday]))) ;
	}

return($build_success, 'PBS run ' . ($pbs_run_index + 1) . " building '@$targets' with '$pbs_config->{PBSFILE}'\n") ;
}

#-------------------------------------------------------------------------------

sub DisplayVersion
{
print <<EOH ;

This is the Perl Build System, PBS, version $VERSION 

Copyright 2002-2005, Nadim Khemir and Anders Lindgren.

This is a free software with a very restrictive licence.
See the license.txt file for the condition of use.

PBS comes with NO warranty. If you need a warranty, a completely
unafordable licencing fee can be arranged.

Send all suggestions and inqueries to <nadim\@khemir.net>.

EOH
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::FrontEnd  -

=head1 SYNOPSIS

  use PBS::FrontEnd ;
  PBS::FrontEnd::Pbs(@ARGV) ;

=head1 DESCRIPTION

Entry point into B<PBS>.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut

