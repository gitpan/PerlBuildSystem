
=head1 EvaluateShellCommand

Let the Build system author to evaluate shell commands before they are run.  This allows
her to add variables like %SOME_SPECIAL_VARIABLE without interfering with PBS.

=cut


#-------------------------------------------------------------------------------

sub EvaluateShellCommand
{
my ($shell_command_ref, $tree) = @_ ;

#~ PrintDebug "'EvaluateShellCommand' plugin handling '$tree->{__NAME}' shell command $$shell_command_ref\n" ;
}

#-------------------------------------------------------------------------------

1 ;

