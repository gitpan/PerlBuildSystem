
use strict ;
use warnings ;

#-------------------------------------------------------------------------------

my $project_config = GetConfig("PROJECT_CONFIG") ;
my (undef, $file, $line) = caller(2) ;

if(defined $project_config && '' eq ref $project_config)
	{
	eval {PbsUse("$project_config") ;} ;
		
	if($@)
		{
		die ERROR ("Error while loading project configuration '$project_config' at  $file:$line:\n   $@") ;
		}
	}
else
	{
	die ERROR("Error loading project configuration: variable 'PROJECT_CONFIG' is not set properly at $file:$line.\n") ;
	}

#-------------------------------------------------------------------------------
1 ;

