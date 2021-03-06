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
use Cwd 2.12;
use File::chmod 0.40 qw(symchmod getsymchmod);
use FindBin;
use Getopt::Long 2.33 qw(:config gnu_getopt no_ignore_case bundling);
use IO::Handle 1.19;
use Path::Tiny 0.053;
use Scalar::Util qw(blessed);
use Stat::lsMode 0.50;
use Sys::Hostname;
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
my $opts = {
    'verbose' => 1,
};
my @opts_def = (
    'chown|o=s',
    'chusr|u=s',
    'chgrp|g=s',
    'chmod|p=s',
    'name|n',
    'scp|f',
    'cat|c',
    'rm|d',
    'machine|machine-readable|m',
    'verbose|v+',
    'silent|s' => sub {$opts->{'verbose'} = 0},
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

    if ($opts->{'verbose'} >= 1) {

        my $out = \*STDERR;

        my $m = join("\n\t", "$FindBin::Script",
                 "Simple file manipulation tool implemented in Perl language combining selected features of chmod, chown, cat, ls and rm core utils.",
                 '$Version$');
        if (defined($msg)) {
            chomp $msg;
            $m = "$msg";
        }

        print $out join("\n\n",
            $m,
            join("\n\t", 'Usage:',
                join(' ',
                     "$FindBin::Script",
                     "[ --name|-n ]",
                     "[ --scp|-f ]",
                     "[ --cat|-c ]",
                     "{ [ --chown|-o <new_owner>:<new_group> ] | [ --chusr|-u <new_owner> ] [ --chgrp|-g <new_group> ] }",
                     "[ --chmod|-p <new_permissions> ]",
                     "[ --machine|--machine-readable|-m ]",
                     "[ { --verbose|-v | --silent|-s } ]",
                     "--",
                     "file [ file ... ]",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--rm|-d",
                     "[ { --verbose|-v | --silent|-s } ]",
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
                     "testfiles/",
                     "testfiles/link_to_file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--name",
                     "testfiles/link_to_file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--scp -m",
                     "testfiles/link_to_file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--cat",
                     "testfiles/link_to_file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--chown root:users",
                     "testfiles/dir/file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--chusr root",
                     "testfiles/dir/",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--chgrp users",
                     "testfiles/",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--chmod u=rwx,go-w,a+X",
                     "testfiles/link_to_file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "-o root:users",
                     "-p u=rwx,a+rX",
                     "-v",
                     "testfiles/dir/",
                     "testfiles/dir/file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "-s",
                     "-c",
                     "-g users",
                     "testfiles/dir/file",
                ),
                join(' ',
                     "$FindBin::Script",
                     "--rm",
                     "testfiles/dir/sub_dir/",
                     "testfiles/link_to_file",
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
                     "--",
                     "`End of options` indicator.",
                     "Any argument after will not be consider a configuration option even though it looks like one."),
                join("\t\n\t\t",
                     "-n, --name",
                     "Show final real path of the files/directories.",
                     "If the given file path is a symlink, the symlink target will also be shown (dangling symlinks will be indicated).",
                     "This is the default mode of operations if no other options are specified."),
                join("\t\n\t\t",
                     "-f, --scp",
                     "Show final real path of the files/directories together with user's login name and hostname in the format suitable for scp/rsync.",
                     "If the given file path is a symlink, the symlink target will also be shown (dangling symlinks will be indicated)."),
                join("\t\n\t\t",
                     "-c, --cat",
                     "Show contents of the files/directories.",
                     "If the given file path is a symlink, the symlink target will be shown."),
                join("\t\n\t\t",
                     "-o, --chown <new_owner>:<new_group>",
                     "Change owner and group of the file.",
                     "This option cannot be combined with `--chusr` or `-chgrp`.",
                     "If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected."),
                join("\t\n\t\t",
                     "-u, --chusr <new_owner>",
                     "Change owner of the file.",
                     "This option cannot be combined with `--chown`.",
                     "If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected."),
                join("\t\n\t\t",
                     "-g, --chgrp <new_group>",
                     "Change group of the file.",
                     "This option cannot be combined with `--chown`.",
                     "If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected."),
                join("\t\n\t\t",
                     "-p, --chmod <new_permissions>",
                     "Change permissions of the file.",
                     "Beware the `X` manipulation is supported but presence of any `x` bit on target file is checked only at the very beginning of manipulation, not during after every group of settings.",
                     "I.e. definition `u=rwx,go=rX` applied to file with current mode `rw-r--r--` will end up with mode `rwxr--r--`, not `rwxr-xr-x` as could be expected.",
                     "If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected."),
                join("\t\n\t\t",
                     "-d, --rm",
                     "Delete files.",
                     "If the given file path is a symlink, the symlink itself will be deleted and the target file will not be affected.",
                     "This option cannot be combined with other options."),
                join("\t\n\t\t",
                     "-m, --machine, --machine-readable",
                     "Make output of `--name` and `--scp` machine readable by stripping out anything but clean path output string.",
                     "Symlinks are followed in this mode, i.e. print path of the link target."),
                join("\t\n\t\t",
                     "-v, --verbose",
                     "Verbose mode. In this mode not only errors and warnings (which is default behaviour) are shown but also information messages are listed.",
                     "Use of this option overrides `--silent` mode."),
                join("\t\n\t\t",
                     "-s, --silent",
                     "Silent mode. In this mode no information messages (including errors and warnings) are shown. Success/failure of processing is indicated by return value of the tool.",
                     "Use of this option overrides `--verbose` mode."),
                join("\t\n\t\t",
                     "-h, --help",
                     "Print the usage info and exit."),
            ),
        )."\n";

    }

    exit($exit_val);

}

