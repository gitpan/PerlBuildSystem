
package PBS::Warp1_5 ;
use PBS::Debug ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.03' ;

#-------------------------------------------------------------------------------

use PBS::Output ;
use PBS::Check ;
use PBS::Log ;
use PBS::Digest ;
use PBS::Constants ;

use Cwd ;
use File::Path;
use Data::Dumper ;
use Data::Compare ;
use Data::TreeDumper ;
use Digest::MD5 qw(md5_hex) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

#-------------------------------------------------------------------------------

sub GetWarpSignature
{
my ($targets, $pbs_config) = @_ ;

#construct a file name depends on targets and -D and -u switches, etc ...
my $pbs_prf = $pbs_config->{PBS_RESPONSE_FILE} || '' ;
my $pbs_flags = $ENV{PBS_FLAGS} || '' ; 
my $pbs_lib_path = $ENV{PBS_LIB_PATH} || '' ;

my $warp_signature = md5_hex
		(
		  join('_', @$targets) 
		
		. $pbs_config->{PBSFILE}
		
		. DumpTree($pbs_config->{COMMAND_LINE_DEFINITIONS}, '', USE_ASCII => 1)
		. DumpTree($pbs_config->{USER_OPTIONS}, '', USE_ASCII => 1) 
		
		. $pbs_prf
		. $pbs_flags
		. $pbs_lib_path
		) ;

return($warp_signature) ;
}

#-------------------------------------------------------------------------------

sub WarpPbs
{
my $targets = shift ;
my $pbs_config = shift ;

my $warp_signature = GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} ;
my $warp_file= "$warp_path/Pbsfile_$warp_signature.warp1_5.pl" ;

PrintInfo "Warp 1.5 file name: '$warp_file'\n" if defined $pbs_config->{DISPLAY_WARP_FILE_NAME} ;

our ($nodes, $node_names, $global_pbs_config, $insertion_file_names) ;
our ($warp_1_5_version, $number_of_nodes_in_the_dependency_tree, $warp_configuration) ;

my $run_in_warp_mode = 1 ;
my $t0_warp_check = [gettimeofday];

if(-e $warp_file)
	{
	do $warp_file or die ERROR("Couldn't evaluate warp file '$warp_file'\nFile error: $!\nCompilation error: $@\n") ;
	
	PrintInfo "Verifying warp 1.5: $number_of_nodes_in_the_dependency_tree nodes ...\n" ;
	
	unless(defined $warp_1_5_version)
		{
		PrintWarning2("Warp 1.5: bad version. Warp file needs to be rebuilt.\n") ;
		unlink($warp_file) ;
		
		$run_in_warp_mode = 0 ;
		}
		
	unless($warp_1_5_version == $VERSION)
		{
		PrintWarning2("Warp 1.5: bad version. Warp file needs to be rebuilt.\n") ;
		unlink($warp_file) ;
		
		$run_in_warp_mode = 0 ;
		}
		
	# check if all pbs files are still the same
	if(0 == CheckFilesMD5($warp_configuration))
		{
		PrintWarning2("Warp 1.5: Differences in Pbsfiles. Warp file needs to be rebuilt.\n") ;
		unlink($warp_file) ;
		
		$run_in_warp_mode = 0 ;
		}
	}
else
	{
	PrintWarning("Warp 1.5 file '$warp_file' doesn't exist.\n") ;
	$run_in_warp_mode = 0 ;
	}

