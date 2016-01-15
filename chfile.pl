#!/usr/bin/perl

use strict;
use warnings;
use utf8;



################################################################################
# Users' tool configuration                                                    #
################################################################################
#                                                                              #

#
# Any filesystem path matching any of patterns defined bellow will be allowed to
# be manipulated with this tool. Any filesystem path mismatching all the
# patterns will be reject from processing with this tool.
#
# *If NO PATTERN is configured ALL file paths CAN BE manipulated!*
#
# (Keep the definition after ‘use utf8’ to be able to directly define file paths
# using Unicode characters.)
#
my @allowed_filepath_patterns_re = (

    # Allow access to contents of .../testfiles/ directory *but not* to testfiles
    # directory itself (disallow user to delete / change permissions etc. of
    # testfiles directory itself, only allow manipulation of its contents).
    #
    #qr{\A/mnt/example/chfile.git/testfiles/.+\z},

    # Allow access to contents of .../testfiles/ directory *and* to testfiles
    # directory itself (allow user to also delete / change permissions etc. on
    # testfiles directory itself)
    # The ‘(\z|/.+\z)’ construction is necessary to mismatch files like
    # testfile_some_longe_filename in the same directory as testfiles directory
    # itself (i.e. /mnt/example/chfile.git/ in this example).
    #
    #qr{\A/mnt/example/chfile.git/testfiles(\z|/.+\z)},

    # Definition of directory using Unicode characters.
    #
    #qr{\A/mnt/example/chfile.git/testfiles/Šíleně žluťoučký kůň(\z|/.+\z)},

);

#                                                                              #
################################################################################



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
use Cwd;
use File::chmod qw(symchmod getsymchmod);
use FindBin;
use Getopt::Long qw(:config gnu_getopt no_ignore_case bundling);
use IO::Handle;
use Path::Tiny;
use Scalar::Util qw(blessed);
use Stat::lsMode;
use Try::Tiny;

# It is recommended that you explicitly set $File::chmod::UMASK
# as the default will change in the future
#
# 0 is recommended to behave like system chmod
# 1 if you want File::chmod to apply your environment set umask.
# 2 is how we detect that it's internally set, undef will become the
# default in the future, eventually a lexicaly scoped API may be designed
$File::chmod::UMASK = 0;