# Check validity of provided arguments. In case of an error exit with help
# message.
sub check_options {

    # If no mode is specified default to name mode
    $opts->{'name'} = 1
        if (scalar(keys($opts)) == 1); # The only predefined value is verbosity level

    print_usage_and_exit() if ($opts->{'help'});

    print_usage_and_exit(2, 'Option `--rm` is not compatible with another commands.')
            if ($opts->{'rm'} and scalar(keys($opts)) != 2); # Checking for 2: the --rm option + predefined verbosity level.

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
              ." on '".decode_locale_if_necessary($err->{'file'})
              ."' failed: ".decode_locale_if_necessary($err->{'err'});
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

    IO::Handle::printflush STDERR "ERROR $msg\n" if ($opts->{'verbose'} >= 1);

}

# Print processing warning message.
# args
#   message to print
sub print_warning {

    my $msg = shift @_;

    chomp $msg;
    $msg = decode_locale_if_necessary($msg);

    IO::Handle::printflush STDERR "WARN $msg\n" if ($opts->{'verbose'} >= 1);

}

# Print processing info message.
# args
#   message to print
sub print_info {

    my $msg = shift @_;

    chomp $msg;
    $msg = decode_locale_if_necessary($msg);

    IO::Handle::printflush STDERR "INFO $msg\n" if ($opts->{'verbose'} >= 2);

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

    my $input_file = path($path);

    return path(decode_locale_if_necessary(Cwd::realpath($input_file->parent)))->child($input_file->basename);

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

# Name mode of operation:
# Print file real path. In case of a symlink print also target of the symlink.
# args
#   instance of Path::Tiny
sub mode_name {

    my $file = shift @_;

    my @targets = (real_path_dereference_symlinks_but_last($file->canonpath));

    my $arrow = '->';
    if (-l $file->canonpath) {
        push(@targets, real_path_dereference_all_symlinks($file->canonpath));
        $arrow = '-[dangling]->' unless (-e "$targets[1]");
    } else {
        die "No such file or directory\n" unless (-e "$targets[0]");
    }

    if ($opts->{'machine'}) {
        print "$targets[scalar(@targets-1)]\n";
    } else {
        print $file->canonpath.": ".join(" $arrow ", @targets)."\n";
    }

}

# scp/rsync name mode of operation:
# Print file real path. In case of a symlink print also target of the symlink.
# args
#   instance of Path::Tiny
sub mode_scp {

    my $file = shift @_;

    my $login = getpwuid($<) || getlogin || 'login';
    my $hostname = hostname();

    my $lh = "$login\@$hostname:";

    my @targets = (real_path_dereference_symlinks_but_last($file->canonpath));

    my $arrow = '->';
    if (-l $file->canonpath) {
        push(@targets, real_path_dereference_all_symlinks($file->canonpath));
        $arrow = '-[dangling]->' unless (-e "$targets[1]");
    }

    @targets = map { "$lh'$_'" } @targets;

    if ($opts->{'machine'}) {
        print "$targets[scalar(@targets-1)]\n";
    } else {
        print $file->canonpath.": ".join(" $arrow ", @targets)."\n";
    }

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
        die "User '$user' does not exists.\n";
    }
    unless (defined($gid)) {
        die "Group '$gname' does not exists.\n";
    }

    if (chown($uid, $gid, $file->canonpath) > 0) {
        print_info("Changed ownership of file '".$file->canonpath."' to user '$user' and group '$gname'.");
    } else {
        die "Change ownership failed on file '".$file->canonpath."'\n";
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
        die "User '$user' does not exists.\n";
    }

    if (chown($uid, -1, $file->canonpath) > 0) {
        print_info("Changed owner on file '".$file->canonpath."' to '$user'.");
    } else {
        die "Change owner failed on file '".$file->canonpath."'\n";
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
        die "Group '$gname' does not exists.\n";
    }

    if (chown(-1, $gid, $file->canonpath) > 0) {
        print_info("Changed group on file '".$file->canonpath."' to '$gname'.");
    } else {
        die "Change group failed on file '".$file->canonpath."'\n";
    }

}

