#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

# Set encoding translation according to system locale.
use Encode;
use Encode::Locale;
if (-t) {
    binmode(STDIN,  ":encoding(console_in)");
    binmode(STDOUT, ":encoding(console_out)");
    binmode(STDERR, ":encoding(console_out)");
} else {
    binmode(STDIN,  ":encoding(locale)");
    binmode(STDOUT, ":encoding(locale)");
    binmode(STDERR, ":encoding(locale)");
}
Encode::Locale::decode_argv(Encode::FB_CROAK);


# External modules
use Data::Dumper;
use File::Spec;
use FindBin;
use Getopt::Long qw(:config gnu_getopt no_ignore_case bundling);
use IO::Handle;
use Path::Tiny;
use Scalar::Util qw(blessed);
use Try::Tiny;



#
# Global configuration
#
my @files = ();
my $opts = {};
my @opts_def = (
    'chown|o=s',
    'chgrp|g=s',
    'chmod|p=s',
    'cat|c',
    'rm|d',
    'help|h',
);


#
# Subroutines
#

# Print script usage and exit.
# args
#   optional: exit value
#   optional: error message
sub print_usage_and_exit {

    my ($exit_val, $msg) = @_;

    $exit_val = 0 unless(defined($exit_val));
    my $out = \*STDERR;

    if (defined($msg)) {
        chomp $msg;
        print $out "$msg\n\n";
    }

    print $out join("\n\n",
        join("\n\t", 'Usage:',
            join(' ',
                 "$FindBin::Script",
                 "[ --cat|-c ]",
                 "[ --chown|-o <new_owner> ]",
                 "[ --chgrp|-g <new_group> ]",
                 "[ --chmod|-p <new_permissions> ]",
                 "--",
                 "file [ file ... ]",
            ),
            join(' ',
                 "$FindBin::Script",
                 "[ --rm|-d ]",
                 "--",
                 "file [ file ... ]",
            ),
            join(' ',
                 "$FindBin::Script",
                 "[ --help|-h ]",
            ),
        ),
        join("\n\t", 'Examples:',
            join(' ',
                 "$FindBin::Script",
                 "<input_file>",
                 "<input_dir>",
            ),
            join(' ',
                 "$FindBin::Script",
                 "--cat",
                 "<input_file>",
            ),
            join(' ',
                 "$FindBin::Script",
                 "-d",
                 "<input_file>",
                 "<input_dir>",
            ),
            join(' ',
                 "$FindBin::Script",
                 "--help",
            ),
        ),
        join("\n\t", 'Options:',
            join("\t\n\t\t",
                 "file [ file ... ]",
                 "List of one or more files to work on."),
            join("\t\n\t\t",
                 "-c, --cat",
                 "Show contents of the files.",
                 "This is the default mode of operations if no other options are specified."),
            join("\t\n\t\t",
                 "-o, --chown <new_owner>",
                 "Change owner of the file."),
            join("\t\n\t\t",
                 "-g, --chgrp <new_group>",
                 "Change group of the file."),
            join("\t\n\t\t",
                 "-p, --chmod <new_permissions>",
                 "Change permissions of the file."),
            join("\t\n\t\t",
                 "-d, --rm",
                 "Delete files.",
                 "This option cannot be combined with other options."),
            join("\t\n\t\t",
                 "-h, --help",
                 "Print the usage info and exit."),
        ),
    )."\n";

    exit($exit_val);

}

# Check validity of provided arguments. In case of an error exit with help
# message.
sub check_options {

    # If no mode is specified default to cat mode
    $opts->{'cat'} = 1
        if (scalar(keys($opts)) == 0);

    print_usage_and_exit() if ($opts->{'help'});

    print_usage_and_exit(2, 'Option `--rm` is not compatible with another commands.')
            if ($opts->{'rm'} and scalar(keys($opts)) != 1);

    print_usage_and_exit(3, 'No files to work on.')
            unless (scalar(@files) > 0);

    # TODO – check chown argument format
    # TODO – check chgrp argument format
    # TODO – check chmod argument format

}

