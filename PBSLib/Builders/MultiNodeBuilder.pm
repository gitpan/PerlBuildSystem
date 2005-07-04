sub MultiNodeBuilder
{
# this can be used when a single command builds multiple nodes and
# we don't want the command to be run multiple times
# an example is generating a swig wrapper and swig perl module

my ($package, $file_name, $line) = caller() ;

unless(@_ == 1 && 'CODE' eq ref $_[0])
	{
	die ERROR "Error: MultiNodeBuilder only accepts a single sub ref as builder." ;
	}

my $builder = shift ;
my @already_built ;

return
	(
	sub
		{
		my ($config, $file_to_build, $dependencies) = @_ ;
		
		unless(@already_built)
			{
			push @already_built, $file_to_build ;
			return($builder->(@_)) ;
			}
		else
			{
			push @already_built, $file_to_build ;
			return(1, "MultiNodeBuilder @ '$file_name:$line' was already run") ;
			}
		}
	) ;
	
}

1; 