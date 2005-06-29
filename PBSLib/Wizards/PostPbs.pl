# WIZARD_GROUP PBS
# WIZARD_NAME  post_pbs
# WIZARD_DESCRIPTION template for a post pbs
# WIZARD_ON

print <<EOT ;
PrintInfo <<EOPP ;
Hi from post pbs:

pbs_config      => \$pbs_config
build_success   => \$build_success 
dependency_tree => \$dependency_tree
build_sequence  => \$dependency_tree->{__BUILD_SEQUENCE}
inserted_nodes  => \$inserted_nodes 

EOPP

EOT

1;

