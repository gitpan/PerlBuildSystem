
$PBS::Dependency::BuildDependencyTree_calls = 0 ;

package PBS::Depend ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Time::HiRes ;
use Tie::Hash::Indexed ;
use File::Basename ;

require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CreateDependencyTree) ;
our $VERSION = '0.06' ;

use PBS::PBS ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Triggers ;
use PBS::PostBuild ;
use PBS::Plugin;

#-------------------------------------------------------------------------------
# July 2005, try to figure out how to implement micro warps
our %used_pbsfiles ;
our %used_pbsfiles_located ;

sub CreateDependencyTree
{
my $Pbsfile          = shift ;
my $package_alias    = shift ;
my $load_package     = PBS::PBS::CanonizePackageName(shift) ;
my $pbs_config       = shift ;
my $tree             = shift ;
my $config           = shift ; 
my $inserted_nodes   = shift ;
my $dependency_rules = shift ;

$PBS::Depend::BuildDependencyTree_calls++ ;

return if(exists $tree->{__DEPENDED}) ;

my $node_name = $tree->{__NAME} ;

my $node_name_matches_ddr = 0 ;
for my $regex (@{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}})
	{
	if($node_name =~ /$regex/)
		{
		$node_name_matches_ddr = 1 ;
		last ;
		}
	}
	
$tree->{__DEPENDED}++ ; # depend sub tree once only flag
$tree->{__DEPENDED_AT} = $Pbsfile ;

my %dependency_rules ; # keep a list of  which rules generated which dependencies
my $has_dependencies = 0 ;
my @sub_pbs ; # list of subpbs matching this node

tie my %triggered_nodes, 'Tie::Hash::Indexed';

my @post_build_rules = PBS::PostBuild::GetPostBuildRules($load_package) ;

if
	(
	   defined $tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX}
	|| defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}
	)
	{
	PrintInfo("Depending '$node_name'\n")  ;
	}

# check if the current node has matching post build rules
for my $post_build_rule (@post_build_rules)
	{
	my ($match, $message) = $post_build_rule->{DEPENDER}($node_name) ;
	
	if($match)
		{
		push @{$tree->{__POST_BUILD_COMMANDS}}, $post_build_rule ;
		
		if($pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS})
			{
			my $post_build_command_info =  $post_build_rule->{NAME}
								. $post_build_rule->{ORIGIN} ;
								
			PrintInfo("$node_name has matching post build command, '$post_build_command_info'\n") ;
			}
		}
	}

