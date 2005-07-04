=head1 PBSFILE USER HELP

=head2 Top rules

=over 2 

=item * 'all'

=back

=cut

PbsUse('Rules/C') ;
PbsUse('Configs/gcc') ;

AddRule [VIRTUAL], 'all', ['all' => 'a.out']; #, BuildOk('') ;

AddRule 'a.out', ['a.out' => 'hello.o'] ;
	#, ["%CC -o %FILE_TO_BUILD DEPENDENCY_LIST"] ;

