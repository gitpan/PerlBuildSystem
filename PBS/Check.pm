
package PBS::Check ;
use PBS::Debug ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;

use 5.006 ;
 
require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CheckDependencyTree RegisterUserCheckSub) ;
our $VERSION = '0.04' ;

use File::Basename ;

use PBS::Cyclic ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Digest ;

#-------------------------------------------------------------------------------

my %global_user_check_subs = ();

sub RegisterUserCheckSub
{
my $sub = shift ;
my $package = caller() ;

$global_user_check_subs{$package} = $sub ;
}

sub GetUserCheckSub
{
my $package = shift ;
return(undef) unless defined $package ;
return($global_user_check_subs{$package}) ;
}

#-----------------------------------------------------------------------------

sub CheckDependencyTree
{
# also checks the tree for cyclic dependencies
# generates a build sequence

my $tree                     = shift ;
my $inserted_nodes           = shift ; # this is to be considered read only
my $pbs_config               = shift ;
my $config                   = shift ; 
my $trigger_rule             = shift ;
my $node_checker_rule        = shift ;

my $build_sequence           = shift || [] ; # output
my $files_in_build_sequence  = shift || {} ; # output

my $build_directory          = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories       = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ; 

my $triggered = 0 ; 
	
if(exists $tree->{__CHECKED})
	{
	# linked nodes are checked once only
	if(exists $tree->{__TRIGGERED})
		{
		return(1) ;
		}
	else
		{
		return(0) ;
		}
	}
	
my $name = $tree->{__NAME} ;

#~ PrintDebug(DumpTree($tree, $name, MAX_DEPTH => 3)) ;

if(exists $tree->{__CYCLIC_FLAG})
	{
	$tree->{__CYCLIC_ROOT}++ ;
	
	my ($number_of_cycles, $cyclic_dump) = PBS::Cyclic::GetUserCyclicText($tree, $inserted_nodes, $pbs_config) ;
	
	my $plural = $number_of_cycles == 1? '' : 's' ;
	PrintError("Dependency cycle$plural detected!\n$cyclic_dump\n") ;
	
	warn DumpTree($tree, "Cyclic tree:") if (defined $pbs_config->{DEBUG_DISPLAY_CYCLIC_TREE}) ;
	die ;
	}
	
$tree->{__CYCLIC_FLAG}++ ; # used to detect when a cycle has started

my ($full_name, $is_alternative_source, $alternative_index) = LocateSource($name, $build_directory, $source_directories) ;

if ($is_alternative_source)
	{
	$tree->{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alternative_index] ;
	}
else
	{
	$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
	}

if(defined $tree->{__USER_ATTRIBUTE})
	{
	my $insertion_package ;
	
	if(defined $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA})
		{
		$insertion_package = $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_LOAD_PACKAGE} ;
		}
	else
		{
		$insertion_package = $tree->{__INSERTED_AT}{INSERTION_LOAD_PACKAGE} ;
		}
	
	my $user_attribute = $tree->{__USER_ATTRIBUTE} ;
	my $user_check     = GetUserCheckSub($insertion_package) ;
	
	if(defined $user_check)
		{
		# we allow the the user check to change the location of the file
		my ($user_full_name) = $user_check->($full_name, $user_attribute, $tree) ;
		
		my ($user_name, $user_path, $user_ext) = File::Basename::fileparse($user_full_name,('\..*')) ;
		my ($pbs_name, $pbs_path, $pbs_ext)    = File::Basename::fileparse($full_name,('\..*')) ;
		
		# but the name must stay the same
		if($user_name ne $pbs_name || $user_ext ne $pbs_ext)
			{
			die ERROR("PBS Doesn't allow to change '$name' name to '$user_full_name'!\n") ;
			}
			
		if($user_full_name ne $full_name)
			{
			# location was changed
			$full_name = $user_full_name ;
			
			if($user_path ne $build_directory)
				{
				$tree->{__ALTERNATE_SOURCE_DIRECTORY} = $user_path ;
				}
			}
		#else
			# keep the file PBS has found
		}
	else
		{
		my $definition_location = $tree->{__INSERTED_AT}{INSERTION_FILE} ;
		die ERROR("Node/File '$name', from '$definition_location', has a user attribute '$user_attribute' but no handler!\n") ;
		}
	}
	

$full_name = $tree->{__FIXED_BUILD_NAME} if(exists $tree->{__FIXED_BUILD_NAME}) ;
$tree->{__BUILD_NAME} = $full_name ;