# find the dependencies by applying the rules
for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
	{
	my $rule_name = $dependency_rules->[$rule_index]{NAME} ;
	my $rule_info = "'$rule_name' @ '$dependency_rules->[$rule_index]{FILE}:$dependency_rules->[$rule_index]{LINE}'" ;
	
	my $depender  = $dependency_rules->[$rule_index]{DEPENDER} ;
   
	#DEBUG	
	my %debug_data ;
	if($PBS::Debug::debug_enabled)
		{
		%debug_data = 
			(
			  TYPE           => 'DEPEND'
			, RULE_NAME      => $rule_name
			, NODE_NAME      => $node_name
			, PACKAGE_NAME   => $package_alias
			, PBSFILE        => $Pbsfile
			, TREE           => $tree
			, INSERTED_FILES => $inserted_nodes
			, CONFIG         => $config
			) ;
			
		$DB::single = 1 if(PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
		}
		
	my ($dependency_result, $builder_override) = $depender->($node_name, $config, $tree, $inserted_nodes, $dependency_rules->[$rule_index]) ;
	
	my ($triggered, @dependencies ) = @$dependency_result ;
	
	#DEBUG	
	$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1, TRIGGERED => $triggered, DEPENDENCIES => \@dependencies)) ;
	
	if($triggered)
		{
		my $subs_list = $dependency_rules->[$rule_index]{NODE_SUBS} ;
		
		if(defined $subs_list)
			{
			my $subs = [] ;
			
			if('CODE' eq ref $subs_list)
				{
				push @$subs, $subs_list ;
				}
			elsif('ARRAY' eq ref $subs_list)
				{
				for(@$subs_list)
					{
					if('CODE' eq ref $_)
						{
						push @$subs, $_ ;
						}
					else
						{
						die ERROR "Node sub is not a sub in array at rule $rule_info\n" ;
						}
					}
				}
			else
				{
				die ERROR "Node sub is not a sub @ $rule_info\n" ;
				}
				
			for my $sub (@$subs)
				{
				$sub->($node_name, $config, $tree, $inserted_nodes) ;
				}
			}
			
		#~ my $depender_message = $dependencies[0] || 'no depender message' ;
		#~ PrintInfo("\t'$rule_info'  matched: $depender_message\n") if(defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;
		
		#----------------------------------------------------------------------------
		# is it a sub pbs definition?
		#----------------------------------------------------------------------------
		if(@dependencies && 'HASH' eq ref $dependencies[0])
			{
			$dependencies[0]{__RULE_NAME} = $dependency_rules->[$rule_index]{NAME} ;
			push @sub_pbs, 
				{
				  SUBPBS => $dependencies[0]
				, RULE   => $dependency_rules->[$rule_index]
				} ;
			
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddr)
				{
				PrintInfo("$node_name has matching sub pbs, rule $rule_index:$rule_info\n") ;
				}
				
			next ;
			}
			
		#~ warn DumpTree(\@dependencies, "dependencies:") ;
		
		# transform the node name into an internal structure and check for node attributes
		@dependencies = map
				{
				my ($dependency_name, $dependency_attribute) ;
				
				
				if(/(.*)::(.*)$/)
					{
					# handle node user attribute
					
					# return a hash
						{
						  NAME => $1
						, RULE_INDEX => $rule_index
						, USER_ATTRIBUTE => $2
						}

					}
				else
					{
					# return a hash
						{
						  NAME => $_
						, RULE_INDEX => $rule_index
						}
					}
				} @dependencies ;
				
		#~ warn DumpTree(\@dependencies, "dependencies:\") ;
		
		#-------------------------------------------------------------------------
		# handle VIRTUAL, LOCAL OR FORCED rule type
		#-------------------------------------------------------------------------
		my %types = map { $_, 1 } (VIRTUAL, LOCAL, FORCED, IMMEDIATE_BUILD) ;
		
		for my $rule_type (@{$dependency_rules->[$rule_index]{TYPE}})
			{
			$tree->{$rule_type} = 1 if(exists $types{$rule_type}) ;
			}
			
		#----------------------------------------------------------------------------
		# display the dependencies inserted by current rule
		#----------------------------------------------------------------------------
		if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddr)
			{
			$node_name_matches_ddr = 0 if ($node_name =~ /^__/) ;
			
			if($node_name_matches_ddr)
				{
				my $node_type = '' ;
				for my $type (VIRTUAL, LOCAL, FORCED)
					{
					$node_type .= " $type " if exists $tree->{$type} ;
					}
				$node_type = '[' . $node_type . '] ' if $node_type ne '' ;
				
				my $rule_info =  $dependency_rules->[$rule_index]{NAME}
									. $dependency_rules->[$rule_index]{ORIGIN} ;
									
				my $rule_type = '' ;
				$rule_type .= '[B]'  if(defined $dependency_rules->[$rule_index]{BUILDER}) ;
				$rule_type .= '[BO]' if($builder_override) ;
				$rule_type .= '[S]'  if(defined $dependency_rules->[$rule_index]{NODE_SUBS}) ;
				
				my @dependency_names = map {$_->{NAME} ;} @dependencies ;
				
				my $dependency_info = "$node_name ${node_type}has dependencies [@dependency_names], rule $rule_index:$rule_info:$rule_type" ;
				if(defined $tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
					{
					# the dependers will be indented, indent the result under them.
					PrintInfo("      $dependency_info.\n") ;
					}
				else
					{
					PrintInfo("   $dependency_info.\n") ;
					}
					
				PrintWithContext
					(
					  $dependency_rules->[$rule_index]{FILE}
					, 1, 2 #context  size
					, $dependency_rules->[$rule_index]{LINE}
					, \&INFO
					) if defined $pbs_config->{DISPLAY_DEPENDENCY_RULE_DEFINITION} ;
				}
			}
			
		#----------------------------------------------------------------------------
		# Check the dependencies
		#----------------------------------------------------------------------------
		for my $dependency (@dependencies)
			{
			my $dependency_name = $dependency->{NAME} ;
			
			if($dependency_name =~ /^__PBS_FORCE_TRIGGER/)
				{
				$tree->{$dependency_name} = $dependency ;
				}
			
			next if $dependency_name =~ /^__/ ;
			
			RunPluginSubs('CheckNodeName', $dependency_name, $dependency_rules->[$rule_index]) ;
			
			if($node_name eq $dependency_name)
				{
				my $rule      = $dependency_rules->[$rule_index] ;
				my $rule_info =  $rule->{NAME} . $rule->{ORIGIN} ;
									
				my $dependency_names = join ' ', map{$_->{NAME}} @dependencies ;
				PrintError( "Self referencial rule #$rule_index '$rule_info' for $node_name: $dependency_names.\n") ;
				
				PbsDisplayErrorWithContext($rule->{FILE}, $rule->{LINE}) ;
				die ;
				}
			
			if(exists $tree->{$dependency_name})
				{
				unless($dependency_name =~ /^__/)
					{
					unless (defined $pbs_config->{NO_DUPLICATE_INFO})
						{
						my $rule_info =  $dependency_rules->[$rule_index]{NAME}
											. $dependency_rules->[$rule_index]{ORIGIN} ;
											
						my $inserting_rule_index = $tree->{$dependency_name}{RULE_INDEX} ;
						my $inserting_rule_info  =  $dependency_rules->[$inserting_rule_index]{NAME}
											             . $dependency_rules->[$inserting_rule_index]{ORIGIN} ;
											
						PrintWarning
							(
							  "In Pbsfile : $Pbsfile, while at rule '$rule_info', node '$node_name':\n"
							. "    $dependency_name already inserted by rule "
							. "'$inserting_rule_index:$inserting_rule_info'"
							. ", Ignoring duplicate dependency.\n"
							) ;
						}
					}
				}
			else
				{
				# temporarely hold the names of the dependencies within the node
				# this is used for checking duplicate dependencies
				$tree->{$dependency_name} = $dependency ;
				}
			}
			
		# keep a log of matching rules
		push @{$tree->{__MATCHING_RULES}}, 
			{
			  RULE => 
				{
				  INDEX             => $rule_index
				, DEFINITIONS       => $dependency_rules
				, BUILDER_OVERRIDE  => $builder_override
				}
			, DEPENDENCIES => \@dependencies
			};
		}
	else
		{
		# not triggered
		my $depender_message = $dependencies[0] || 'no depender message' ;
		PrintInfo("\t'$rule_info'  didn't match '$node_name': $depender_message\n") if(defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;
		}
	}
	