if($run_in_warp_mode)
	{
	my $number_of_removed_nodes = 0 ;
	
	# check md5 and remove all nodes that would trigger
	my $node_verified = 0 ;
	for my $node (keys %$nodes)
		{
		PrintInfo "\r$node_verified" ;
		$node_verified++ ;
		
		next unless exists $nodes->{$node} ; # can have been removed by one of its dependencies
		
		my $remove_this_node = 0 ;
		
		if('VIRTUAL' eq $nodes->{$node}{__MD5})
			{
			# virtual nodes don't have MD5
			}
		else
			{
			# rebuild the build name
			if(exists $nodes->{$node}{__LOCATION})
				{
				$nodes->{$node}{__BUILD_NAME} = $nodes->{$node}{__LOCATION} . substr($node, 1) ;
				}
			else
				{
				$nodes->{$node}{__BUILD_NAME} = $node ;
				}
				
			if(defined (my $current_md5 = GetFileMD5($nodes->{$node}{__BUILD_NAME})))
				{
				unless($current_md5 eq $nodes->{$node}{__MD5})
					{
					if($pbs_config->{DISPLAY_WARP_TRIGGERED_NODES})	
						{
						PrintDebug "\nWarp: '$nodes->{$node}{__BUILD_NAME}' MD5 mismatch\n" ;
						}
						
					$remove_this_node++ ;
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_WARP_TRIGGERED_NODES})	
					{
					PrintDebug "\nWarp: '$nodes->{$node}{__BUILD_NAME}' No such file $@\n" ;
					}
					
				$remove_this_node++ ;
				}
			}
			
		$remove_this_node++ if(exists $nodes->{$node}{__FORCED}) ;
		
		if($remove_this_node) #and its dependents and its triggerer if any
			{
			my @nodes_to_remove = ($node) ;
			
			while(@nodes_to_remove)
				{
				my @dependent_nodes ;
				
				for my $node_to_remove (grep{ exists $nodes->{$_} } @nodes_to_remove)
					{
					if($pbs_config->{DISPLAY_WARP_TRIGGERED_NODES})	
						{
						PrintDebug "Warp: Removing node '$node_to_remove'\n" ;
						}
					
					push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} @{$nodes->{$node_to_remove}{__DEPENDENT}} ;
					
					# remove triggering node and its dependents
					if(exists $nodes->{$node_to_remove}{__TRIGGER_INSERTED})
						{
						my $trigerring_node = $nodes->{$node_to_remove}{__TRIGGER_INSERTED} ;
						push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} @{$nodes->{$trigerring_node}{__DEPENDENT}} ;
						delete $nodes->{$trigerring_node} ;
						}
						
					delete $nodes->{$node_to_remove} ;
					
					$number_of_removed_nodes++ ;
					}
					
				if($pbs_config->{DISPLAY_WARP_TRIGGERED_NODES})	
					{
					PrintDebug '-' x 30 . "\n" ;
					}
					
				@nodes_to_remove = @dependent_nodes ;
				}
			}
		else
			{
			# rebuild the data PBS needs from the warp file
			$nodes->{$node}{__NAME} = $node ;
			$nodes->{$node}{__BUILD_DONE} = "Field set in warp 1.5" ;
			$nodes->{$node}{__DEPENDED}++ ;
			$nodes->{$node}{__CHECKED}++ ; # pbs will not check any node (and its subtree) which is marked as checked
			
			$nodes->{$node}{__PBS_CONFIG} = $global_pbs_config unless exists $nodes->{$node}{__PBS_CONFIG} ;
			
			$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_names->[$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE}] ;
			
			unless(exists $nodes->{$node}{__DEPENDED_AT})
				{
				$nodes->{$node}{__DEPENDED_AT} = $nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
				}
				
			#let our dependent nodes know about their dependencies
			#this needed when regenerating the warp file from partial warp data
			for my $dependent (map {$node_names->[$_]} @{$nodes->{$node}{__DEPENDENT}})
				{
				if(exists $nodes->{$dependent})
					{
					$nodes->{$dependent}{$node}++ ;
					}
				}
			}
		}
	
	PrintInfo "\r" ;
	
	if($pbs_config->{DISPLAY_WARP_TIME})
		{
		PrintInfo(sprintf("Warp 1.5 verification time: %0.2f s.\n", tv_interval($t0_warp_check, [gettimeofday]))) ;
		}
	
	if($number_of_removed_nodes)
		{
		if(defined $pbs_config->{DISPLAY_WARP_TREE})
			{
			}
			
		if(defined $pbs_config->{DISPLAY_WARP_BUILD_SEQUENCE})
			{
			}
			
		eval "use PBS::PBS" ;
		die $@ if $@ ;
		
		unless($pbs_config->{DISPLAY_WARP_GENERATED_WARNINGS})
			{
			$pbs_config->{NO_LINK_INFO} = 1 ;
			$pbs_config->{NO_LOCAL_MATCHING_RULES_INFO} = 1 ;
			}
			
		# we can't  generate a warp file while warping.
		# The warp configuration (pbsfiles md5) would be truncated
		# to the files used during the warp
		delete $pbs_config->{GENERATE_WARP1_5_FILE} ;
		
		# much of the "normal" node attributes are stripped in warp nodes
		# let the rest of the system know about this (ex graph generator)
		$pbs_config->{IN_WARP} = 1 ;
		my $new_dependency_tree ;
		
		eval
			{
			# PBS will link to the  warp nodes instead for regenerating them
			my $node_plural = '' ; $node_plural = 's' if $number_of_removed_nodes > 1 ;
			
			PrintInfo "Running PBS in warp 1.5 mode. $number_of_removed_nodes node$node_plural to rebuild.\n" ;
			($new_dependency_tree) = PBS::PBS::Pbs
								(
								  $pbs_config->{PBSFILE}
								, ''    # parent package
								, $pbs_config
								, {}    # parent config
								, $targets
								, $nodes
								, "warp_tree"
								, DEPEND_CHECK_AND_BUILD
								) ;
			} ;
			
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occures only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					  $targets, $new_dependency_tree, $nodes
					, $pbs_config, $warp_configuration
					) ;
				}
				
			# died during depend or check
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				  $targets, $new_dependency_tree, $nodes
				, $pbs_config, $warp_configuration
				) ;
			}
			
		return($new_dependency_tree, $nodes) ;
		}
	else
		{
		PrintInfo("Warp 1.5: Up to date.\n") ;
		return({WARP_1_5_DPENDENCY_TREE => "doesn't really exist."}, $nodes) ;
		}
	}
