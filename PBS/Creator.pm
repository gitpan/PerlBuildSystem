
package PBS::Creator;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;
use AutoLoader qw(AUTOLOAD) ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(ScanForPlugins RunPluginSubs RunUniquePluginSub) ;
our $VERSION = '0.01' ;

use File::Basename ;
use Getopt::Long ;
use Cwd ;

use PBS::Constants ;
use PBS::PBSConfig ;
use PBS::Output ;

#-------------------------------------------------------------------------------

use Data::TreeDumper ;
use File::Path ;
use Digest::MD5 qw(md5_hex) ;

#---------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Creator - Handle creator digest

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 EXPORT

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
