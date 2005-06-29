#!/usr/bin/perl

package PerlBuildSystem ;

use strict ;
use warnings ;

#~ use PBS::Debug ;
use PBS::Output ;

use vars qw ($VERSION) ;
$VERSION = '0.28' ;

use PBS::FrontEnd ;

#-------------------------------------------------------------------------------

my ($success, $message) = PBS::FrontEnd::Pbs(COMMAND_LINE_ARGUMENTS => [@ARGV]) ;

if($success)
	{
	}
else
	{
	PrintError($message) ;
	exit(! $success) ;
	}

#-------------------------------------------------------------------------------

__END__
=head1 NAME

PerlBuildSystem - (PBS) Build system written in perl.

=head1 SYNOPSIS

perl pbs.pl all
perl pbs.pl -c -a a.h -f all

=head1 DESCRIPTION

'pbs.pl' is an utility script used to kick start PBS through its FrontEnd module.

PBS functionality is available through the standard module mechanism which allows you to integrate
a build system in your scripts.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

Parts of the development was funded by B<C-Technologies AB, Ideon Research Center, Lund, Sweden>.

=head1 SEE ALSO

PBS::PBS.

=cut