else
	{
	#eurk hack we could dispense with!
	# this is not needed but the subpses are travesed an extra time
	
	my ($dependency_tree_snapshot, $inserted_nodes_snapshot) ;
	
	$pbs_config->{INTERMEDIATE_WARP_WRITE} = 
		sub
		{
		my $dependency_tree = shift ;
		my $inserted_nodes = shift ;
		
		($dependency_tree_snapshot, $inserted_nodes_snapshot) = ($dependency_tree, $inserted_nodes) ;
		
		GenerateWarpFile
			(
			  $targets
			, $dependency_tree
			, $inserted_nodes
			, $pbs_config
			) ;
		} ;
		
	my ($dependency_tree, $inserted_nodes) ;
	eval
		{
		($dependency_tree, $inserted_nodes) = PBS::PBS::Pbs
							(
							$pbs_config->{PBSFILE}
							, ''    # parent package
							, $pbs_config
							, {}    # parent config
							, $targets
							, undef # inserted files
							, "root_WARP_1_5_NEEDS_REBUILD_pbs_$pbs_config->{PBSFILE}" # tree name
							, DEPEND_CHECK_AND_BUILD
							) ;
		} ;
		
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occures only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					  $targets
					, $dependency_tree_snapshot
					, $inserted_nodes_snapshot
					, $pbs_config
					) ;
				}
				
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				  $targets
				, $dependency_tree
				, $inserted_nodes
				, $pbs_config
				) ;
			}
			
	return($dependency_tree, $inserted_nodes) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub GenerateWarpFile
{
# indexing the node name  saves another 10% in size
# indexing the location name saves another 10% in size

my ($targets, $dependency_tree, $inserted_nodes, $pbs_config, $warp_configuration) = @_ ;

$warp_configuration = GetWarpConfiguration($pbs_config, $warp_configuration) ; #$warp_configuration can be undef or from a warp file

PrintInfo("Generating warp 1.5 file.               \n") ;
my $t0_warp_generate =  [gettimeofday] ;

my $warp_signature = GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} ;
mkpath($warp_path) unless(-e $warp_path) ;

my $warp_file= "$warp_path/Pbsfile_$warp_signature.warp1_5.pl" ;

