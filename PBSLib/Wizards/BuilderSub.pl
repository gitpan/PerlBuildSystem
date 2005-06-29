# WIZARD_GROUP PBS
# WIZARD_NAME  builder
# WIZARD_DESCRIPTION template for a builder sub
# WIZARD_ON

print <<'EOP' ;
sub Builder
{
my ($config, $file_to_build, $dependencies) = @_ ;
#~my ($config, $file_to_build, $dependencies, $triggering_dependencies, $file_tree, $inserted_nodes) = @_ ;

if($PBS::user_options{display_BuildAnExe})
	{
	}

my @commands =
	(
	  "$config->{CC} -c -o" 
	, 'ls -lsa'
	) ;

RunShellCommands(@commands) ;
  
#~return(0, "Some  error") ;
return(1, "OK Builder") ;
}

EOP