#
# Global configuration
#
my @files = ();
my $opts = {};
my @opts_def = (
    'chown|o=s',
    'chusr|u=s',
    'chgrp|g=s',
    'chmod|p=s',
    'cat|c',
    'rm|d',
    'help|h',
);
my $chown_re = qr/(\A[^:\s]+):([^:\s]+)\z/;


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
                 "{ [ --chown|-o <new_owner>:<new_group> ] | [ --chusr|-u <new_owner> ] [ --chgrp|-g <new_group> ] }",
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
                 "-o, --chown <new_owner>:<new_group>",
                 "Change owner and group of the file."),
            join("\t\n\t\t",
                 "-u, --chusr <new_owner>",
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

    if ($opts->{'chown'}) {
        print_usage_and_exit(3, 'Option `--chown` is mutually exclusive with `--chusr` and `--chgrp` options.')
                if (defined($opts->{'chusr'}) or defined($opts->{'chgrp'}));
        print_usage_and_exit(4, 'Invalid format of `--chown` parameter.')
                unless ($opts->{'chown'} =~ $chown_re);
    }

    print_usage_and_exit(5, 'No files to work on.')
            unless (scalar(@files) > 0);

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

# Path to absolute real path conversion with normalization and real filesystem
# solving of ALL symlinks / all symlinks BUT THE LAST symlink.
#
# 1. path normalization
#
# Path normalization is tricky and impossible without filesystem checks: For
# example having directory structure
#
#   ├── dir
#   │   ├── file
#   │   └── sub_dir
#   │       ├── file
#   │       ├── sub_link_to_file -> file
#   │       ├── sub_link_to_sub_dir -> ../sub_dir
#   │       └── sub_sub_dir
#   │           └── file
#   └──  link_to_file -> dir/file
#
# and path specifications
#
#   dir/../dir/file
#
# it is not enough to simply collapse dir/../dir/ to dir/ as it will not
# correctly work for links, i.e. collapsing link_to_sub_dir/../link_to_sub_dir/
# to link_to_sub_dir/ will change the path target:
#
#   $ ls dir/../dir/file
#   dir/../dir/file        <~~ this is file dir/file
#
#   $ ls dir/file
#   dir/file               <~~ this is file dir/file
#
#   $ ls link_to_sub_dir/../link_to_sub_dir/file
#   ls: cannot access link_to_sub_dir/../link_to_sub_dir/file: No such file or directory
#
#   $ ls link_to_sub_dir/file
#   link_to_sub_dir/file   <~~ this is file dir/sub_dir/file
#
# 2. resolving symlinks
#
# Two methods of symlink solving are introduced:
#
# – The first resolves ALL symlinks including the last component of the path.
#
#   The method is useful to work with the target file/directory (to read
#   contents of the target file/directory, to set attributes/permissions/... on
#   the target file/directory etc.).
#
#   real_path_dereference_all_symlinks($path):
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir
#     result    /.../dir/sub_dir
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/sub_link_to_file
#     result    /.../dir/sub_dir/file
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/sub_sub_dir
#     result    /.../dir/sub_dir/sub_sub_dir
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/file
#     result    /.../dir/sub_dir/file
#
# – The second method resolves ALL symlinks BUT the last component of the path.
#
#   This method is useful to manipulate the symlink itself (to delete the
#   symlink, for example) but not the target file/directory.
#
#   real_path_dereference_symlinks_but_last($path):
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir
#     result    /.../dir/sub_dir/sub_link_to_sub_dir
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/sub_link_to_file
#     result    /.../dir/sub_dir/sub_link_to_file
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/sub_sub_dir
#     result    /.../dir/sub_dir/sub_sub_dir
#
#     argument  dir/../dir/./sub_dir/sub_link_to_sub_dir/file
#     result    /.../dir/sub_dir/file
#
# args
#   path to normalize as string
# returns
#   normalized path with all symlinks resolved, i.e. even the last symlink in
#   the path will be resolved
sub real_path_dereference_all_symlinks {

    my $path = shift @_;

    return decode_locale_if_necessary(Cwd::realpath($path));

}
# args
#   path to normalize as string
# returns
#   normalized path with all symlinks but the last one resolved
sub real_path_dereference_symlinks_but_last {

    my $path = shift @_;

    return path($path)->realpath;

}

# Check if the tool runs in restricted mode, i.e. if only selected file paths
# are allowed to be manipulated.
#
# returns
#   1 if the tool runs in restricted mode, 0 otherwise
sub is_in_restricted_mode {

    if (scalar(@allowed_filepath_patterns_re) > 0) {
        return 1;
    } else {
        return 0;
    }

}

# Check if final real target of given path matches at least one allowed pattern
# if any is configured.
#
# args
#   instance of Path::Tiny
# returns
#   1 if the given filesystem path target matches at least one allowed pattern
#     or no pattern is defined at all;
#   0 otherwise
sub is_allowed_target_manipulation {

    my $file = shift @_;

    return 1 unless (is_in_restricted_mode());

    my $target_real_path = real_path_dereference_all_symlinks($file->canonpath);

    my $allowed = 0;
    foreach my $allowed_re (@allowed_filepath_patterns_re) {
        $allowed = 1 if $target_real_path =~ $allowed_re;
    }

    return $allowed;

}

# Check if final real object of given path (i.e. the final dir/file/... or
# symlink itself if the symlink is the last component of the given path) matches
# at least one allowed pattern if any is configured.
#
# args
#   instance of Path::Tiny
# returns
#   1 if the given filesystem path object matches at least one allowed pattern
#     or no pattern is defined at all;
#   0 otherwise
sub is_allowed_object_manipulation {

    my $file = shift @_;

    return 1 unless (is_in_restricted_mode());

    my $object_real_path = real_path_dereference_symlinks_but_last($file->canonpath);

    my $allowed = 0;
    foreach my $allowed_re (@allowed_filepath_patterns_re) {
        $allowed = 1 if $object_real_path =~ $allowed_re;
    }

    return $allowed;

}

# Cat mode of operation:
# Print file contents / list directory contents.
# args
#   instance of Path::Tiny
sub mode_cat {

    my $file = shift @_;

    if ($file->is_dir) {
        print join("\n\t",
            "Contens of directory '".$file->canonpath."':",
            sort map { decode_locale($_->basename) } $file->children)."\n";
    } else {
        print decode_locale_if_necessary($file->slurp);
    }

}

# Change owner and group mode of operation:
# Change owner and group of given file to given user and group.
# args
#   instance of Path::Tiny
#   user and group name as string <user>:<group>
sub mode_chown {

    my ($file, $usergroup) = @_;

    my ($user, $gname) = $usergroup =~ $chown_re;

    my $uid = getpwnam "$user";
    my $gid = getgrnam "$gname";

    unless (defined($uid)) {
        die "User '$user' does not exists.";
    }
    unless (defined($gid)) {
        die "Group '$gname' does not exists.";
    }

    if (chown($uid, $gid, $file->canonpath) > 0) {
        print_info("Changed ownership of file '".$file->canonpath."' to user '$user' and group '$gname'.");
    } else {
        die "Change ownership failed on file '".$file->canonpath."'";
    }

}

# Change owner mode of operation:
# Change owner of given file to given user.
# args
#   instance of Path::Tiny
#   user name as string
sub mode_chusr {

    my ($file, $user) = @_;

    my $uid = getpwnam "$user";

    unless (defined($uid)) {
        die "User '$user' does not exists.";
    }

    if (chown($uid, -1, $file->canonpath) > 0) {
        print_info("Changed owner on file '".$file->canonpath."' to '$user'.");
    } else {
        die "Change owner failed on file '".$file->canonpath."'";
    }

}

# Change group mode of operation:
# Change group of given file to given group.
# args
#   instance of Path::Tiny
#   group name as string
sub mode_chgrp {

    my ($file, $gname) = @_;

    my $gid = getgrnam "$gname";

    unless (defined($gid)) {
        die "Group '$gname' does not exists.";
    }

    if (chown(-1, $gid, $file->canonpath) > 0) {
        print_info("Changed group on file '".$file->canonpath."' to '$gname'.");
    } else {
        die "Change group failed on file '".$file->canonpath."'";
    }

}

sub mode_chmod {

    my ($file, $mode) = @_;

    die "Manipulation of 's' and 't' permissions is not allowed.\n"
        if (is_in_restricted_mode() and $mode =~ /[st]/);

    try {
        # Is x-bit set somewhere now?
        if (File::chmod::getmod($file->canonpath) & 0111) {
            $mode =~ s/X/x/g;
        } else {
            $mode =~ s/X//g;
        }
        symchmod($mode, $file->canonpath);
        print_info("Changed permissions on file '".$file->canonpath."' by '$mode' to '".format_mode(File::chmod::getmod($file->canonpath))."'.");
    } catch {
        die "Change permissions failed on file '".$file->canonpath."': "
            .decode_locale_if_necessary($_);
    };

}

# Delete mode of operation:
# Remove file or directory.
# args
#   instance of Path::Tiny
sub mode_rm {

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

    foreach my $f (@files) {

        my $file = path($f);

        print_info "Processing path '".$file->canonpath."'." if (scalar(@files) > 1);

        try {

            if (is_allowed_target_manipulation($file)) {

                # Cat
                mode_cat($file) if ($opts->{'cat'});

                # Change owner and group
                mode_chown($file, $opts->{'chown'}) if ($opts->{'chown'});

                # Change owner
                mode_chusr($file, $opts->{'chusr'}) if ($opts->{'chusr'});

                # Change group
                mode_chgrp($file, $opts->{'chgrp'}) if ($opts->{'chgrp'});

                # Change permissions
                mode_chmod($file, $opts->{'chmod'}) if ($opts->{'chmod'});

            } else {
                die "Access to '".real_path_dereference_all_symlinks($file->canonpath)."' is not allowed.";
            }

            if (is_allowed_object_manipulation($file)) {

                # Delete
                mode_rm($file) if ($opts->{'rm'});

            } else {
                die "Access to '".real_path_dereference_symlinks_but_last($file->canonpath)."' is not allowed.";
            }

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
