# Change Log

All notable changes to this project will be documented in this file.


## [v1.1.0] – 2016-01-17

### Added
- Name mode printing real final path of files.
  * If the last component of the path is a symlink the real final path of the
    target is also shown.
- scp/rsync name mode.
- Verbose/silent mode.
- Change log.

### Changed
- Default mode changed from cat mode to name mode.
- Processing information messages are not shown unless in verbose mode.

### Fixed
- Return value if number of errors during process MOD 253 == 0.
- Changing permission on dangling symlink will end with error.
  * It is consistant with the commitment to change permission of the link target
    that really does not exist in this case.
- Decoding of special characters in file names in
  `real_path_dereference_symlinks_but_last()`.


## v1.0.0 – 2016-01-16
- The first release.


[v1.1.0]: https://github.com/michal-ruzicka/chfile/compare/v1.0.0...v1.1.0



<!--
  vim:textwidth=80:expandtab:tabstop=4:shiftwidth=4:fileencodings=utf8:spelllang=en
-->