if($pbs_config->{DISPLAY_FILE_LOCATION} && $name !~ /^__/)
	{
	my $located_message = '' ;
	$located_message = "located at '$full_name'" if $full_name ne $name ;
	
	if($is_alternative_source)
		{
		PrintInfo("$name [R]: $located_message\n") ;
		}
	else
		{
		PrintInfo("$name: $located_message\n")  if ($pbs_config->{DISPLAY_ALL_FILE_LOCATION}) ;
		}
	}
	
#----------------------------------------------------------------------------
# handle the node type
#----------------------------------------------------------------------------
if(exists $tree->{__VIRTUAL})
	{
	if(exists $tree->{__LOCAL})
		{
		die ERROR("Node/File '$name' can't be VIRTUAL and LOCAL") ;
		}
		
	if(-e $full_name)
		{
		if(-d $full_name && $pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY})
			{
			# do not generate warning
			}
		else
			{
			PrintWarning2("$name is VIRTUAL but file '$full_name' exists!\n") ;
			}
		}
	}
	
if(exists $tree->{__FORCED})
	{
	push @{$tree->{__TRIGGERED}}, {NAME => '__FORCED', REASON => 'Forced build'};
	
	PrintInfo("$name: trigged on [FORCED] type.\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
	$triggered++ ;
	}
	
#----------------------------------------------------------------------------

my $node_exist_on_disk = 1 ;
unless(-e $full_name)
	{
	unless(exists $tree->{__VIRTUAL})
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => "Doesn't exist"} ;
		PrintInfo("$name: trigged on itself [Doesn't exist]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		$node_exist_on_disk = 0 ;
		$triggered++ ;
		}
	}

if(defined $node_checker_rule)
	{
	my ($must_build, $why) = $node_checker_rule->($tree, $full_name) ;
	if($must_build)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => $why} ;
		PrintInfo("$name: trigged on itself [$why]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}

for my $dependency (keys %$tree)
	{
	if($dependency =~ /^__PBS_FORCE_TRIGGER(?::(.*))?/)
		{
		# the C depender and other depender can use this if they want to trigger a node rebuild
		
		my $reason = defined $1 ? "__$1" : '__PBS_FORCE_TRIGGER, no reason given' ;
		PrintInfo("$name: trigged because of $reason\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		
		push @{$tree->{__TRIGGERED}}, {NAME => $reason, REASON => $reason} ;
		$triggered++ ;
		}
		
	next if $dependency =~ /^__/ ; # eliminate private data
	
	my ($full_dependency, undef) = LocateSource
												(
												$dependency
												, $tree->{$dependency}{__PBS_CONFIG}{BUILD_DIRECTORY}
												, $tree->{$dependency}{__PBS_CONFIG}{SOURCE_DIRECTORIES}
		 										, $pbs_config->{DISPLAY_SEARCH_INFO} || 0
												, $pbs_config->{DISPLAY_SEARCH_ALTERNATES} || 0
												) ;
												
	if(-e $full_dependency)
		{
		unless(exists $tree->{__VIRTUAL})
			{
			# check via user defined sub
			if(defined $trigger_rule)
				{
				my ($must_build, $why) = $trigger_rule->($tree, $full_name, $dependency, $full_dependency) ;
				
				if($must_build)
					{
					push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => $why} ;
					PrintInfo("$name: trigged on '$dependency' [$why]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
					$triggered++ ;
					}
				else
					{
					if($pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES})
						{
						push @{$tree->{__NOT_TRIGGERED}}, [$dependency, 'user defined check was OK'] ;
						PrintInfo("$name: NOT trigged on '$dependency'\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
						}
					}
				}
			}
		#else
			# node already triggered by type virtual
		}
	else
		{
		unless(exists $tree->{$dependency}{__VIRTUAL})
			{
			push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => "Doesn't exist"} ;
			PrintInfo("$name: trigged on '$dependency' (doesn't exist)\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
			$triggered++ ;
			
			my $digest_file_name = $full_dependency . 'pbs_md5' ;
			if(-e $digest_file_name)
					{
					PrintWarning("Removing digest '$digest_file_name': node '$dependency->{__NAME}' doesn't exist.") ;
					unlink($digest_file_name) ;
					}
			}
		}
		
	if(exists $tree->{$dependency}{__CHECKED})
		{
		if($tree->{$dependency}{__TRIGGERED})
			{
			$triggered = 1 ; # current node also need to be build
			push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => 'Subdependency or self'} ;
			
			# data used to parallelize build
			$tree->{__CHILDREN_TO_BUILD}++ ;
			
			push @{$tree->{$dependency}{__PARENTS}}, $tree ;
			}
		}
	else
		{
		my ($subdependency_triggered) = CheckDependencyTree
														(
														  $tree->{$dependency}
														, $inserted_nodes
														, $pbs_config
														, $config
														, $trigger_rule
														, $node_checker_rule
														, $build_sequence
														, $files_in_build_sequence
														, $build_directory
														, $source_directories
														) ;
		
		if($subdependency_triggered)
			{
			push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => 'Subdependency or self'};
			$triggered++ ;
			
			# data used to parallelize build
			$tree->{__CHILDREN_TO_BUILD}++ ;
			push @{$tree->{$dependency}{__PARENTS}}, $tree ;
			}
		}
	}

