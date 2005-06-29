
use Module::Build;

my @pm_files = qw(
PBS/Attributes.pm
PBS/Build.pm
PBS/Build/NodeBuilder.pm
PBS/Build/Threaded.pm
PBS/Build/Forked.pm
PBS/Build/ForkedNodeBuilder.pm
PBS/Build/LightWeightServer.pm
PBS/Check.pm
PBS/Cyclic.pm
PBS/Config.pm
PBS/Constants.pm
PBS/DefaultBuild.pm
PBS/Debug.pm
PBS/Depend.pm
PBS/Digest.pm
PBS/Distributor.pm
PBS/Documentation.pm
PBS/FrontEnd.pm
PBS/Graph.pm
PBS/Graph/Html.pm
PBS/Graph/Snapshots.pm
PBS/GraphViz.pm
PBS/Output.pm
PBS/PBS.pm
PBS/PBSConfig.pm
PBS/PBSConfigSwitches.pm
PBS/Plugin.pm
PBS/ProgressBar.pm
PBS/Rules.pm
PBS/Rules.pm
PBS/Rules/Dependers.pm
PBS/Rules/Dependers/Subpbs.pm
PBS/Rules/Builders.pm
PBS/Rules/Metarules.pm
PBS/Triggers.pm
PBS/PostBuild.pm
PBS/Shell.pm
PBS/Shell/SSH.pm
PBS/Shell/Telnet.pm
PBS/Wizard.pm
PBS/Information.pm
PBS/Log.pm
PBS/Warp1_5.pm
);

my $build = Module::Build->new
	(
	module_name => 'PerlBuildSystem',
	dist_version_from => 'PBS/FrontEnd.pm',
	license => 'restrictive',
	requires => 
		{
		Data::TreeDumper    => '0.20',
		Getopt::Long        => '2.32',
		Cwd                 => '2.06',
		Data::Dumper        => '2.12',
		File::Basename      => '2.71',
		Tie::IxHash         => '1.21',
		Tie::Hash::Indexed  => '0.03',
		Devel::Depend::Cpp  => '0.05',
		Devel::Depend::Cl   => '0.01',
		Devel::Cycle        => '0',
		File::MkTemp        => '0',
		GraphViz            => '0',
		Math::Pari          => '0',
		Net::Telnet         => '0',
		Net::SSH::Perl      => '0',
		Pod::Simple::Search => '0',
		Data::Compare       => '0',
		Test::Class         => '0',
		Test::Cmd           => '0',
		Term::ProgressBar   => '0',
		File::Copy::Recursive => '0',
		File::Spec          => '',
		
		#Term::ANSIColor => ?
		#Text::Balanced => ?
		},
		
	pm_files     => {map {$_ => "lib/$_"} @pm_files},
	autosplit    => \@pm_files,
	
	script_files => 'pbs.pl',
	dist_author  => 'Khemir Nadim ibn Hamouda. <nadim@khemir.net>',

	);
	
$build->create_build_script;
  
