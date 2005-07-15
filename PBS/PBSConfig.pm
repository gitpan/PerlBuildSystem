
package PBS::PBSConfig ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;

require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GetPbsConfig PARSE_SWITCH_SUCCESS PARSE_SWITCH_MESSAGE CollapsePath) ;
our $VERSION = '0.03' ;

use Getopt::Long ;
use Pod::Parser ;
use Cwd ;
use File::Spec;

use PBS::Output ;
use PBS::Log ;
use PBS::Constants ;
use PBS::PBSConfigSwitches ;

use constant PARSE_SWITCH_SUCCESS => 0 ;
use constant PARSE_SWITCH_MESSAGE => 1 ;

#-------------------------------------------------------------------------------

my %pbs_configuration ;

sub RegisterPbsConfig
{
my $package  = shift ;
my $configuration= shift ;

if(ref $configuration eq 'HASH')
	{
	$pbs_configuration{$package} = $configuration;
	}
else
	{
	PrintError("RegisterPbsConfig: switches are to be encapsulated within a hash reference!\n") ;
	}
}

#-------------------------------------------------------------------------------

sub GetPbsConfig
{
my $package  = shift || caller() ;

if(defined $pbs_configuration{$package})
	{
	return($pbs_configuration{$package}) ;
	}
else
	{
	PrintWarning("GetPbsConfig: no configuration for package '$package'! Returning empty set.\n") ;
	Carp::confess ;
	return({}) ;
	}
}

#-------------------------------------------------------------------------------

