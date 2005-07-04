
package PBS::Plugin;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(ScanForPlugins RunPluginSubs RunUniquePluginSub) ;
our $VERSION = '0.03' ;

use File::Basename ;
use Getopt::Long ;
use Cwd ;

use PBS::Constants ;
use PBS::PBSConfig ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my %loaded_plugins ;
my $config = 
	{
	PLUGIN_PATH => []
	} ;

#-------------------------------------------------------------------------------

sub ScanForPlugins
{
ParseSwitches(@_) ;

for my $plugin_path (@{$config->{PLUGIN_PATH}})
	{
	PrintInfo "Plugin directory '$plugin_path':\n" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
	
	my $plugin_load = 0 ;
	for my $plugin (glob("$plugin_path/*.pm"))
		{
		if(exists $loaded_plugins{$plugin})
			{
			PrintInfo "   Ignoring Already loaded '$plugin'.\n" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
			next ;
			}
			
		if($config->{DISPLAY_PLUGIN_LOAD_INFO})
			{
			my ($basename, $path, $ext) = File::Basename::fileparse($plugin, ('\..*')) ;
			PrintInfo "   $basename$ext\n" ;
			}
			
		$plugin_load++ ;
		
		eval
			{
			PBS::PBS::LoadFileInPackage
				(
				''
				, $plugin
				, "PBS::PLUGIN_$plugin_load"
				, {}
				, "use strict ;\nuse warnings ;\n"
				  . "use PBS::Output ;\n"
				) ;
			} ;
			
		die ERROR("Couldn't load plugin from '$plugin':\n   $@") if $@ ;
		
		$loaded_plugins{$plugin}++ ;
		}
	}
}

#-------------------------------------------------------------------------------

