# Changelog

## 0.1.19
* Fix broken `test` mode on Windows
* Many powershell cleanups
* Actually break the tunnel loop when ready
* Handle removes of non-existent files in powershell better

## 0.0.18
* Fix broken `test` mode on Linux

## 0.0.17
* Add support for Windows target hosts. See help for `-w` and #144 for details
* Fix bug in `taste-untester` where ignored the config file
* Various lint and gemspec cleanups
* Improved symlink handling in cookbook and other dirs

## 0.0.16
* Fix the 'run' subcommand - no longer errors out and streams correclty
* Fix the 'debug' command given to users when SSH fails with Jump hosts
* Significant improvements to SSH tunnel handling
   * Tunnel will last as long as the test
   * Tunnel is torn down properly regardless of mode
   * Tunnel removal is syslogged if 'logger' is available
* License in gemspec if a proper shortname for Apache 2.0

## 0.0.15
* Add ProxyJump support
* Better error messages for connection errors
* Fix dependencies
* Remove broken `run` keyword
* Support `chefignore`
* `bundle` mode improvements
* handle non-v6 environments properly
* fix warnings that break `--json`

## 0.0.14
* Always use the desired knife config
* Rubocop compliance
* Add "partial failure" reporting
* Fix race conditions
* Better detection for existing chef-zero instances
* README corrections
* noop transport fixes
* add `--no-repo` options
* better error reporting when tunnel setup fails
* 'impact' mode
* 'profile' mode
* 'bundle' mode with tar transport
* Fix statefile key duplication
* Restore pwd

## 0.0.13
* Add a NoOp transport
* Replace `--locallink` with `--transport`
* Add option to support tracking symlinks
* Add option to allow specifying a knife config
* Use /bin/echo rather than built-in for better cross-platform support
* Add config file for taste-untester
* Fix tunnel support

## 0.0.12
* Check for chef-zero anywhere in PATH, not just two hard-coded directories
* Windows support
* Keep the same port on restart
* Handle client and server having different timezones
* Fix line number reporting when hooks crash

## 0.0.11
* Add support for JSON roles
* add --locallink option
* Fix support for 'port' on chef server
* Fix untesting
* Add option to pass hostname for local machine
* Add option to pass chef config file name
* chef-zero debug logging
* update syntax for ohai plugin path
* report SSH errors better

## 0.0.10
* Fix dependency

## 0.0.9
* Honor user-specified `chef_client_command` everywhere
* Various help message fixes
* Let user specify repo type
* Let user override SSH command
* Honor `--skip_repo_checks` more consistently
* Better error messages
* Support for `auto` repo type
* Fix bug in determining default role directory
* Fix bug in determining default databag directory

## 0.0.8
* Honor chef-zero path from config
* If user specifies a plugin path, error if it does not exist
* Support empty base directories
* Handle transitions from/to ssl/ssh
* Support HTTPS/SSL
* Support chef-zero logging
* Clear the ref number when restarting chef-zero
* Find our tunnel using group IDs
* Fix non-root case
* Handle upload failures better
* Error out if we hit problems rather than trying to carry on
* Various SSH changes to handle tunnels better
* Fixes for Chef 12
