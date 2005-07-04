
=head1 'Rules/C.pm'

This is a B<PBS> (Perl Build System) module.

=head1 When is 'Rules/C.pm' used?

Whenever we need to build object files from  c, cpp or assembler source.

=head1 What 'Rules/C.pm' does.

=cut 

use strict ;
use warnings ;
use PBS::PBS ;
use PBS::Rules ;

=over 2 

=item * Add a C depender Rule in your Pbsfile

=back

=cut

PbsUse('Rules/C_depender') ;
PbsUse('MetaRules/FirstAndOnlyOneOnDisk') ;

# todo
# remove from CFLAGS_INCLUDE all the repository directories, it's is not a mistake to leave them but it look awkward
# to have the some include path twice on the command line

=over 2 

=item * define the variable C_DEFINES if not already defined and make all object file depend on it

=item * define the variable CFLAGS_INCLUDE if not already defined

=back

=cut

unless(GetConfig('CDEFINES'))
	{
	my @defines = %{GetPbsConfig()->{COMMAND_LINE_DEFINITIONS}} ;
	if(@defines)
		{
		AddCompositeDefine('CDEFINES', @defines) ;
		}
	else
		{
		AddConfig('CDEFINES', '') ;
		}
	}
	
my %config = GetConfig() ;
my $c_defines = $config{CDEFINES} ;
AddNodeVariableDependencies(qr/\.o$/, CDEFINES => $c_defines) ;

unless($config{CFLAGS_INCLUDE})
	{
	my $pbs_config = GetPbsConfig() ;
	
	my $cflags_include = '-I' ;
	$cflags_include .= join " -I",  @{$pbs_config->{SOURCE_DIRECTORIES}} ;
		
	PrintUser("[PBS]C.pm: Adding config variable 'CFLAGS_INCLUDE' = '$cflags_include'.\n") ;
	
	AddConfig('CFLAGS_INCLUDE' => $cflags_include);
	}
	
=over 2 

=item * tag cpp, c, header, assembler , library, ...  files as source only

=back

=cut

ExcludeFromDigestGeneration
	(
	  'cpp_files' => qr/\.cpp$/
	, 'c_files'   => qr/\.c$/
	, 's_files'   => qr/\.s$/
	, 'h_files'   => qr/\.h$/
	, 'libs'      => qr/\.a$/
	) ;

=over 2 

=item * Adds the rules for building objects files

=back

=cut

AddRuleTo 'BuiltIn', 'c_objects', [ '*/*.o' => '*.c' ]
	, "%CC %CFLAGS %CDEFINES %CFLAGS_INCLUDE -I%PBS_REPOSITORIES -o %FILE_TO_BUILD -c %DEPENDENCY_LIST" ;
	
AddRuleTo 'BuiltIn', 'cpp_objects', [ '*/*.o' => '*.cpp' ]
	, "%CXX %CXXFLAGS %CDEFINES %CFLAGS_INCLUDE -I%PBS_REPOSITORIES -o %FILE_TO_BUILD -c %DEPENDENCY_LIST" ;
		
AddRuleTo 'BuiltIn', 's_objects', [ '*/*.o' => '*.s' ]
	, "%AS %ASFLAGS %ASDEFINES %ASFLAGS_INCLUDE -I%PBS_REPOSITORIES -o %FILE_TO_BUILD %DEPENDENCY_LIST" ;

=over 2 

=item * Adds a meta rule to arbiter between different types of source code

=back

=cut

AddRuleTo 'BuiltIn', [META_RULE], 'o_cs_meta',
	[\&FirstAndOnlyOneOnDisk, ['cpp_objects', 'c_objects', 's_objects'], 'c_objects'] ;

#-------------------------------------------------------------------------------

1 ;