sub RunPluginSubs
{
# run multiple subs, don't return anything

my $plugin_sub_name = shift ;

my $plugin_load = 0 ;

for my $plugin_path (keys %loaded_plugins)
	{
	no warnings ;

	$plugin_load++ ;
	
	my $plugin_sub ;
	
	eval "\$plugin_sub = *PBS::PLUGIN_${plugin_load}::${plugin_sub_name}{CODE} ;" ;
	
	if($plugin_sub)
		{
		PrintInfo "Running '$plugin_sub_name' in plugin '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		
		eval {$plugin_sub->(@_)} ;
		die ERROR "Error Running plugin sub '$plugin_sub_name':\n$@" if $@ ;
		}
	else
		{
		PrintWarning "Couldn't find '$plugin_sub_name' in plugin '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	}
}

#-------------------------------------------------------------------------------

sub RunUniquePluginSub
{
# run a single sub and returns

my $plugin_sub_name = shift ;

my ($plugin_load, @found_plugin, $plugin_path, $plugin_sub) = (0) ;
my ($plugin_sub_to_run, $plugin_to_run_path) ;

for $plugin_path (keys %loaded_plugins)
	{
	no warnings ;

	$plugin_load++ ;
	eval "\$plugin_sub = *PBS::PLUGIN_${plugin_load}::${plugin_sub_name}{CODE} ;" ;
	push @found_plugin, $plugin_path if($plugin_sub) ;

	if($plugin_sub)
		{
		$plugin_sub_to_run = $plugin_sub ;
		$plugin_to_run_path = $plugin_path ;
		PrintInfo "Found '$plugin_sub_name' in plugin '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	else
		{
		PrintWarning "Couldn't find '$plugin_sub_name' in plugin '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	}
	
if(@found_plugin > 1)
	{
	die ERROR "Error: Found more than one plugin for '$plugin_sub_name'\n" . join("\n", @found_plugin) . "\n" ;
	}

if($plugin_sub_to_run)
	{
	PrintInfo "Running '$plugin_sub_name' in plugin '$plugin_to_run_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
	
	if(! defined wantarray)
		{
		eval {$plugin_sub_to_run->(@_)} ;
		die ERROR "Error Running plugin sub '$plugin_sub_name':\n$@" if $@ ;
		}
	else
		{
		if(wantarray)
			{
			my @results ;
			eval {@results = $plugin_sub_to_run->(@_)} ;
			die ERROR "Error Running plugin sub '$plugin_sub_name':\n$@" if $@ ;
			
			return(@results) ;
			}
		else
			{
			my $result ;
			eval {$result = $plugin_sub_to_run->(@_)} ;
			die ERROR "Error Running plugin sub '$plugin_sub_name':\n$@" if $@ ;
			
			return($result) ;
			}
		}
		
	}
else
	{
	PrintWarning "Couldn't find Plugin '$plugin_sub_name'.\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
	}
}

#-------------------------------------------------------------------------------

sub ParseSwitches
{
my @switches = @_ ;

Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case', 'require_order') ;
my @flags = PBS::PBSConfigSwitches::Get_GetoptLong_Data($config) ;

{ # localized scope

local @ARGV = ( # default colors so the user only need to say --colorize
		  '-ci'  => 'green'
		, '-ci2' => 'blink green'
		, '-cw'  => 'yellow'
		, '-cw2' => 'blink yellow'
		, '-ce'  => 'red'
		, '-cd'  => 'magenta'
		, '-cs'  => 'bold green'
		, '-cu'  => 'cyan'
		) ;
		
unless(GetOptions(@flags))
	{
	die ERROR "Error in default colors configuration." ;
	}

@ARGV = @switches ;

for (my $argument_index = 0 ; $argument_index < @ARGV ; $argument_index++)
	{
	if($ARGV[$argument_index] =~ /(-nge)|(-no_global_environement)/)
		{
		$config->{NO_GLOBAL_ENVIRONEMENT}++ ;
		}

	if($ARGV[$argument_index] =~ /(-nprf)|(-no_pbs_response_file)/)
		{
		$config->{NO_PBS_RESPONSE_FILE}++ ;
		}

	if($ARGV[$argument_index] =~ /(-prf)|(-pbs_response_file)/)
		{
		$config->{PBS_RESPONSE_FILE} = $_[$argument_index + 1] || '' ;
		$argument_index += 1 ;
		}
	}

unless(defined $config->{NO_GLOBAL_ENVIRONEMENT})
	{
	my $status = PBS::PBSConfig::ParseEnvironementSwitches($config, @flags) ;
	
	if($status == CONFIG_ENVIRONEMENT_VARIABLE_FLAG_ERROR)
		{
		die ERROR "Environement variable 'PBS_FLAGS=$ENV{PBS_FLAGS}' contains unrecognized options. Try -h.\n" ;
		}
	}

unless(defined $config->{NO_PBS_RESPONSE_FILE})
	{
	my ($status, $data) = PBS::PBSConfig::ParsePrfSwitches($config, @flags) ;
	
	for ($status)
		{
		$status == CONFIG_PRF_ERROR and do
			{
			die ERROR $data ;
			} ;
			
		$status == CONFIG_PRF_FLAG_ERROR and do
			{
			die ERROR "Pbs response file '$data' contains unrecognized options. Try -h.\n" ;
			} ;
		}
	}

# make switch parsing position independent
my $contains_switch ;

do
	{
	while(@ARGV && $ARGV[0] !~ /^-/)
		{
		shift @ARGV ;
		}
		
	$contains_switch = @ARGV ;
	
	# plugin switches are not know yet
	local $SIG{'__WARN__'} = sub {print STDERR $_[0] unless $_[0] =~ 'Unknown option:'} ;
	
	unless(GetOptions(@flags))
		{
		shift @ARGV ; # error in switch just ignore, will be detected later
		}
	}
while($contains_switch) ;
} # end of localized scope

my $cwd = cwd() ;
for my $plugin_path (@{$config->{PLUGIN_PATH}})
	{
	unless(File::Spec->file_name_is_absolute($plugin_path))
		{
		$plugin_path = File::Spec->catdir($cwd, $plugin_path)  ;
		}
		
	$plugin_path = PBS::PBSConfig::CollapsePath($plugin_path ) ;
	}

}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Plugin  - Handle Plugins in PBS

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 LIMITATIONS

plugins can't hadle the same switch (switch registred by a plugin, pbs switches OK when passed to plugin)

=head2 EXPORT

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