# Decode string in system locale encoding to internal UTF-8 representation.
# args
#   string needing conversion
# returns
#   converted string
sub decode_locale {

    my $s = shift @_;

    if (not ref($s) or ref($s) eq 'SCALAR') {
        return decode(locale => $s)
    }

    return $s;

}

# Decode string in system locale encoding to internal UTF-8 representation
# unless already in UTF-8.
# args
#   string possibly needing conversion
# returns
#   converted string if conversion was necessary or
#   original value if no string passed or conversion was not necessary
sub decode_locale_if_necessary {

    my $s = shift @_;

    if (not ref($s) or ref($s) eq 'SCALAR') {
        return decode_locale($s) unless (Encode::is_utf8($s));
    }

    return $s;

}

# Returns formated message representing by exception object of instance of
# Path::Tiny::Error.
# args
#   instance of Path::Tiny::Error
# returns
#   formated message representing by given Path::Tiny::Error exception or
#   the original argument if the argument is not Path::Tiny::Error instance
sub format_path_tiny_error {

    my $err = shift @_;

    if (blessed $err && $err->isa('Path::Tiny::Error')) {
        return "Operation ".decode_locale_if_necessary($err->{'op'})
              ." on ".decode_locale_if_necessary($err->{'file'})
              ."failed: ".decode_locale_if_necessary($err->{'err'});
    } else {
        return $err;
    }

}

# Print processing warning message.
# args
#   message to print
sub print_error {

    my $msg = shift @_;

    chomp $msg;
    $msg = decode_locale_if_necessary($msg);

    IO::Handle::printflush STDERR "ERROR $msg\n";

}

# Print processing warning message.
# args
#   message to print
sub print_warning {

    my $msg = shift @_;

    chomp $msg;
    $msg = decode_locale_if_necessary($msg);

    IO::Handle::printflush STDERR "WARN $msg\n";

}

# Print processing info message.
# args
#   message to print
sub print_info {

    my $msg = shift @_;

    chomp $msg;
    $msg = decode_locale_if_necessary($msg);

    IO::Handle::printflush STDERR "INFO $msg\n";

}

# Cat mode of operation:
# Print file contents / list directory contents.
# args
#   instance of Path::Tiny
sub cat {

    my $file = shift @_;

    if ($file->is_dir) {
        print join("\n\t",
            "Contens of directory '".$file->canonpath."':",
            sort map { decode_locale($_->basename) } $file->children)."\n";
    } else {
        print decode_locale_if_necessary($file->slurp);
    }

}

# Delete mode of operation:
# Remove file or directory.
# args
#   instance of Path::Tiny
sub rm {

    my $file = shift @_;

    if ($file->is_dir) {
        if(rmdir($file->canonpath)) {
            print_info("Removed directory '".$file->canonpath."'.");
        } else {
            die decode_locale_if_necessary($!);
        }
    } else {
        if ($file->remove) {
            print_info("Removed file '".$file->canonpath."'.");
        } else {
            die decode_locale_if_necessary($!);
        }
    }

}



#
# Main
#

# Check and process command line options.
try {

    # Parse command line.
    GetOptions ($opts, @opts_def)
        or print_usage_and_exit(1, "Error in command line arguments");

    @files = @ARGV; # Use file paths from the command line.

    # Check the configuration.
    check_options();

} catch {
    die decode_locale_if_necessary($_);
};

# Do work
my $rv = 0;
try {

    print_info(Dumper($opts));
    print_info(scalar(Dumper(@files)));

    foreach my $f (@files) {

        my $file = path($f);

        print_info "Processing path '".$file->canonpath."'." if (scalar(@files) > 1);

        try {

            # Cat
            cat($file) if ($opts->{'cat'});

            # Delete
            rm($file) if ($opts->{'rm'});

        } catch {
            print_error("Skipping path '".$file->canonpath."', processing failed: "
                        .format_path_tiny_error($_));
            $rv++;
        };

    }

} catch {
    print_error(format_path_tiny_error($_));
    $rv++;
};

exit($rv);


# vim:textwidth=80:expandtab:tabstop=4:shiftwidth=4:fileencodings=utf8:spelllang=en