# Change permissions mode of operation:
# Change permissions of given file to given mode.
# args
#   instance of Path::Tiny
#   permission modification specification as string
sub mode_chmod {

    my ($file, $mode) = @_;

    die "Manipulation of 's' and 't' permissions is not allowed.\n"
        if (is_in_restricted_mode() and $mode =~ /[st]/);

    try {

        die "No such file or directory\n" unless (-e real_path_dereference_all_symlinks($file->canonpath));

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

    if ($file->is_dir and not -l $file->canonpath) {
        if(rmdir($file->canonpath)) {
            print_info("Removed directory '".$file->canonpath."'.");
        } else {
            die decode_locale_if_necessary($!)."\n";
        }
    } else {
        if ($file->remove) {
            print_info("Removed file '".$file->canonpath."'.");
        } else {
            die decode_locale_if_necessary($!)."\n";
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
    die decode_locale_if_necessary($_)."\n";
};

# Do work
my $rv = 0;
try {

    foreach my $f (@files) {

        my $file = path($f);

        print_info "Processing path '".$file->canonpath."'." if (scalar(@files) > 1);

        try {

            if (is_allowed_target_manipulation($file)) {

                # Name
                mode_name($file) if ($opts->{'name'});

                # scp name
                mode_scp($file) if ($opts->{'scp'});

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
                die "Access to '".real_path_dereference_all_symlinks($file->canonpath)."' is not allowed.\n";
            }

            if (is_allowed_object_manipulation($file)) {

                # Delete
                mode_rm($file) if ($opts->{'rm'});

            } else {
                die "Access to '".real_path_dereference_symlinks_but_last($file->canonpath)."' is not allowed.\n";
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

$rv = 253 unless ($rv >= 0 and $rv <= 253);
exit($rv);


# vim:textwidth=80:expandtab:tabstop=4:shiftwidth=4:fileencodings=utf8:spelllang=en
