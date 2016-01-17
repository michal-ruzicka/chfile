# `chfile.pl`

`chfile.pl` is a simple file manipulation tool implemented in Perl language
combining selected features of `chmod`, `chown`, `cat`, `ls` and `rm` core
utils.

## Restricted mode

The tools can be run in an *unrestrestricted mode*, that does not limit the tool
functionality in any way, or in the *restricted mode*.

To switch to restricted mode a set of filesystem paths patterns have to be
configured. Consequently no operation will be done by the tool on any filesystem
path not matching any of these pattern. Moreover, no manipulation of ‘s’ or ‘t’
permission will be allowed even on files matching configured allowed patterns.

## Usage

The tools has build-in help. To see usage information run

`chfile.pl --help`

```
chfile.pl
	Simple file manipulation tool implemented in Perl language combining selected features of chmod, chown, cat, ls and rm core utils.

Usage:
	chfile.pl [ --name|-n ] [ --scp|-f ] [ --cat|-c ] { [ --chown|-o <new_owner>:<new_group> ] | [ --chusr|-u <new_owner> ] [ --chgrp|-g <new_group> ] } [ --chmod|-p <new_permissions> ] [ --machine|--machine-readable|-m ] [ { --verbose|-v | --silent|-s } ] -- file [ file ... ]
	chfile.pl --rm|-d [ { --verbose|-v | --silent|-s } ] -- file [ file ... ]
	chfile.pl [ --help|-h ]

Examples:
	chfile.pl testfiles/ testfiles/link_to_file
	chfile.pl --name testfiles/link_to_file
	chfile.pl --scp -m testfiles/link_to_file
	chfile.pl --cat testfiles/link_to_file
	chfile.pl --chown root:users testfiles/dir/file
	chfile.pl --chusr root testfiles/dir/
	chfile.pl --chgrp users testfiles/
	chfile.pl --chmod u=rwx,go-w,a+X testfiles/link_to_file
	chfile.pl -o root:users -p u=rwx,a+rX -v testfiles/dir/ testfiles/dir/file
	chfile.pl -s -c -g users testfiles/dir/file
	chfile.pl --rm testfiles/dir/sub_dir/ testfiles/link_to_file
	chfile.pl --help

Options:
	file [ file ... ]
		List of one or more files to work on.
	--
		`End of options` indicator.
		Any argument after will not be consider a configuration option even though it looks like one.
	-n, --name
		Show final real path of the files/directories.
		If the given file path is a symlink, the symlink target will also be shown (dangling symlinks will be indicated).
		This is the default mode of operations if no other options are specified.
	-f, --scp
		Show final real path of the files/directories together with user's login name and hostname in the format suitable for scp/rsync.
		If the given file path is a symlink, the symlink target will also be shown (dangling symlinks will be indicated).
	-c, --cat
		Show contents of the files/directories.
		If the given file path is a symlink, the symlink target will be shown.
	-o, --chown <new_owner>:<new_group>
		Change owner and group of the file.
		This option cannot be combined with `--chusr` or `-chgrp`.
		If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected.
	-u, --chusr <new_owner>
		Change owner of the file.
		This option cannot be combined with `--chown`.
		If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected.
	-g, --chgrp <new_group>
		Change group of the file.
		This option cannot be combined with `--chown`.
		If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected.
	-p, --chmod <new_permissions>
		Change permissions of the file.
		Beware the `X` manipulation is supported but presence of any `x` bit on target file is checked only at the very beginning of manipulation, not during after every group of settings.
		I.e. definition `u=rwx,go=rX` applied to file with current mode `rw-r--r--` will end up with mode `rwxr--r--`, not `rwxr-xr-x` as could be expected.
		If the given file path is a symlink, the symlink target will be manipulated and the symlink itself will not be affected.
	-d, --rm
		Delete files.
		If the given file path is a symlink, the symlink itself will be deleted and the target file will not be affected.
		This option cannot be combined with other options.
	-m, --machine, --machine-readable
		Make output of `--name` and `--scp` machine readable by stripping out anything but clean path output string.
		Symlinks are followed in this mode, i.e. print path of the link target.
	-v, --verbose
		Verbose mode. In this mode not only errors and warnings (which is default behaviour) are shown but also information messages are listed.
		Use of this option overrides `--silent` mode.
	-s, --silent
		Silent mode. In this mode no information messages (including errors and warnings) are shown. Success/failure of processing is indicated by return value of the tool.
		Use of this option overrides `--verbose` mode.
	-h, --help
		Print the usage info and exit.
```

## Dependencies & Implementation Notes

### CPAN Modules

The tools uses bunch of CPAN modules implementing useful functionality. To run
the tool install the needed modules using your distribution software management
tool or install up-to-date versions directly from CPAN:

`cpan Cwd Encode::Locale Encode File::chmod FindBin Getopt::Long IO::Handle
Path::Tiny Scalar::Util Stat::lsMode Sys::Hostname Try::Tiny`

See
  * http://www.cpan.org/

### Error Handling

The module uses `Try::Tiny` module to handle exceptions/errors.

See
 * https://metacpan.org/pod/Try::Tiny

### Command Line Parsing

Command line arguments are processed using `Getopt::Long` module. GNU getopt
and advanced features such as options bundling and auto completion can be used.

See
 * https://metacpan.org/pod/Getopt::Long



<!--
  vim:textwidth=80:expandtab:tabstop=4:shiftwidth=4:fileencodings=utf8:spelllang=en
-->