#-------------------------------------------------------------------------
# continue with single definition of dependencies 
# and remove temporary dependency names
#-------------------------------------------------------------------------
my @dependencies ;
for my $dependency_name (keys %$tree)
	{
	push @dependencies, $tree->{$dependency_name} unless($dependency_name =~ /^__/) ;
	}
	
for (keys %$tree)
	{
	delete $tree->{$_} if $_ !~ /^__/ ;
	}
	
#-------------------------------------------------------------------------
# handle IGNORE_LOCAL_RULES, ...
#-------------------------------------------------------------------------
if(@sub_pbs)
	{
	if(@sub_pbs == 1)
		{
		if(@dependencies && exists $sub_pbs[0]{SUBPBS}{IGNORE_LOCAL_RULES} && $sub_pbs[0]{SUBPBS}{IGNORE_LOCAL_RULES} > 0)
			{
			PrintWarning
				(
				DumpTree
					(
					  \@sub_pbs
					, "Sub Pbs rule:"
					)
				) ;
				
			PrintWarning("Forces removal of locally defined dependencies:\n") ;
				
			for my $dependency (@dependencies)
				{
				PrintWarning("    $dependency->{NAME}\n") ;
				}
			
			# force sub pbs by eliminating the dependencies
			$tree->{__MATCHING_RULES} = [] ;
			
			for my $dependency (keys %$tree)
				{
				next if $dependency =~ /^__/ ;
				delete $tree->{$dependency} ;
				
				unless(exists $inserted_nodes->{$dependency}{__LINKED})
					{
					delete $inserted_nodes->{$dependency}  ;
					}
				}
				
			@dependencies = () ;
			%triggered_nodes  = () ;
			}
		}
	else
		{
		PrintError "In Pbsfile : $Pbsfile, $node_name has multiple sub pbs defined:\n" ;
		PrintError(DumpTree(\@sub_pbs, "Sub Pbs:")) ;
		
		Carp::croak  ;
		}
	}
	