my $global_pbs_config = # cache to reduce warp file size
	{
	  BUILD_DIRECTORY    => $pbs_config->{BUILD_DIRECTORY}
	, SOURCE_DIRECTORIES => $pbs_config->{SOURCE_DIRECTORIES}
	} ;
	
my $number_of_nodes_in_the_dependency_tree = keys %$inserted_nodes ;

my ($nodes, $node_names, $insertion_file_names) = WarpifyTree1_5($inserted_nodes, $global_pbs_config) ;

open(WARP, ">", $warp_file) or die qq[Can't open $warp_file: $!] ;
print WARP PBS::Log::GetHeader('Warp', $pbs_config) ;

local $Data::Dumper::Purity = 1 ;
local $Data::Dumper::Indent = 1 ;
local $Data::Dumper::Sortkeys = undef ;

print WARP Data::Dumper->Dump([$global_pbs_config], ['global_pbs_config']) ;

print WARP Data::Dumper->Dump([ $nodes], ['nodes']) ;

print WARP "\n" ;
print WARP Data::Dumper->Dump([$node_names], ['node_names']) ;

print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$insertion_file_names], ['insertion_file_names']) ;

print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$warp_configuration], ['warp_configuration']) ;
print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$VERSION], ['warp_1_5_version']) ;
print WARP Data::Dumper->Dump([$number_of_nodes_in_the_dependency_tree], ['number_of_nodes_in_the_dependency_tree']) ;

print WARP "\n\n" ;
close(WARP) ;

if($pbs_config->{DISPLAY_WARP_TIME})
	{
	PrintInfo(sprintf("Warp 1.5 generated in: %0.2f s.\n", tv_interval($t0_warp_generate, [gettimeofday]))) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub WarpifyTree1_5
{
my $inserted_nodes = shift ;
my $global_pbs_config = shift ;

my ($package, $file_name, $line) = caller() ;

my (%nodes, @node_names, %nodes_index) ;
my (@insertion_file_names, %insertion_file_index) ;

for my $node (keys %$inserted_nodes)
	{
	# this doesn't work with LOCAL_NODES
	
	if(exists $inserted_nodes->{$node}{__VIRTUAL})
		{
		$nodes{$node}{__VIRTUAL} = 1 ;
		}
	else
		{
		# here some attempt to start handling AddDependency and micro warps
		#$nodes{$node}{__DIGEST} = GetDigest($inserted_nodes->{$node}) ;
		}
		
	if(exists $inserted_nodes->{$node}{__FORCED})
		{
		$nodes{$node}{__FORCED} = 1 ;
		}

	if(!exists $inserted_nodes->{$node}{__VIRTUAL} && $node =~ /^\.(.*)/)
		{
		($nodes{$node}{__LOCATION}) = ($inserted_nodes->{$node}{__BUILD_NAME} =~ /^(.*)$1$/) ;
		}
		
	#this can also be reduced for a +/- 10% reduction
	if(exists $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE})
		{
		$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
		}
	else
		{
		$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTING_NODE} ;
		}
	
	$nodes{$node}{__INSERTED_AT}{INSERTION_RULE} = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_RULE} ;
	
	if(exists $inserted_nodes->{$node}{__DEPENDED_AT})
		{
		if($inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ne $inserted_nodes->{$node}{__DEPENDED_AT})
			{
			$nodes{$node}{__DEPENDED_AT} = $inserted_nodes->{$node}{__DEPENDED_AT} ;
			}
		}
		
	#reduce amount of data by indexing Insertion files (Pbsfile)
	my $insertion_file = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
	
	unless (exists $insertion_file_index{$insertion_file})
		{
		push @insertion_file_names, $insertion_file ;
		$insertion_file_index{$insertion_file} = $#insertion_file_names ;
		}
		
	$nodes{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_index{$insertion_file} ;
	
	if
		(
		   $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY}  ne $global_pbs_config->{BUILD_DIRECTORY}
		|| !Compare($inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}, $global_pbs_config->{SOURCE_DIRECTORIES})
		)
		{
		$nodes{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} = $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} ;
		$nodes{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES} = [@{$inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}}] ; 
		}
		
	if(exists $inserted_nodes->{$node}{__BUILD_DONE})
		{
		if(exists $inserted_nodes->{$node}{__VIRTUAL})
			{
			$nodes{$node}{__MD5} = 'VIRTUAL' ;
			}
		else
			{
			if(exists $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_TIME})
				{
				# this is a new node
				if(defined $inserted_nodes->{$node}{__MD5} && $inserted_nodes->{$node}{__MD5} ne 'not built yet')
					{
					$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
					}
				else
					{
					if(defined (my $current_md5 = GetFileMD5($inserted_nodes->{$node}{__BUILD_NAME})))
						{
						$nodes{$node}{__MD5} = $current_md5 ;
						}
					else
						{
						die ERROR("Can't open '$node' to compute MD5 digest: $!") ;
						}
					}
				}
			else
				{
				# use the old md5
				$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
				}
			}
		}
	else
		{
		$nodes{$node}{__MD5} = 'not built yet' ; 
		}
		
	unless (exists $nodes_index{$node})
		{
		push @node_names, $node ;
		$nodes_index{$node} = $#node_names;
		}
		
	for my $dependency (keys %{$inserted_nodes->{$node}})
		{
		next if $dependency =~ /^__/ ;
		
		push @{$nodes{$dependency}{__DEPENDENT}}, $nodes_index{$node} ;
		}
		
	unless (exists $nodes_index{$node})
		{
		push @node_names, $node ;
		$nodes_index{$node} = $#node_names;
		}
		
	if (exists $inserted_nodes->{$node}{__TRIGGER_INSERTED})
		{
		$nodes{$node}{__TRIGGER_INSERTED} = $inserted_nodes->{$node}{__TRIGGER_INSERTED} ;
		}
	}
	
