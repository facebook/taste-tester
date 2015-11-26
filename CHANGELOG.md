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

asdfasdfasdf
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
