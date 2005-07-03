#!/usr/bin/env perl

# Tests for command line flags.

package t::Misc::CommandLineFlags;

use strict;
use warnings;

use base qw(Test::Class);

use Test::More;
use t::PBS;

my $t;

sub setup : Test(setup) {
    $t = t::PBS->new(string => 'Command line flags');

    $t->build_dir('build_dir');
    $t->target('file.target');

    $t->write('post_pbs.pl', <<'_EOF_');
    for my $node( @{$dependency_tree->{__BUILD_SEQUENCE}}) {
	print "Rebuild node $node->{__NAME}\n";
    }
1;
_EOF_

    $t->command_line_flags('--post_pbs=post_pbs.pl');
}

# removed when Simplified rules made it to plugins
# -nge doesn't set the plugin path and thus fails the test now

sub flag_nge : Test(4) {
    # Write files
    $t->subdir('subdir');
    $t->write_pbsfile(<<'_EOF_');
	PbsUse('Language/Simplified');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');
    $t->write('subdir/file.in', 'file2 contents');

	# Set PBS_LIB_PATH so PBS can find Language/Simplified
    $t->command_line_flags($t->command_line_flags . ' --plp=' . $ENV{PBS_LIB_PATH});

    # Build
    $ENV{'PBS_FLAGS'} = ' --source_directory subdir';
    $t->build_test();
    $t->test_target_contents('file2 contents');

    # Specify --nge so the source directory is not used and rebuild
    $t->command_line_flags($t->command_line_flags . ' --nge');
    $t->build_test();
    $t->test_target_contents('file contents');

    $ENV{'PBS_FLAGS'} = '';
}


sub flag_a : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file1.immediate',
                                        'file2.immediate'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
    AddRule 'imm1', ['file1.immediate' => 'file2.in', 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
    AddRule 'imm2', ['file2.immediate' => 'file3.in', 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_

    # Build
    $t->command_line_flags($t->command_line_flags . ' --a=file.in');
    $t->build_test();
	my $stdout = $t->stdout;
	like($stdout, qr|file\.in' ancestors.*file1\.immediate.*file\.target.*file2\.immediate.*file\.target|s, 'Correct output from build with ancestors');
}

sub flag_l : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');

    # Build
    $t->command_line_flags($t->command_line_flags . ' --l');
    $t->build_test();
    my $stdout = $t->stdout;
    $stdout =~ qr|(build_dir/PBS_LOG/PBS_LOG.*)'|;
    my $log_file = $1;
    $t->test_file_exist($log_file);
}

sub flag_kpbb : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file1.immediate',
                                        'file2.immediate'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
    AddRule 'imm1', ['file1.immediate' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
    AddRule 'imm2', ['file2.immediate' => 'file2.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');
    $t->write('file2.in', 'file2 contents');

    # Build
    $t->command_line_flags($t->command_line_flags . ' --kpbb -j=1');
    if ($^O eq 'MSWin32')
	{
		TODO: {
			local $TODO = '-j does not work on Windows';
			#			$t->build_test();
			$t->test_file_exist_in_build_dir('PBS_BUILD_BUFFERS/PBS::Shell__node_._file.target');
		}
	}
    else
	{
		$t->build_test();

		$t->test_file_exist_in_build_dir('PBS_BUILD_BUFFERS/PBS::Shell__node_._file.target');
	}
}

sub flag_dd : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_

    # Build
    $t->command_line_flags($t->command_line_flags . ' --dd');
    $t->build_test();
    my $stdout = $t->stdout;
    like($stdout, qr|file\.target has dependencies \[\./file.in\].*file\.in has no locally defined dependencies|s, 'Correct output from build with display dependencies');
}

sub flag_gtg : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');

    # Build
    $t->command_line_flags($t->command_line_flags . ' --gtg=graph.png');
    if ($^O eq 'MSWin32')
	{
		TODO: {
			local $TODO = 'Generate tree graph does not work on Windows';
			$t->build_test();
			ok(-s 'graph.png', 'Graph file has nonzero size');
		}
	}
    else
	{
		$t->build_test();
		ok(-s 'graph.png', 'Graph file has nonzero size');
	}
}

sub flag_p : Test(2) {
    # Test that the specified Pbsfile is used

    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('pbsfile2', <<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file.target' => 'file2.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');
    $t->write('file2.in', 'file2 contents');

    # Build
    $t->command_line_flags($t->command_line_flags . ' --p=pbsfile2');
    $t->build_test();
    $t->test_target_contents('file2 contents');
}

sub flag_prf : Test(2) {
    # Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', ['file2.target' => 'file.in'] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('file.in', 'file contents');
    $t->write('responsefile', "\$TEST_TARGET\n");

    # Build
    $t->command_line_flags($t->command_line_flags . ' --prf responsefile');
    $ENV{'TEST_TARGET'} = 'file2.target';
    $t->target('');
    $t->build_test();
    $t->test_file_contents($t->catfile($t->build_dir, 'file2.target'), 'file contents');
}

sub flag_plp : Test(2) {
# Write files
    $t->write_pbsfile(<<'_EOF_');
    PbsUse('Intermediate');
    AddRule 'target', [ 'file.target' => 'file.intermediate' ] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->write('Intermediate.pm', <<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'intermediate', [ '*.intermediate' => '*.in' ] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
	
    1 ;
_EOF_
    $t->write('file.in', 'file contents');

# Build
    $t->command_line_flags($t->command_line_flags . ' --plp ./');
    $t->build_test;
    $t->test_target_contents('file contents');
}

sub flag_ppp : Test(2) {
# Write files
    $t->write_pbsfile(<<'_EOF_');
    ExcludeFromDigestGeneration('in-files' => qr/\.in$/);
    AddRule 'target', [ 'file.target' => 'file.in' ] =>
	'cat %DEPENDENCY_LIST > %FILE_TO_BUILD';
_EOF_
    $t->subdir('plugin_dir');
    $t->write('plugin_dir/TestPlugin.pm', <<'_EOF_');
sub CreateLog {
    my ($pbs_config, $dependency_tree, $inserted_nodes, $build_sequence, $build_node) = @_ ;
    print "Test plugin\n";
}

1 ;

_EOF_
    $t->write('file.in', 'file contents');

# Build
    $t->command_line_flags($t->command_line_flags . ' --ppp ./plugin_dir');
    $t->build_test;
    my $stdout = $t->stdout;
    like($stdout, qr|Test plugin\n|, 'Plugin output');
}

unless (caller()) {
    $ENV{"TEST_VERBOSE"} = 1;
    Test::Class->runtests;
}

1;
