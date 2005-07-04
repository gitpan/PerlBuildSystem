
use Data::TreeDumper ;

PrintDebug 
	DumpTree
		(
		$PBS::Depend::used_pbsfiles{$dependency_tree->{__PBS_CONFIG}{PBSFILE}}
		, $dependency_tree->{__PBS_CONFIG}{PBSFILE}
		, NO_NO_ELEMENTS => 1
		) ;

# when warpifing, add a dependency from each node to the pbsfile
# dump the above tree (could warpify it too)
# at check time, verify and trigger the tree
# when verifying the nodes, remove if the pbsfile has changed