#-------------------------------------------------------------------------
# handle node triggers
#-------------------------------------------------------------------------
for my $dependency (@dependencies)
	{
	use constant TRIGGERED_NODE_NAME  => 0 ;
	use constant TRIGGERING_NODE_NAME => 1 ;
	use constant TRIGGER_INFO         => 2 ;
	
	use Carp ;
	unless('HASH' eq ref $dependency)
		{
		print $dependency ;
		confess  ;
		}
	
	my $dependency_name = $dependency->{NAME} ;
	
	for my $trigger_rule (PBS::Triggers::GetTriggerRules($load_package))
		{
		my ($match, $triggered_node_name) = $trigger_rule->{DEPENDER}($dependency_name) ;
		my $trigger_info =  $trigger_rule->{NAME}
								. $trigger_rule->{ORIGIN} ;
								
		if($match)
			{
			my $current_trigger_message = '' ;
			
			next if($triggered_node_name eq $node_name) ;
			
			if(exists $inserted_nodes->{$triggered_node_name})
				{
				$current_trigger_message = "'$triggered_node_name' would have been inserted by trigger: '$trigger_info' "
								. "on node '$dependency_name', but was found among the nodes.\n" ;
				}
			else
				{
				$current_trigger_message = "'$triggered_node_name' was inserted by trigger: '$trigger_info' "
														. " on node '$dependency_name'.\n" ;
														
				if(exists $triggered_nodes{$triggered_node_name})
					{
					$current_trigger_message .= "'$triggered_node_name' was already trigger inserted by trigger "
									. "'$triggered_nodes{$triggered_node_name}[TRIGGER_INFO]' on "
									. "node '$triggered_nodes{$triggered_node_name}[TRIGGERING_NODE_NAME]'."
									. "Ignoring duplicate triggered node.\n" ;
					}
				else
					{
					$triggered_nodes{$triggered_node_name} = [$triggered_node_name, $dependency_name, $trigger_info] ;
					}
				}
				
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} || $pbs_config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES})
				{
				PrintInfo($current_trigger_message)  ;
				}
			}
		}
	}
	
#-------------------------------------------------------------------------
# insert triggered nodes
#-------------------------------------------------------------------------
for my $triggered_node_data (values %triggered_nodes)
	{
	my $triggered_node_name  = $triggered_node_data->[TRIGGERED_NODE_NAME] ;
	my $triggering_node_name = $triggered_node_data->[TRIGGERING_NODE_NAME] ;
	my $rule_info            = $triggered_node_data->[TRIGGER_INFO] ,
	
	my $time = Time::HiRes::time() ;
	
	tie my %triggered_node_tree, "Tie::Hash::Indexed" ;
	
	%triggered_node_tree = 
		(
		  __NAME             => $triggered_node_name
		, __DEPENDENCY_TO    => {PBS => 'Perl Build System'}
		, __INSERTED_AT      => {
					  INSERTION_FILE         => $Pbsfile
					, INSERTION_PACKAGE      => $package_alias
					, INSERTION_LOAD_PACKAGE => $load_package
					, INSERTION_RULE         => $rule_info
					, INSERTION_TIME         => $time
					, INSERTING_NODE         => $triggering_node_name
					} 
		, __CONFIG           => $config
		, __PACKAGE          => $package_alias
		, __LOAD_PACKAGE     => $load_package
		, __PBS_CONFIG       => $pbs_config
		, __TRIGGER_INSERTED => $triggering_node_name
		, __MATCHING_RULES   => []
		#~, __USER_ATTRIBUTE   => $dependency->[DEPENDENCY_USER_ATTRIBUTE]
		) ;
		
	$inserted_nodes->{$triggered_node_name} = \%triggered_node_tree ;
	
	CreateDependencyTree
		(
		  $Pbsfile
		, $package_alias 
		, $load_package
		, $pbs_config             
		, \%triggered_node_tree                       
		, $config                     
		, $inserted_nodes             
		, $dependency_rules           
		) ;
	}
# handle node triggers finished

