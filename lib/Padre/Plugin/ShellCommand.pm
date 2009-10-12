package Padre::Plugin::ShellCommand;

use 5.008;
use strict;
use warnings;
use Padre::Constant ();
use Padre::Current  ();
use Padre::Plugin   ();
use Padre::Wx       ();
use File::Temp qw/ tempfile /;

our $VERSION = '0.2';
our @ISA     = 'Padre::Plugin';

#####################################################################
# Padre::Plugin Methods

sub plugin_name {
    'ShellCommand';
}

sub padre_interfaces {
    'Padre::Plugin' => 0.43;
}

sub menu_plugins_simple {
    my ($self) = @_;

    ShellCommand => [
        Wx::gettext("Run Command\tAlt+Shift+R") => sub { $self->run_command(0) },
        Wx::gettext("Run Command Replace")      => sub { $self->run_command(1) },
    ];
}

#####################################################################
# Custom Methods

sub get_cmd {
    my ( $self, $editor ) = @_;
    my %cmd;

    if ( $editor->GetSelectedText() ) {
        $cmd{cmd}        = $editor->GetSelectedText();
        $cmd{start_pos}  = $editor->GetSelectionStart();
        $cmd{start_line} = $editor->LineFromPosition( $cmd{start_pos} );
        $cmd{end_pos}    = $editor->GetSelectionEnd();
        $cmd{end_line}   = $editor->LineFromPosition( $cmd{end_pos} );
    }
    else {

        # the command is the current line
        $cmd{start_line} = $editor->LineFromPosition( $editor->GetCurrentPos() );
        $cmd{start_pos}  = $editor->PositionFromLine( $cmd{start_line} );
        $cmd{end_line}   = $cmd{start_line};
        $cmd{end_pos}    = $editor->GetLineEndPosition( $cmd{end_line} );
        $cmd{cmd}        = $editor->GetTextRange( $cmd{start_pos}, $cmd{end_pos} );
    }
    $cmd{has_shebang} = ( $cmd{cmd} =~ m/^\s*#!/ ) ? 1 : 0;

    # is it a command or should it be wrapped it in a cat block?
    unless ( $cmd{has_shebang} ) {
        my ($test) = $cmd{cmd} =~ m/^\s*([^\s]+)/;
        my @ary = `which $test 2>&1`;
        if ($?) {
            $cmd{cmd}         = "#!/bin/sh\ncat <<EIEIOT\n" . $cmd{cmd} . "\nEIEIOT\n";
            $cmd{has_shebang} = 1;
        }
    }
    return %cmd;
}

sub set_environment {
    my ( $self, $editor ) = @_;

    # Set up various environment variables that may be useful to scripts/commands
    my $document = $editor->{Document};
    $ENV{PE_FILEPATH}   = $document->filename();
    $ENV{PE_BASENAME}   = $document->basename();
    $ENV{PE_DIRECTORY}  = $document->dirname();
    $ENV{PE_MIMETYPE}   = $document->get_mimetype();
    $ENV{PE_CONFIG_DIR} = Padre::Constant::CONFIG_DIR;

    my $config = $self->current->main->ide->config;
    $ENV{PE_INDENT_TAB_WIDTH} = $config->editor_indent_tab_width;
    $ENV{PE_INDENT_WIDTH}     = $config->editor_indent_width;
    $ENV{PE_INDENT_TAB}       = ( $config->editor_indent_tab ) ? 'YES' : 'NO';
    $ENV{PE_DEF_PROJ_DIR}     = $config->default_projects_directory;
}

sub run_command {
    my ( $self, $replace_cmd ) = @_;

    my $editor = $self->current->editor;
    $editor->Freeze;

    $self->set_environment($editor);

    my %cmd = $self->get_cmd($editor);
    my @cmd_out;

    if ( $cmd{has_shebang} || $cmd{start_line} != $cmd{end_line} ) {
        my ( $fh, $filename ) = tempfile('PDT_XXXXXXXX');
        if ($fh) {
            print $fh $cmd{cmd};
            close $fh;
            `chmod u+x $filename`;

            # Use shebang if there is one, otherwise not.
            @cmd_out
                = ( $cmd{has_shebang} )
                ? `./$filename 2>&1`
                : `sh $filename 2>&1`;

            # In case of errors, we don't want the temp filename
            # showing up in the output as it is pretty ugly and
            # doesn't add anything to the conversation.
            if ($?) {
                $_ =~ s/^[.\/]*$filename/ERR/ for @cmd_out;
            }

            # We could use "tempfile (..., UNLINK => 1)" above but
            # then the temporary files hang around until Padre exits.
            # Therefore we explicity delete the temporary file as
            # soon as we are done with them.
            ( -f $filename ) && unlink $filename;
        }
    }
    else {

        # It's a one-liner
        @cmd_out = `$cmd{cmd} 2>&1`;
    }

    if (@cmd_out) {
        if ($replace_cmd) {
            my $text = join '', @cmd_out;
            chomp $text;
            $editor->SetSelection( $cmd{start_pos}, $cmd{end_pos} );
            $editor->ReplaceSelection($text);
        }
        else {
            my $text = "\n" . join '', @cmd_out;
            $editor->GotoPos( $cmd{end_pos} );
            $editor->insert_text($text);
        }
    }
    $editor->Thaw;
}

1;

__END__

=pod

=head1 NAME

Padre::Plugin::ShellCommand - A Shell Command plug-in

=head1 DESCRIPTION

This plug-in takes shell commands from the active document and inserts the 
output of the command into the document.

If text is selected then the plug-in will attempt to execute the selected text.
If no text is selected the the plug-in will attempt to execute the current line 
as a command.

"Commands" can either be valid shell commands, entire scripts (with shebang), or
environment variables to be evaluated.

There are two associated menu items:

=over

=item "Run Command" inserts the command output after the command while 

=item "Run Command Replace" replaces the command with the command output.

=back

To assist in running shell commands this plug-in also sets some environment 
variables that may be of use to the commands being run. The following Padre 
Environment (PE_) are set.

=over

=item PE_BASENAME  -- The file name of the current document.

=item PE_DIRECTORY -- The directory of the current document.

=item PE_FILEPATH  -- The full path and name of the current document.

=item PE_MIMETYPE  -- The mime-type of the current document.

=item PE_CONFIG_DIR    -- Location of the configuration directory (~/.padre)

=item PE_DEF_PROJ_DIR  -- The default project directory.

=item PE_INDENT_TAB         -- Use tabs for indentation. 'YES' or 'NO'

=item PE_INDENT_TAB_WIDTH   -- Tab width/size.

=item PE_INDENT_WIDTH       -- Indentation width/size.

=back

=head1 EXAMPLES

=head4 Example 1

Typing `$USER` on an otherwise blank line and invoking 'Run Command'
without selecting anything would insert your user-name on the next line down.

    $USER
    gsiems

=head4 Example 2

Combinations of Environment variables and commands are also possible:

    $USER was last seen on `date`
    gsiems was last seen on Fri Oct  9 16:12:11 CDT 2009

=head4 Example 3

By typing, on an otherwise blank line, `The date is:` then selecting the word 
`date` and invoking 'Run Command' results in the date being inserted on the 
next line down.

    The date is:
    Fri Oct  9 16:12:11 CDT 2009

=head4 Example 4 (Mult-line scripts)

Typing a multi-line script, selecting the entire script and invoking 
'Run Command' will run the entire selection as a shell script:

So:

    for I in 1 2 3 ;
        do
        echo " and a $I"
    done
    
Inserts:

     and a 1
     and a 2
     and a 3

after the script block.

=head4 Example 5 (The whole shebang)

Shebangs are supported so the scripts aren't limited to shell commands/scripts.

For example, typing (and selecting) the following

    #!/usr/bin/env perl
    print " and a $_\n" for (qw(one two three));
    
and invoking 'Run Command' inserts:

     and a one
     and a two
     and a three

after the script block.

=head4 Example 6 (PE_ variables)

Running the following:

    #!/bin/sh
    set | grep "^PE_"

Inserts something like:

    PE_BASENAME=padre_test.pl
    PE_CONFIG_DIR=/home/gsiems/.padre
    PE_DEF_PROJ_DIR=/home/gsiems/projects
    PE_DIRECTORY=/home/gsiems
    PE_FILEPATH=/home/gsiems/padre_test.pl
    PE_INDENT_TAB=NO
    PE_INDENT_TAB_WIDTH=4
    PE_INDENT_WIDTH=4
    PE_MIMETYPE=application/x-perl

So, for instance, a user created script `mkheader` could use PE_BASENAME 
and PE_MIMETYPE to create an appropriate header for different file types.

=head1 LIMITATIONS

This plug-in will not work on operating systems that do not have an appropriate 
shell environment (such as MS Windows).

=head1 AUTHOR

Gregory Siems E<lt>gsiems@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Gregory Siems

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