return(\%nodes, \@node_names, \@insertion_file_names) ;
}

#--------------------------------------------------------------------------------------------------

sub GetWarpConfiguration
{
my $pbs_config = shift ;
my $warp_configuration = shift ;

my $pbs_prf = $pbs_config->{PBS_RESPONSE_FILE} ;

unless(defined $warp_configuration)
	{
	if(defined $pbs_prf)
		{
		my $pbs_prf_md5 = GetFileMD5($pbs_prf) ; 
		
		if(defined $pbs_prf_md5)
			{
			$warp_configuration->{$pbs_prf} = $pbs_prf_md5 ;
			}
		else
			{
			PrintError("Warp file generation aborted: Can't compute MD5 for prf file '$pbs_prf'!") ;
			close(DUMP) ;
			return ;
			}
		}
	else
		{
		$warp_configuration = {} ;
		}
		
	my $package_digest = PBS::Digest::GetPackageDigest('__PBS_WARP_DATA') ;
	for my $entry (keys %$package_digest)
		{
		$warp_configuration->{$entry} = $package_digest->{$entry} ;
		}
	}


# what a usefull comment! shall we remove or did I already do it?
#is the code bellow supposed to replace the code in Digest.pm?
# hate!

#NK, remove special handling in  digest.pm(seePBS_WARP_DATA)
#~ my $package_digests = PBS::Digest::GetAllPackageDigests() ;
#~ my $computed_warp_digest = {} ;

#~ for my $package (keys %$package_digests)
	#~ {
	#~ PrintDebug "Handling package: '$package'\n" ;
	
	#~ my $package_digest = $package_digests->{$package} ;
	
	#~ for my $digest_key (keys %$package_digest)
		#~ {
		
		#~ if($digest_key =~ "__PBS_LIB_PATH" || $digest_key =~ "^__PBSFILE")
			#~ {
			#~ PrintDebug "\t**** Found: '$digest_key'\n" ;
			#~ $computed_warp_digest->{$digest_key} = $package_digest->{$digest_key} ;
			
			#~ # we must find the fulll path for the lib and the pbs file
			#~ # the md5 is already computed
			#~ }
		#~ else
			#~ {
			#~ PrintDebug "\t key: '$digest_key'\n" ;
			#~ }
		#~ }
	#~ }

return($warp_configuration) ;
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp1_5  -

=head1 DESCRIPTION

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS::Information>.

=cut