for my $dependency (@dependencies)
	{
	my $dependency_name = $dependency->{NAME} ;
	my $rule_index      = $dependency->{RULE_INDEX} ;
	
	$has_dependencies++ ;
	
	# remember which rule inserted which dependency
	push @{$dependency_rules{$dependency_name}}, [$rule_index, $dependency_rules->[$rule_index]{NAME}] ;
	
	if(exists $inserted_nodes->{$dependency_name})
		{
		# the dependency already exists within the tree (inserted through another node)
		# do some sanity checking
		#~ PrintDebug DumpTree($inserted_nodes->{$dependency_name}, '' , MAX_DEPTH => 3) ;
		
		if($inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_FILE} ne $Pbsfile)
			{
			if(defined $pbs_config->{DEBUG_NO_EXTERNAL_LINK})
				{
				PrintError("--no_external_link switch specified, stop.\n") ;
				die ;
				}
				
			unless($pbs_config->{NO_LOCAL_MATCHING_RULES_INFO})
				{
				my @local_rules_matching ;
				
				for(my $matching_rule_index = 0 ; $matching_rule_index < @$dependency_rules ; $matching_rule_index++)
					{
					my ($dependency_result) = $dependency_rules->[$matching_rule_index]{DEPENDER}->($dependency_name, $config, $inserted_nodes->{$dependency_name}, $inserted_nodes) ;
					push @local_rules_matching, $matching_rule_index if($dependency_result->[0]) ;
					}
				
				if(exists $inserted_nodes->{$dependency_name}{__DEPENDED} && @local_rules_matching)
					{
					my $rule_info =  $dependency_rules->[$rule_index]{NAME}
										. $dependency_rules->[$rule_index]{ORIGIN} ;
										
					PrintWarning
						(
						  "While checking '$node_name' at rule '$rule_info' :\n"
						. "   Existing node '$dependency_name' from:"
						. "$inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_FILE}"
						. "->$inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_RULE}"
						. " is already depended but has local rules matching in '$Pbsfile':\n"
						) ;
					
					for my $matching_rule_index (@local_rules_matching)
						{
						$rule_info =  $dependency_rules->[$matching_rule_index]{NAME}
											. $dependency_rules->[$matching_rule_index]{ORIGIN} ;
											
						PrintWarning("      $matching_rule_index:$rule_info\n") ;
						}
						
					}
				}
			}
			
		if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && (! $pbs_config->{NO_LINK_INFO}))
			{
			my $rule_info =  $dependency_rules->[$rule_index]{NAME}
								. $dependency_rules->[$rule_index]{ORIGIN} ;
								
			PrintWarning
				(
				"In Pbsfile : $Pbsfile, while at rule $rule_info, node '$node_name'\n"
				. "    '$dependency_name' already inserted @ $inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_FILE}:"
				. "$inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_RULE}, Linking.\n"
				) ;
				
			PrintWarning("    Above node is not depended yet!\n") unless (exists $inserted_nodes->{$dependency_name}{__DEPENDED}) ;
			
			#~ warn DumpTree($inserted_nodes->{$dependency_name}, "node '$dependency_name' linked but not depended:") ;
			}
		
		$tree->{$dependency_name} = $inserted_nodes->{$dependency_name} ;
		$tree->{$dependency_name}{__LINKED}++ ;
		}
	else
		{
		# a new node is born
		my $rule_info =  $dependency_rules->[$rule_index]{NAME}
							. $dependency_rules->[$rule_index]{ORIGIN} ;
							
		my $time = Time::HiRes::time() ;
		
		#DEBUG
		my %debug_data ;
		if($PBS::Debug::debug_enabled)
			{
			%debug_data = 
				(
				  TYPE           => 'INSERT'
				, PARENT_NAME    => $node_name
				, NODE_NAME      => $dependency_name
				, PACKAGE_NAME   => $package_alias
				, PBSFILE        => $Pbsfile
				, TREE           => $tree
				, INSERTED_FILES => $inserted_nodes
				, CONFIG         => $config
				) ;
			
			#DEBUG	
			$DB::single = 1 if(PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
			}
		
		tie my %dependency_tree_hash, "Tie::Hash::Indexed" ;
		
		$tree->{$dependency_name}                     = \%dependency_tree_hash ;
		$tree->{$dependency_name}{__MATCHING_RULES}   = [] ;
		$tree->{$dependency_name}{__CONFIG}           = $config ;
		$tree->{$dependency_name}{__NAME}             = $dependency_name ;
		$tree->{$dependency_name}{__USER_ATTRIBUTE}   = $dependency->{USER_ATTRIBUTE} if exists $dependency->{USER_ATTRIBUTE} ;
		
		$tree->{$dependency_name}{__PACKAGE}          = $package_alias ;
		$tree->{$dependency_name}{__LOAD_PACKAGE}     = $load_package ;
		$tree->{$dependency_name}{__PBS_CONFIG}       = $pbs_config ;
		
		$tree->{$dependency_name}{__INSERTED_AT}      = {
								  INSERTION_FILE         => $Pbsfile
								, INSERTION_PACKAGE      => $package_alias
								, INSERTION_LOAD_PACKAGE => $load_package
								, INSERTION_RULE         => $rule_info
								, INSERTION_TIME         => $time
								, INSERTING_NODE         => $tree->{__NAME}
								} ;
								
		$inserted_nodes->{$dependency_name} = $tree->{$dependency_name} ;
			
		#DEBUG
		$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1)) ;
		}
	}
	