unless($pbs_config->{NO_DIGEST} || exists $tree->{__VIRTUAL})
	{
	# check digest
	my ($must_build_because_of_digest, $reason) = (0, '') ;
	($must_build_because_of_digest, $reason) = PBS::Digest::IsNodeDigestDifferent($tree) unless $triggered ;
	
	if($must_build_because_of_digest)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__DIGEST_TRIGGERED', REASON => $reason} ;
		PrintInfo("$name: trigged on '__DIGEST_TRIGGERED'[$reason]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}

# node is checked, add it to the build sequence if triggered
if($triggered)
	{
	delete $tree->{__BUILD_DONE} ;
	
	my $full_name ;
	if(exists $tree->{__FIXED_BUILD_NAME})
		{
		$full_name = $tree->{__FIXED_BUILD_NAME}  ;
		}
	else
		{
		($full_name) = LocateSource($name, $build_directory) ;
		}
	
	if($tree->{__BUILD_NAME} ne $full_name)
		{
		if(defined $pbs_config->{DISPLAY_ALL_FILE_LOCATION})
			{
			PrintWarning("Relocating '$name' @ '$full_name'\n")  ;
			PrintWarning(DumpTree($tree->{__TRIGGERED}, 'Cause:')) ;
			}
			
		$tree->{__BUILD_NAME} = $full_name ;
		$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
		delete $tree->{__ALTERNATE_SOURCE_DIRECTORY} ;
		}
		
	$files_in_build_sequence->{$name} = $tree ;
	push @$build_sequence, $tree  ;
	}
else
	{
	if(exists $tree->{__LOCAL})
		{
		# never get here if the node doesn't exists as it would have triggered
		
		my ($build_directory_name) = LocateSource($name, $build_directory) ;
		my ($repository_name) = LocateSource($name, $build_directory, $source_directories) ;
		
		my $repository_digest_name = $repository_name . '.pbs_md5' ;
		my $build_directory_digest_name = $build_directory_name . '.pbs_md5' ;
		
		unless($repository_name eq $build_directory_name)
			{
			PrintWarning("Forcing local copy of '$repository_name' to '$build_directory_name'.\n") if defined $pbs_config->{DISPLAY_ALL_FILE_LOCATION} ;
			
			# build a  localizer rule on the fly for this node
			my $localizer =
				[
					{
					  TYPE => ['__LOCAL']
					, NAME => '__LOCAL:Internal rule' # name, package, ...
					, FILE => 'Internal'
					, LINE => 0
					, ORIGIN => ''
					, DEPENDER => undef
					, BUILDER  => sub 
							{
							use File::Copy ;
							
							my ($basename, $path, $ext) = File::Basename::fileparse($build_directory_name, ('\..*')) ;
							
							# create path to the node so external commands succeed
							unless(-e $path)
								{
								use File::Path ;
								mkpath($path) ;
								}
								
							my $result ;
							eval 
								{
								$result = copy($repository_name, $build_directory_name) ;
								
								return($result) unless $result ;
								
								# NO_DIGEST switch is to be eliminated
								#~ unless($_[6]->{__PBS_CONFIG}{NO_DIGEST})
									#~ {
									#~ $result = copy($repository_digest_name, $build_directory_digest_name) ;
									#~ }
									
								return($result) ;
								} ;
							
							if($@)
								{
								return(0 , "Copy '$repository_name' -> '$build_directory_name' failed! $@\n") ;
								}
								
							if($result)
								{
								return(1, "Copy '$repository_name' -> '$build_directory_name' succes.\n") ;
								}
							else
								{
								return(0 , "Copy '$repository_name' -> '$build_directory_name' failed! $!\n") ;
								}
							}
					, TEXTUAL_DESCRIPTION => 'Rule to localize a file from the repository.'
					}
				] ;
				
			# localizer will be called as it is the last rule
			push @{$tree->{__MATCHING_RULES}}, 
				{
				  RULE => 
					{
					  INDEX             => -1
					, DEFINITIONS       => $localizer
					}
				, DEPENDENCIES => []
				};
			
			push @{$tree->{__TRIGGERED}}, {NAME => '__LOCAL', REASON => 'Local file'};
			
			$files_in_build_sequence->{$name} = $tree ;
			push @$build_sequence, $tree  ; # build once only
			}
		}
	else
		{
		$tree->{__BUILD_DONE} = "node was up to date" ;
		}
	}
	
delete($tree->{__CYCLIC_FLAG}) ;
$tree->{__CHECKED}++ ;

return($triggered) ;
}

#-------------------------------------------------------------------------------

sub LocateSource
{
# returns the directory where the file is located
# if the file doesn't exist in any of the build directory or other directories
# the file is then locate in the build directory

my $file                     = shift ;
my $build_directory          = shift ;
my $other_source_directories = shift ;
my $display_search_info      = shift ;
my $display_all_alternates   = shift ;

my $located_file = $file ; # for files starting at root
my $alternative_source = 0 ;
my $other_source_index = -1 ;

unless(File::Spec->file_name_is_absolute($file))
	{
	my $unlocated_file = $file ;
	
	$file =~ s/^\.\/// ;

	$located_file = "$build_directory/$file" ;
	$located_file =~ s!//!/! ;
	
	my $file_found = 0 ;
	PrintInfo("Locating '$unlocated_file' \@:\n") if $display_search_info ;
	
	if(-e $located_file)
		{
		$file_found++ ;
		
		my ($file_size, undef, undef, $modification_time) = (stat($located_file))[7..10];
		my ($sec,$min,$hour,$month_day,$month,$year,$week_day,$year_day) = gmtime($modification_time) ;
		$year += 1900 ;
		$month++ ;
		
		PrintInfo("   located in build directory '$build_directory'. s: $file_size t: $month_day-$month-$year $hour:$min:$sec\n") if $display_search_info ;
		}
	else
		{
		if($display_search_info)
			{
			PrintInfo("   in build directory '$build_directory': ") ;
			PrintError("not found.\n", 0) if $display_search_info ;
			}
		}
		
	if((! $file_found) || $display_all_alternates)
		{
		for my $source_directory (@$other_source_directories)
			{
			$other_source_index++ unless $alternative_source ;
			
			if('' eq ref $source_directory)
				{
				my $searched_file = "$source_directory/$file" ;
				PrintInfo("   '$searched_file': ") if $display_search_info ;
				
				if(-e $searched_file)
					{
					my ($file_size, undef, undef, $modification_time) = (stat($searched_file))[7..10];
					my ($sec, $min, $hour, $month_day, $month, $year, $week_day, $year_day) = gmtime($modification_time) ;
					$year += 1900 ;
					$month++ ;
					
					if($file_found)
						{
						PrintWarning("NOT USED. size: $file_size time: $month_day-$month-$year $hour:$min:$sec\n", 0) if $display_search_info ;
						}
					else
						{
						$file_found++ ;
						PrintInfo("Relocated. size: $file_size time: $month_day-$month-$year $hour:$min:$sec\n", 0) if $display_search_info ;
						$located_file = $searched_file ;
						$alternative_source++ ;
						last unless $display_all_alternates ;
						}
					}
				else
					{
					PrintError("not found.\n", 0) if $display_search_info ;
					}
				}
			else
				{
				die "unimplemented!" ;
				}
			}
		}
	}
	
return($located_file, $alternative_source, $other_source_index) ;
}

#-------------------------------------------------------------------------------

sub CheckTimeStamp
{
my $dependent_tree  = shift ;
my $dependent       = shift ;
my $dependency_tree = shift ;
my $dependency      = shift ;

if(-e $dependent)
	{
	if((stat($dependency))[9] > (stat($dependent))[9])
		{
		return(1, "$dependency newer than $dependent") ;
		}
	else
		{
		return(0, "Time stamp OK") ;
		}
	}
else
	{
	if(-e $dependency)
		{
		return(0, "'$dependent' doesn't exist") ;
		}
	else
		{
		die ERROR "Can't Check time stamp on non existing nodes!" ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Check  -

=head1 SYNOPSIS

	use PBS::Check ;
	my $triggered = CheckDependencyTree
							(
							  $tree
							, $inserted_nodes
							, $pbs_config
							, $config
							, $trigger_rule
							, $node_checker_rule
							, $build_sequence # output
							, $files_in_build_sequence # output
							) ;

=head1 DESCRIPTION

	sub RegisterUserCheckSub: exported function available in Pbsfiles
	sub GetUserCheckSub
	sub CheckDependencyTree: checks a tree and generates a build sequence
	sub LocateSource: find a file in the build directory or source directories
	sub CheckTimeStamp: check 2 nodes time stamps with each other

=head2 EXPORT

	CheckDependencyTree
	RegisterUserCheckSub

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO


=cut