sub ParseSwitches
{
my $success_message = '' ;

Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case', 'require_order') ;

my %pbs_config = (ORIGINAL_ARGV => join(' ', @ARGV)) ;
my @flags = PBS::PBSConfigSwitches::Get_GetoptLong_Data(\%pbs_config) ;

local @ARGV = ( # default colors
		  '-ci'  => 'green'
		, '-ci2' => 'bold blue'
		, '-cw'  => 'yellow'
		, '-cw2' => 'blink yellow'
		, '-ce'  => 'red'
		, '-cd'  => 'magenta'
		, '-cs'  => 'bold green'
		, '-cu'  => 'cyan'
		) ;
		
unless(GetOptions(@flags))
	{
	return([0, "Error in default colors configuration." . __FILE__ . ':' . __LINE__ . "\n"], \%pbs_config, @ARGV) ;
	}

@ARGV = @_ ;

for (my $argument_index = 0 ; $argument_index < @ARGV ; $argument_index++)
	{
	if($ARGV[$argument_index] =~ /(-nge)|(-no_global_environement)/)
		{
		$pbs_config{NO_GLOBAL_ENVIRONEMENT}++ ;
		}

	if($ARGV[$argument_index] =~ /(-nprf)|(-no_pbs_response_file)/)
		{
		$pbs_config{NO_PBS_RESPONSE_FILE}++ ;
		}

	if($ARGV[$argument_index] =~ /(-prf)|(-pbs_response_file)/)
		{
		$pbs_config{PBS_RESPONSE_FILE} = $_[$argument_index + 1] || '' ;
		$argument_index += 1 ;
		}
	}
	
# tweek option parsing so we can mix switches with targets
my $contains_switch ;
my @targets ;

do
	{
	while(@ARGV && $ARGV[0] !~ /^-/)
		{
		#~ print "target => $ARGV[0] \n" ;
		push @targets, shift @ARGV ;
		}
		
	$contains_switch = @ARGV ;
	
	unless(GetOptions(@flags))
		{
		return([0, "Try perl pbs.pl -h.\n"], \%pbs_config, @ARGV) ;
		}
	}
while($contains_switch) ;

unless(defined $pbs_config{NO_PBS_RESPONSE_FILE})
	{
	my ($status, $data) = ParsePrfSwitches(\%pbs_config, @flags) ;
	
	for ($status)
		{
		$status == CONFIG_PRF_SUCCESS and do
			{
			push @targets, @$data ;
			last ;
			} ;
			
		$status == CONFIG_PRF_ERROR and do
			{
			return([0, $data. "\n"], \%pbs_config, @ARGV) ;
			} ;
			
		$status == CONFIG_PRF_FLAG_ERROR and do
			{
			return([0, "Pbs response file '$data' contains unrecognized options. Try -h.\n"], \%pbs_config, @ARGV) ;
			} ;
		}
	}

unless(defined $pbs_config{NO_GLOBAL_ENVIRONEMENT})
	{
	my ($status) = ParseEnvironementSwitches(\%pbs_config, @flags) ;
	
	if($status == CONFIG_ENVIRONEMENT_VARIABLE_FLAG_ERROR)
		{
		return([0, "Environement variable 'PBS_FLAGS=$ENV{PBS_FLAGS}' contains unrecognized options. Try -h.\n"], \%pbs_config, @ARGV) ;
		}
	}
	
#-------------------------------------------------------------------------------
# check the options
if(defined $pbs_config{DISPLAY_DEPENDENCY_INFO})
	{
	delete $pbs_config{DISPLAY_COMPACT_DEPEND_INFORMATION} ;
	}
	
#~ use Data::Validate::IP qw(is_ipv4 is_loopback_ipv4);
#~ if(exists $pbs_config{LIGHT_WEIGHT_FORK})
	#~ {
	#~ my ($server, $port) = split(':', $pbs_config{LIGHT_WEIGHT_FORK}) ;
	
	#~ unless(is_ipv4($server) || is_loopback_ipv4($server))
		#~ {
		#~ die ERROR "Error: IP error '$pbs_config{LIGHT_WEIGHT_FORK}' to -ubs\n" ;
		#~ }
	#~ }
	
# segmentation fault because of missing ':' and use statement placement.
#~ if(exists $pbs_config{LIGHT_WEIGHT_FORK})
	#~ {
	#~ my ($server, $port) = split(':', $pbs_config{LIGHT_WEIGHT_FORK}) ;
	#~ use Net:IP ;
	#~ my $ip = new Net::IP ($server) or die ERROR 'Error: invalid IP given to -ubs' ;
	#~ }
	
if(defined $pbs_config{DISPLAY_COMPACT_DEPEND_INFORMATION})
	{
	$pbs_config{NO_SUBPBS_INFO}++ ;
	}
	
if(defined $pbs_config{DISPLAY_NO_PROGRESS_BAR})
	{
	delete $pbs_config{DISPLAY_PROGRESS_BAR} ;
	}
	
if(defined $pbs_config{DISPLAY_PROGRESS_BAR})
	{
	$PBS::Shell::silent_commands++ ;
	$PBS::Shell::silent_commands_output++ ;
	$pbs_config{DISPLAY_NO_BUILD_HEADER}++ ;
	}
	
if(defined $pbs_config{NO_WARP})
	{
	delete $pbs_config{USE_WARP1_5_FILE} ;
	}
	
$pbs_config{USE_WARP_FILE}++ if defined $pbs_config{USE_WARP2_FILE} ;

if(defined $pbs_config{DISPLAY_PBS_TIME})
	{
	$pbs_config{DISPLAY_PBS_TOTAL_TIME}++ ;
	$pbs_config{DISPLAY_TOTAL_BUILD_TIME}++ ;
	$pbs_config{DISPLAY_TOTAL_DEPENDENCY_TIME}++ ;
	$pbs_config{DISPLAY_CHECK_TIME}++ ;
	$pbs_config{DISPLAY_WARP_TIME}++ ;
	}

if($pbs_config{DISPLAY_DEPENDENCY_TIME})
	{
	$pbs_config{DISPLAY_TOTAL_DEPENDENCY_TIME}++ ;
	}

if($pbs_config{NO_SUBPBS_INFO} || $pbs_config{DISPLAY_COMPACT_DEPEND_INFORMATION})
	{
	undef $pbs_config{DISPLAY_DEPENDENCY_TIME} ;
	}

if($pbs_config{TIME_BUILDERS})
	{
	$pbs_config{DISPLAY_TOTAL_BUILD_TIME}++ ;
	}

$pbs_config{DISPLAY_PBSUSE_TIME}++ if(defined $pbs_config{DISPLAY_PBSUSE_TIME_ALL}) ;

$pbs_config{DISPLAY_HELP}++ if defined $pbs_config{DISPLAY_HELP_NARROW_DISPLAY} ;

$pbs_config{DEBUG_DISPLAY_RULES}++ if defined $pbs_config{DEBUG_DISPLAY_RULE_DEFINITION} ;

$pbs_config{DISPLAY_USED_RULES}++ if defined $pbs_config{DISPLAY_USED_RULES_NAME_ONLY} ;
	
$pbs_config{DEBUG_DISPLAY_DEPENDENCIES}++ if defined $pbs_config{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION} ;

if(@{$pbs_config{DISPLAY_DEPENDENCIES_REGEX}})
	{
	$pbs_config{DEBUG_DISPLAY_DEPENDENCIES}++ ;
	}
else
	{
	push @{$pbs_config{DISPLAY_DEPENDENCIES_REGEX}}, '.*' ;
	}

$pbs_config{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES} = undef if(defined $pbs_config{DEBUG_DISPLAY_DEPENDENCIES}) ;

$pbs_config{DISPLAY_DIGEST}++ if defined $pbs_config{DISPLAY_DIFFERENT_DIGEST_ONLY} ;


$pbs_config{DISPLAY_SEARCH_INFO}++ if defined $pbs_config{DISPLAY_SEARCH_ALTERNATES} ;

if(defined $pbs_config{BUILD_AND_DISPLAY_NODE_INFO} || @{$pbs_config{DISPLAY_BUILD_INFO}} || @{$pbs_config{DISPLAY_NODE_INFO}})
	{
	undef $pbs_config{BUILD_AND_DISPLAY_NODE_INFO} if (@{$pbs_config{DISPLAY_BUILD_INFO}}) ;
	
	$pbs_config{DISPLAY_NODE_ORIGIN}++ ;
	$pbs_config{DISPLAY_NODE_DEPENDENCIES}++ ;
	$pbs_config{DISPLAY_NODE_BUILD_CAUSE}++ ;
	$pbs_config{DISPLAY_NODE_BUILD_RULES}++ ;
	$pbs_config{DISPLAY_NODE_BUILDER}++ ;
	$pbs_config{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS}++ ;
	
	undef $pbs_config{DISPLAY_NO_BUILD_HEADER} ;
	}
	
# ------------------------------------------------------------------------------

$pbs_config{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY} = undef if(defined $pbs_config{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY}) ;

$pbs_config{GENERATE_TREE_GRAPH_DISPLAY_CONFIG}++ if(defined $pbs_config{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE}) ;
$pbs_config{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG}++ if(defined $pbs_config{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE}) ;

for my $cluster_node_regex (@{$pbs_config{GENERATE_TREE_GRAPH_CLUSTER_NODE}})
	{
	#~ print "$cluster_node_regex " ;
	
	$cluster_node_regex = './' . $cluster_node_regex unless ($cluster_node_regex =~ /^\.|\//) ;
	$cluster_node_regex =~ s/\./\\./g ;
	$cluster_node_regex =~ s/\*/.*/g ;
	$cluster_node_regex = '^' . $cluster_node_regex . '$' ;
	
	#~ print "=> $cluster_node_regex\n" ;
	}

for my $exclude_node_regex (@{$pbs_config{GENERATE_TREE_GRAPH_EXCLUDE}})
	{
	#~ print "$exclude_node_regex => " ;
	$exclude_node_regex =~ s/\./\\./g ;
	$exclude_node_regex =~ s/\*/.\*/g ;
	#~ print "$exclude_node_regex\n" ;
	}

for my $include_node_regex (@{$pbs_config{GENERATE_TREE_GRAPH_INCLUDE}})
	{
	#~ print "$include_node_regex => " ;
	$include_node_regex =~ s/\./\\./g ;
	$include_node_regex =~ s/\*/.\*/g ;
	#~ print "$include_node_regex\n" ;
	}
	
#-------------------------------------------------------------------------------
# build or not switches
if($pbs_config{NO_BUILD} && $pbs_config{FORCE_BUILD})
	{
	return([0, "-force_build and -no_build switch can't be given simulteanously\n"], {}, []) ;
	}
	
$pbs_config{DO_BUILD} = 0 if $pbs_config{NO_BUILD} ;

unless($pbs_config{FORCE_BUILD})
	{
	while(my ($debug_flag, $value) = each %pbs_config) 
		{
		if($debug_flag =~ /^DEBUG/ && defined $value)
			{
			$pbs_config{DO_BUILD} = 0 ;
			keys %pbs_config;
			last ;
			}
		}
	}
#-------------------------------------------------------------------------------

$pbs_config{DISPLAY_FILE_LOCATION}++ if $pbs_config{DISPLAY_ALL_FILE_LOCATION} ;
$pbs_config{DEBUG_DISPLAY_BUILD_SEQUENCE}++ if defined $pbs_config{DEBUG_DISPLAY_BUILD_SEQUENCE_NAME_ONLY} ;

$Data::Dumper::Maxdepth = $pbs_config{MAX_DEPTH} if defined $pbs_config{MAX_DEPTH} ;
$Data::Dumper::Indent   = $pbs_config{INDENT_STYLE} if defined $pbs_config{INDENT_STYLE} ;

if(defined $pbs_config{DISTRIBUTE} && ! defined $pbs_config{JOBS})
	{
	$pbs_config{JOBS} = 0 ; # let distributor determine how many jobs
	}

if(defined $pbs_config{JOBS} && $pbs_config{JOBS} < 0)
	{
	return([0, "Invalid value '$pbs_config{JOBS}' for switch -j/-jobs\n"], \%pbs_config, @ARGV) ;
	}
	
if(defined $pbs_config{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON})
	{
	$pbs_config{DEBUG_DISPLAY_TREE_NODE_TRIGGERED} = 1 ;
	}

if(defined $pbs_config{DEBUG_DISPLAY_TREE_NAME_ONLY})
	{
	$pbs_config{DEBUG_DISPLAY_TEXT_TREE} = '' unless $pbs_config{DEBUG_DISPLAY_TEXT_TREE} ;
	}
	
if(defined $pbs_config{DISPLAY_TEXT_TREE_USE_ASCII})
	{
	$pbs_config{DISPLAY_TEXT_TREE_USE_ASCII} = 1 ;
	}
else
	{
	$pbs_config{DISPLAY_TEXT_TREE_USE_ASCII} = 0 ;
	}

$pbs_config{DISPLAY_TEXT_TREE_MAX_DEPTH} = -1 unless defined $pbs_config{DISPLAY_TEXT_TREE_MAX_DEPTH} ;

#--------------------------------------------------------------------------------

$Data::TreeDumper::Startlevel = 1 ;
$Data::TreeDumper::Useascii   = $pbs_config{DISPLAY_TEXT_TREE_USE_ASCII} ;
$Data::TreeDumper::Maxdepth   = $pbs_config{DISPLAY_TEXT_TREE_MAX_DEPTH} ;

#--------------------------------------------------------------------------------

unless(defined $pbs_config{PBSFILE})
	{
	my @pbsfile_names;
	if($^O eq 'MSWin32')
		{
		@pbsfile_names = qw(pbsfile.pl pbsfile) ;
		}
	else
		{
		@pbsfile_names = qw(Pbsfile.pl pbsfile.pl Pbsfile pbsfile) ;
		}

	my %existing_pbsfile = map{( $_ => 1)} grep { -e "./$_"} @pbsfile_names ;
	
	if(keys %existing_pbsfile)
		{
		if(keys %existing_pbsfile == 1)
			{
			my ($pbsfile) = keys %existing_pbsfile ;
			$pbs_config{PBSFILE} = $pbsfile ;
			}
		else
			{
			my $error_message = "PBS has found the following Pbsfiles:\n" ;
			
			for my $pbsfile (keys %existing_pbsfile)
				{
				$error_message .= "\t$pbsfile\n" ;
				}
				
			$error_message .= "Only one can be defined!\n" ;
			
			return([0, $error_message], \%pbs_config, @ARGV) ;
			}
		}
	else
		{
		return([0, "No 'Pbsfile' to define build.\n"], \%pbs_config, @ARGV) ;
		}
	}

$pbs_config{PBSFILE} = './' . $pbs_config{PBSFILE} unless $pbs_config{PBSFILE}=~ /^\.|\// ;

for my $target (@targets)
	{
	if($target =~ /^\@/ || $target =~ /\@$/ || $target =~ /\@/ > 1)
		{
		return([0, "Invalid composite target definition\n"], \%pbs_config, @targets) ;
		}

	if($target =~ /@/)
		{
		return([0, "Only one composite target allowed\n"], \%pbs_config, @targets) if @targets > 1 ;
		}
	}

my $cwd = getcwd() ;
if(0 == @{$pbs_config{SOURCE_DIRECTORIES}})
	{
	push @{$pbs_config{SOURCE_DIRECTORIES}}, $cwd ;
	$success_message .= "No source directory! Using '$cwd'.\n" ;
	}

for my $plugin_path (@{$pbs_config{PLUGIN_PATH}})
	{
	unless(File::Spec->file_name_is_absolute($plugin_path))
		{
		$plugin_path = File::Spec->catdir($cwd, $plugin_path)  ;
		}
		
	$plugin_path = PBS::PBSConfig::CollapsePath($plugin_path ) ;
	}
	
unless(defined $pbs_config{BUILD_DIRECTORY})
	{
	if(defined $pbs_config{MANDATORY_BUILD_DIRECTORY})
		{
		return([0, "No Build directory given and --mandatory_build_directory set.\n"], \%pbs_config, @targets) ;
		}
	else
		{
		my $default_build_directory = $cwd . "/out_" . $ENV{USER} ;

		$success_message .= "No Build directory! Using '$default_build_directory'.\n" ;
		$pbs_config{BUILD_DIRECTORY} = $default_build_directory ;
		}
	}

CheckPackageDirectories(\%pbs_config) ;

#----------------------------------------- Log -----------------------------------------
undef $pbs_config{CREATE_LOG} if defined $pbs_config{DISPLAY_LAST_LOG} ;

PBS::Log::CreatePbsLog(\%pbs_config) if(defined $pbs_config{CREATE_LOG}) ;

#--------------------------------------------------------------------------------

return([1, $success_message ], \%pbs_config, @targets) ;
}

#-------------------------------------------------------------------------------

sub ParseEnvironementSwitches
{
my ($config, @flags) = @_ ;

if(exists $ENV{PBS_FLAGS})
	{
	local @ARGV = () ;
	
	$ENV{PBS_FLAGS} =~ s/^\s*// ;
	$ENV{PBS_FLAGS} =~ s/\s*$// ;
	
	unshift @ARGV, map
			{
			s/^\s*// ; s/\s*$// ;
			if (/([^ ]+)\ (.*)/)
				{
				("-$1", $2) ;
				}
			else
				{
				"-$_" ; 
				}
			} grep {/./ ;} split /-+/, $ENV{PBS_FLAGS} ;
				
	unless(GetOptions(@flags))
		{
		return(CONFIG_ENVIRONEMENT_VARIABLE_FLAG_ERROR) ;
		}
	}

my $path_separator = $^O eq "MSWin32" ? ';' : ':';

if(exists $ENV{PBS_LIB_PATH})
	{
	push @{$config->{LIB_PATH}}, split(/$path_separator/, $ENV{PBS_LIB_PATH}) ;
	}
	
if(exists $ENV{PBS_PLUGIN_PATH})
	{
	push @{$config->{PLUGIN_PATH}}, split(/$path_separator/, $ENV{PBS_PLUGIN_PATH}) ;
	}

return(CONFIG_ENVIRONEMENT_VARIABLE_FLAG_SUCCESS) ;
}

#-------------------------------------------------------------------------------

sub ParsePrfSwitches
{
my $config = shift ;
my @flags = @_ ;

my (@prf_switches, @prf_targets) ;
my ($prf_ok, $prf_message) = (1, 'no prf.') ;
my $pbs_response_file ;

unless(defined $config->{NO_ANONYMOUS_PBS_RESPONSE_FILE})
	{
	$pbs_response_file = 'Pbs.prf' if(-e 'Pbs.prf') ;
	}

$pbs_response_file = "$ENV{USER}.prf" if(-e "$ENV{USER}.prf") ;

$pbs_response_file = $config->{PBS_RESPONSE_FILE} if(defined $config->{PBS_RESPONSE_FILE}) ;
	
if($pbs_response_file)
	{
	$config->{PBS_RESPONSE_FILE} = $pbs_response_file ;
	($prf_ok, $prf_message) = ParsePbsResponseFile($pbs_response_file, \@prf_switches, \@prf_targets) ;
	
	if($prf_ok)
		{
		$config->{PBS_RESPONSE_FILE_SWITCHES} = \@prf_switches ;
		$config->{PBS_RESPONSE_FILE_TARGETS} = \@prf_targets ;
		
		if(@prf_switches)
			{
			local @ARGV = @prf_switches ;
			
			unless(GetOptions(@flags))
				{
				return(CONFIG_PRF_FLAG_ERROR, $pbs_response_file) ;
				}
			}
		}
	else
		{
		return(CONFIG_PRF_ERROR, $prf_message) ;
		}
	}

return(CONFIG_PRF_SUCCESS, \@prf_targets) ;
}

#-------------------------------------------------------------------------------

sub ParsePbsResponseFile
{
my $response_file = shift ;
my $prf_switches  = shift ;
my $prf_targets   = shift ;

if(-e $response_file)
	{
	if(open PRF, '<', $response_file)
		{
		while(<PRF>)
			{
			/^([^#]+)/ ;
			my $input = $1 ;
			
			next unless $input ;
			next if $input =~ /^\s*$/ ;
			$input =~ s/\s+$// ;
			
			chomp $input ;
			
			while(/\$([a-zA-Z_0-9]+)/g)
				{
				unless(exists $ENV{$1})
					{
					PrintWarning("Can't evaluate '\$$1' in Pbs response file '$response_file':$..\n") ;
					}
				}
			
			$input =~ s/\$([a-zA-Z_0-9]+)/exists $ENV{$1} ? $ENV{$1} : ''/ge ;
			
			if($input =~ /^--?/)
				{
				#~ print "switch: '$input'\n" ;
				push @$prf_switches, split /\s+/, $input ;
				}
			else
				{
				#~ print "target: '$input'\n" ;
				push @$prf_targets, split /\s+/, $input ;
				}
			}
			
		return(1, "ParsePbsResponseFile OK.") ;
		}
	else
		{
		return(0, "ParsePbsResponseFile: Can't open Pbs response file '$response_file': $!.") ;
		}
	}
else
	{
	return(0, "Pbs response file '$response_file' doesn't exist.\n") ;
	}
}

#-------------------------------------------------------------------------------

sub CollapsePath
{
my $path_with_only_slashes;
($path_with_only_slashes = File::Spec->canonpath($_[0])) =~ s|\\|/|g;
return $path_with_only_slashes;
}

#-------------------------------------------------------------------------------

sub CheckPackageDirectories
{
my $pbs_config = shift ;

my $cwd = getcwd() ;

if(defined $pbs_config->{SOURCE_DIRECTORIES})
	{
	for my $source_directory (@{$pbs_config->{SOURCE_DIRECTORIES}})
		{
		unless(File::Spec->file_name_is_absolute($source_directory))
			{
			$source_directory = File::Spec->catdir($cwd, $source_directory) ;
			}
			
		$source_directory = CollapsePath($source_directory) ;
		}
	}
	
if(defined $pbs_config->{BUILD_DIRECTORY})
{
	unless(File::Spec->file_name_is_absolute($pbs_config->{BUILD_DIRECTORY}))
		{
		$pbs_config->{BUILD_DIRECTORY} = File::Spec->catdir($cwd, $pbs_config->{BUILD_DIRECTORY}) ;
		}
		
	$pbs_config->{BUILD_DIRECTORY} = CollapsePath($pbs_config->{BUILD_DIRECTORY}) ;
	}
}

#-------------------------------------------------------------------------------

1 ;

#-------------------------------------------------------------------------------

__END__
=head1 NAME

PBS::PBSConfig  -

=head1 DESCRIPTION

Module handling PBS configuration. Every loaded package has a configuration. The first configuration, loaded
through the I<pbs> utility is stored in the 'PBS' package and is influenced by I<pbs> command line switches.
Subsequent configurations are loaded when a subpbs is run. The configuration name and contents reflect the loaded package parents
and the subpbs configuration.

I<GetPbsConfig> can be used, in Pbsfiles, to get the current pbs configuration. The configuration name is __PACKAGE__. The returned scalar
is a reference to the configuration hash.

	# in a Pbsfile
	use Data::TreeDumper ;
	
	my $pbs_config = GetPbsConfig(__PACKAGE__) ;
	PrintInfo(DumpTree( $pbs_config->{SOURCE_DIRECTORIES}, "Source directories")) ;

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