if(0 == $has_dependencies)
	{
	if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddr)
		{
		if($node_name !~/^__/)
			{
			PrintInfo
				(
				"$node_name has no locally defined dependencies "
				. "(rules from package '$package_alias' loaded from '"
				. $pbs_config->{PBSFILE}
				. "').\n"
				) ;
			}
		}
	
	if(@sub_pbs)
		{
		if(@sub_pbs != 1)
			{
			PrintError "In Pbsfile : $Pbsfile, $node_name has multiple sub pbs defined:\n" ;
			PrintError(DumpTree(\@sub_pbs,, "Sub Pbs:")) ;
			
			Carp::croak  ;
			}
			
		# the node had no dependencie but a single subpbs matched
		
		my $sub_pbs_hash    = $sub_pbs[0]{SUBPBS} ;
		my $sub_pbs_name    = $sub_pbs_hash->{PBSFILE} ;
		my $sub_pbs_package = $sub_pbs_hash->{PACKAGE} ;
		
		my $alias_message = '' ;
		$alias_message = "aliased as '$sub_pbs_hash->{ALIAS}'" if(defined $sub_pbs_hash->{ALIAS}) ;
		
		$sub_pbs_name = LocatePbsfile($pbs_config, $Pbsfile, $sub_pbs_name, $sub_pbs[0]{RULE}) ;
		
		unless(defined $pbs_config->{NO_SUBPBS_INFO})
			{
			if(defined $pbs_config->{SUBPBS_FILE_INFO})
				{
				PrintWarning("[$PBS::PBS::pbs_runs/$PBS::PBS::Pbs_call_depth] Depending '$node_name' $alias_message with sub pbs '$sub_pbs_package:$sub_pbs_name'.\n") ;
				}
			else
				{
				PrintWarning("Depending '$node_name' $alias_message.\n") ;
				}
			}
			
		#-------------------------------------------------------------
		# run subpbs
		#-------------------------------------------------------------
		
		delete $inserted_nodes->{$node_name} ; # temporarely eliminate ourself from the existing nodes list
		
		my $tree_name = "sub_pbs$sub_pbs_name" ;
		$tree_name =~ s/.\//_/g ;
		
		PrintInfo(DumpTree($sub_pbs_hash, "sub pbs:")) if defined $pbs_config->{DISPLAY_SUB_PBS_DEFINITION} ;
			
		# Synchonize with elements from the sub pbs definition, specially build and source dirs 
		# we overide elements
		my $sub_pbs_config = {%{$tree->{__PBS_CONFIG}}, %$sub_pbs_hash} ;
		$sub_pbs_config->{PARENT_PACKAGE} = $package_alias ;
		$sub_pbs_config->{PBS_COMMAND} ||= DEPEND_ONLY ;
		
		my $sub_node_name = $node_name ;
		$sub_node_name    = $sub_pbs_hash->{ALIAS} if(defined $sub_pbs_hash->{ALIAS}) ;
		
		my $package_config = PBS::Config::GetPackageConfig($load_package) ;
		my %sub_config = PBS::Config::ExtractConfig
								(
								$package_config
								, $tree->{__PBS_CONFIG}{CONFIG_NAMESPACES}
								, ['CURRENT', 'PARENT', 'COMMAND_LINE', 'PBS_FORCED'] # LOCAL REMOVED!
								) ;
								
		#~ PrintError(DumpTree($sub_pbs_config, "subpbs config for package $sub_pbs_name :")) ;
		
		my $already_inserted_nodes = $inserted_nodes ;
		$already_inserted_nodes    = {} if(defined $sub_pbs_hash->{LOCAL_NODES}) ;
		
		my ($build_result, $build_message, $sub_tree, $inserted_nodes, $sub_pbs_load_package)
			= PBS::PBS::Pbs
				(
				  $sub_pbs_name
				, $load_package
				, $sub_pbs_config
				, \%sub_config
				, [$sub_node_name]
				, $already_inserted_nodes
				, $tree_name
				, $sub_pbs_config->{PBS_COMMAND}
				) ;
						
		#attempt to micro warp, July 2005 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		#unlocated
		unless(exists $used_pbsfiles{$sub_pbs_name})
			{
			$used_pbsfiles{$sub_pbs_name} = {} ;
			}
			
		$used_pbsfiles{$Pbsfile}{$sub_pbs_name} = $used_pbsfiles{$sub_pbs_name} ;
		
		#locate
		unless(exists $used_pbsfiles_located{$sub_pbs_load_package})
			{
			$used_pbsfiles_located{$sub_pbs_load_package} = {} ;
			}
			
		#~ $used_pbsfiles_located{$sub_pbs_load_package}{$sub_pbs_name} = PBS::Digest::GetFileMD5($sub_pbs_name) ;
		
		$used_pbsfiles_located{$load_package}{$sub_pbs_load_package} = $used_pbsfiles_located{$sub_pbs_load_package} ;
		#attempt to micro warp, July 2005 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		
		# keep this node insertion info
		$sub_tree->{$sub_node_name}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} =  $tree->{__INSERTED_AT} ;
		
		# keep parent relationship
		for my $dependency_to_key (keys %{$tree->{__DEPENDENCY_TO}})
			{
			$sub_tree->{$sub_node_name}{__DEPENDENCY_TO}{$dependency_to_key} = $tree->{__DEPENDENCY_TO}{$dependency_to_key};
			}
			
		# copy the data generated by subpbs
		for my $new_key (keys %{$sub_tree->{$sub_node_name}})
			{
			# keep some  attributes defined from the current Pbs
			next if $new_key =~ /__NAME/ ;
			next if $new_key =~ /__USER_ATTRIBUTE/ ;
			next if $new_key =~ /__LINKED/ ;
			
			$tree->{$new_key} = $sub_tree->{$sub_node_name}{$new_key} ;
			}
			
		# make ourself the real node again
		$inserted_nodes->{$node_name} = $tree ;
		
		#~warn Data::Dumper->Dump($sub_tree, "sub_tree:\n") ;
		}
	}
