#
# This file is part of Padre::Plugin::ShellCommand
# 

use Test::More tests => 1;

use Padre;

diag "Padre: $Padre::VERSION";
diag "Wx Version: $Wx::VERSION " . Wx::wxVERSION_STRING();

BEGIN {
    use_ok( 'Padre::Plugin::ShellCommand' );
}

diag( "Testing Padre::Plugin::ShellCommand $Padre::Plugin::ShellCommand::VERSION, Perl $], $^X" );
