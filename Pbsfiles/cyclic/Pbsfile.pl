

# 2 c files including 2 header files but in a different order
# the header files include each other

# this leads to a dependency when the tree is merged though it is not
# an error when compiling each file per se


PbsUse('Configs/gcc') ;
PbsUse('Rules/Obigo') ; 
PbsUse('Rules/C') ; 

#-------------------------------------------------------------------------------

my @object_files = qw(a.c b.c) ;

AddRule [VIRTUAL], 'all',   [ 'all'     => 'cyclic_test' ], BuildOk("All finished.");
AddRule            'cyclic_test', [ 'cyclic_test' => 'cyclic_test.objects' ], LinkWith('libm');

AddRule 'objects', ['cyclic_test.objects' => @object_files], \&CreateObjectsFile ;