else
	{
	if(@sub_pbs)
		{
		PrintError "In Pbsfile : $Pbsfile, $node_name has locally defined dependencies and matching subpbs definition:\n" ;
		for my $dependency (keys %$tree)
			{
			next if $dependency =~ /^__/ ;
			PrintError("\t$dependency\n") ;
			}
			
		PrintError(DumpTree(\@sub_pbs, "And Sub Pbs:")) ;
			
		Carp::croak ;
		}
		
	for my $dependency (keys %$tree)
		{
		next if $dependency =~ /^__/ ;
		
		# keep parent relationship
		my $key_name = $node_name . ': ' ;
		
		for my $rule (@{$dependency_rules{$dependency}})
			{
			$key_name .= $rule->[0] . ' ' . $rule->[1] ;
			}
		
		$tree->{$dependency}{__DEPENDENCY_TO}{$key_name} = $tree->{__DEPENDENCY_TO} ;
		
		# help user keep sanity by revealing some of the depend history
		if
			(
			   $tree->{$dependency}{__INSERTED_AT}{INSERTION_FILE} eq $Pbsfile
			&& defined $tree->{$dependency}{__DEPENDED_AT}
			&& $tree->{$dependency}{__DEPENDED_AT} ne $Pbsfile
			)
			{
			PrintWarning
				(
				  "Node '$dependency' inserted at rule: "
				. "$tree->{$dependency}{__INSERTED_AT}{INSERTION_RULE} "
				. " [Pbsfile: $tree->{$dependency}{__INSERTED_AT}{INSERTION_FILE}]"
				. " has been depended in Pbsfile: '$tree->{$dependency}{__DEPENDED_AT}'.\n"
				) ;
			
			#~ warn DumpTree($tree->{$dependency}, "node depended elsewhere:") ;
			
			my $ignored_rules ='' ;
			
			for(my $matching_rule_index = 0 ; $matching_rule_index < @$dependency_rules ; $matching_rule_index++)
				{
				my ($dependency_result) = $dependency_rules->[$matching_rule_index]{DEPENDER}->($dependency, $config, $tree->{$dependency}, $inserted_nodes) ;
				if($dependency_result->[0])
					{
					my $rule_info =  $dependency_rules->[$matching_rule_index]{NAME}
										. $dependency_rules->[$matching_rule_index]{ORIGIN} ;
										
					$ignored_rules .= "\t$matching_rule_index:$rule_info\n" ;
					}
				}
				
			PrintWarning("Local rules from '$Pbsfile' are ignored.\n$ignored_rules") if $ignored_rules ne '' ;
			}
			
		unless(exists $tree->{$dependency}{__DEPENDED})
			{
			CreateDependencyTree($Pbsfile, $package_alias, $load_package, $pbs_config, $tree->{$dependency}, $config, $inserted_nodes, $dependency_rules) ;
			}
		}
	}
	
