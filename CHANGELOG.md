# Change Log

All notable changes to this project will be documented in this file.


## [Unreleased]

### Added
- Name mode printing real final path of files.
  * If the last component of the path is a symlink the real final path of the
    target is also shown.
- Verbose/silent mode.
- Change log.

### Changed
- Default mode changed from cat mode to name mode.
- Processing information messages are not shown unless in verbose mode.

### Fixed
- Decoding of special characters in file names in 
  `real_path_dereference_symlinks_but_last()`.


## v1.0.0 – 2016-01-16
- The first release.

[Unreleased]: https://github.com/michal-ruzicka/chfile/compare/v1.0.0...develop



<!--
  vim:textwidth=80:expandtab:tabstop=4:shiftwidth=4:fileencodings=utf8:spelllang=en
-->
