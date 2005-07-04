
# This example shows how to generate multiple node with a single command.

PbsUse 'Builders/MultiNodeBuilder' ;

AddRule [VIRTUAL], "all",['all' => 'A', 'A_B', 'A_C'], BuildOk() ;

AddRule "A_or_B", [qr/A/], MultiNodeBuilder(\&Builder) ;

sub Builder 
{
my ($config, $file_to_build, $dependencies) = @_ ;

RunShellCommands("touch $file_to_build ${file_to_build}_B ${file_to_build}_C") ;
}