if($tree->{__IMMEDIATE_BUILD})
	{
	PrintInfo2("** Immediate build of node $node_name **\n") ;
	my(@build_sequence, %trigged_files) ;
	
	my $nodes_checker ;
	PBS::Check::CheckDependencyTree
		(
		  $tree
		, $inserted_nodes
		, $pbs_config
		, $config
		, $nodes_checker
		, undef # single node checker
		, \@build_sequence
		, \%trigged_files
		) ;
	
	if($pbs_config->{DO_BUILD})
		{
		my ($build_result, $build_message) = PBS::Build::BuildSequence
															(
															  $pbs_config
															, \@build_sequence
															, $inserted_nodes
															) ;
			
		if($build_result == BUILD_SUCCESS)
			{
			PrintInfo2("** Immediate build of node '$node_name' Done **\n") ;
			}
		else
			{
			PrintError("** Immediate build of node '$node_name' Failed **\n") ;
			die "BUILD_FAILED" ;
			}
		}
	else
		{
		PrintInfo2("** Immediate build of node '$node_name' Skipped **\n") ;
		}
	}
	
#DEBUG
if($PBS::Debug::debug_enabled)
	{
	my %debug_data = 
		(
		  TYPE           => 'TREE'
		, PACKAGE_NAME   => $package_alias
		, PBSFILE        => $Pbsfile
		, TREE           => $tree
		, INSERTED_FILES => $inserted_nodes
		) ;
		
	$DB::single = 1 if (PBS::Debug::CheckBreakpoint(%debug_data)) ;
	}
}

#-------------------------------------------------------------------------------

sub LocatePbsfile
{
my $pbs_config   = shift ;
my $Pbsfile      = shift ;
my $sub_pbs_name = shift ;
my $rule         = shift ;

my $info = $pbs_config->{ADD_ORIGIN} ? "rule '$rule->{NAME}' at '$rule->{FILE}\:$rule->{LINE}'" : '' ;

my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;
my $sub_pbs_name_stem ;

if(File::Spec->file_name_is_absolute($sub_pbs_name))
	{
	PrintWarning "Using absolute subpbs: '$sub_pbs_name' $info.\n" ;
	}
else
	{
	my ($basename, $path, $ext) = File::Basename::fileparse($Pbsfile, ('\..*')) ;			
	
	my $found_pbsfile ;
	for my $source_directory (@$source_directories, $path)
		{
		my $searched_pbsfile = PBS::PBSConfig::CollapsePath("$source_directory/$sub_pbs_name") ;
		
		if(-e $searched_pbsfile)
			{
			if($found_pbsfile)
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Ignoring pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Located pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
					
				$found_pbsfile = $searched_pbsfile ;
				
				last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
				}
			}
		else
			{
			if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
				{
				PrintInfo "Couldn't find pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
				}
			}
		}
		
	my $sub_pbs_name_stem ;
	$found_pbsfile ||= "$path$sub_pbs_name" ;
	
	#check if we can find it somewhere else in the source directories
	for my $source_directory (@$source_directories)
		{
		my $flag = '' ;
		$flag = '(?i)' if $^O eq 'MSWin32' ;
		
		if($found_pbsfile =~ /$flag^$source_directory(.*)/)
			{
			$sub_pbs_name_stem = $1
			}
		}
		
	my $relocated_subpbs ;
	if(defined $sub_pbs_name_stem)
		{
		if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
			{
			PrintInfo "Found stem '$sub_pbs_name_stem'.\n" ;
			}
			
		for my $source_directory (@$source_directories)
			{
			my $relocated_from_stem = PBS::PBSConfig::CollapsePath("$source_directory/$sub_pbs_name_stem") ;
			
			if(-e $relocated_from_stem)
				{
				unless($relocated_subpbs)
					{
					$relocated_subpbs = $relocated_from_stem  ;
					
					if($relocated_from_stem ne $found_pbsfile)
						{
						PrintWarning2("Relocated '$sub_pbs_name_stem' in '$source_directory' $info.\n") ;
						}
					else
						{
						if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
							{
							PrintInfo "Keeping '$sub_pbs_name_stem' from '$source_directory' $info.\n" ;
							}
						}
						
					last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
					}
				else
					{
					if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
						{
						PrintInfo "Ignoring relocation of '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
						}
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Couldn't relocate '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
					}
				}
			}
		}
		
	$sub_pbs_name = $relocated_subpbs || $found_pbsfile || $sub_pbs_name;
	}

return($sub_pbs_name) ;
}

#-------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Depend  -

=head1 SYNOPSIS

  use PBS::Depend ;
  my $tree = {...} ;
  CreateDependencyTree(...) ;

=head1 DESCRIPTION

Given a node and a set of rules, B<CreateDependencyTree> will recursively build the entire dependency tree, inserting 
any pertinent information it gathers in the node.

=head2 EXPORT

None by default.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

