# Taste Tester

![Continuous Integration](https://github.com/facebook/taste-tester/workflows/Continuous%20Integration/badge.svg?event=push)

## Intro
Ohai!

Welcome to Taste Tester, software to manage a chef-zero instance and use it to
test changes on production servers.

At its core, Taste Tester starts up a chef-zero server on localhost, uploads a
repository to it, ssh's to a remote server and points its configs to your new
chef-zero instance.

Further, it keeps track of where in git you were when that happened so future
uploads will do the right thing, even as you switch branches.

Taste Tester can be controlled via a variety of config-file options, and can be
further customized by writing a plugin.

## Synopsis

Typical usage is:

```text
vi cookbooks/...             # Make your changes and commit locally
taste-tester impact          # Check where your changes are used
taste-tester test -s [host]  # Put host in Taste Tester mode
ssh root@[host]              # Log in to host
  # Run chef and watch it break
vi cookbooks/...             # Fix your cookbooks
taste-tester upload          # Upload the diff
ssh root@[host]
  # Run chef and watch it succeed
<Verify your changes were actually applied as intended!>
taste-tester untest [host]   # Put host back in production
                             #   (optional - will revert itself after 1 hour)
```

See the help for further information.

## Prerequisites

* Taste Tester assumes that `/etc/chef/client.rb` and `/etc/chef/client.pem` on your
servers is a symlink and that your real config is `/etc/chef/client-prod.rb` and
`/etc/chef/client-prod.pem`, respectively.

* Taste Tester assumes that it's generally safe to "go back" to production. I.e.
We set things up so you can set a cronjob to un-taste-test a server after the
desired amount of time, which means it must be (relatively) safe to revert
back.

* Taste Tester assumes you use a setup similar to grocery-delivery in
production. Specifically that you don't use versions or environments.

* Taste Tester assumes you have password-less SSH authentication to the hosts
you want to test on, i.e. SSH public/private keys, SSH certificates, Kerberos

## Dependencies

* Mixlib::Config
* Colorize
* BetweenMeals
* Minitar
* Chef

## Automatic Untesting

Taste Tester touches `/etc/chef/test_timestamp` on the remote server as far into
the future as the user wants to test (default is 1h). You should have a cronjob
to check the timestamp of this file, and if it is old, remove it and put the
symlinks for `/etc/chef/client.rb` back to where they belong.

A small shell script to do this is included called `taste-untester`. We
recommend running this at least every 15 minutes.

If you let Taste Tester setup reverse-SSH tunnels, make sure your untester
is also killing the ssh tunnel whose PID is in `/etc/chef/test_timestamp`
(taste-untester will do this for you).

## Config file

The default config file is `/etc/taste-tester-config.rb` but you may use -c to
specify another. The config file works the same as `client.rb` does for Chef -
there are a series of keywords that take an argument and anything else is just
standard Ruby.

All command-line options are available in the config file:
* debug (bool, default: `false`)
* timestamp (bool, default: `false`)
* config_file (string, default: `/etc/taste-tester-config.rb`)
* plugin_path (string, no default)
* repo (string, default: `#{ENV['HOME']}/ops`)
* testing_time (int, default: `3600`)
* chef_client_command (string, default: `chef-client`)
* json (bool, default: `false`)
* skip_repo_checks (bool, default: `false`)
* skip_pre_upload_hook (bool, default: `false`)
* skip_post_upload_hook (bool, default: `false`)
* skip_pre_test_hook (bool, default: `false`)
* skip_post_test_hook (bool, default: `false`)
* skip_repo_checks_hook (bool, default: `false`)

The following options are also available:
* base_dir - The directory in the repo under which to find chef configs.
  Default: `chef`
* cookbook_dirs - An array of cookbook directories relative to base_dir.
  Default: `['cookbooks']`
* role_dir - A directory of roles, relative to base_dir. Default: `roles`
* databag_dir - A directory of databags, relative to base_dir.
  Default: `databags`
* ref_file - The file to store the last git revision we uploaded in. Default:
  `#{ENV['HOME']}/.chef/taste-tester-ref.txt`
* checksum_dir - The checksum directory to put in knife.conf for users. Default:
  `#{ENV['HOME']}/.chef/checksums`
* bundle - use a single tar.gz file for transporting cookbooks, roles and
  databags to clients. Experimental. Value is tri-state:
  * `false` - server uses knife upload, client uses `chef_server`
  * `:compatible` - make server support both methods, client uses tar.gz
  * `true` - server only creates tar.gz, client uses tar.gz
  Default: false
* impact - analyze local changes to determine which hosts/roles to test.
  Default: false
* ssh_cmd_gen_template - Provide a command to run, whose stdout will be a
  vanilla ssh command Taste Tester will invoke to access test nodes.
  The command should be a template and will be passed the
  following variables:
  * `jumps` - any jumphost arguments supplied via -J option
  * `host` - the host to SSH to
  * `user` - the user to SSH as
  For example:
  `ssh_gen %{jumps} --user %{user} %{host}`
  Default: nil

## Plugin

The plugin should be a ruby file which defines several class methods. It is
class_eval()d into a Hooks class.

The following functions can optionally be defined:

* self.pre_upload(dryrun, repo, last_ref, cur_ref)

Stuff to do before we upload anything to chef-zero. `Repo` is a BetweenMeals::Repo
object. `last_ref` is the last git ref we uploaded and `cur_ref` is the git ref
the repo is currently at,

* self.post_upload(dryrun, repo, last_ref, cur_ref)

Stuff to do after we upload to chef-zero.

* self.pre_test(dryrun, repo, hosts)

Stuff to do before we put machines in test mode. `hosts` is an array of
hostnames.

* self.test_remote_cmds(dryrun, hostname)

Additional commands to run on the remote host when putting it in test mode.
Should return an array of strings. `hostname` is the hostname.

* self.test_remote_client_rb_extra_code(hostname)

Should return a string of additional code to include in the remote `client.rb`.
Example uses: defining json_attribs

* self.post_test(dryrun, repo, hosts)

Stuff to do after putting all hosts in test mode.

* self.repo_checks(dryrun, repo)

Additional checks you want to do on the repo as sanity checks.

* self.find_impact(changes)

Custom implementation of impact analysis. Uses `knife deps` by default. May
return any data structure, provided one or both of `self.post_impact` or
`self.print_impact` are defined.

* self.post_impact(basic_impact)

Stuff to do after preliminary impact analysis. May be used to extend the
information generated by `self.find_impact`, reformat the data structure, etc.

* self.print_impact(final_impact)

Custom output of calculated impact, useful if defining either of the other
impact hooks. Must return a truthy value to prevent the default output from
printing.

* self.post_error(dryrun, exception, mode, hostname)

A hook which will be called just before taste-tester throws an exception/exits.
Passes down the `exception` object and the `mode` taste-tester was invoked with
for further analysis and doing any additional logging, output, or cleanup.

## Plugin example

This is an example `/etc/taste-tester-plugin.rb` to add a user-defined string
to `client-taste-tester.rb` on the remote system:

```
Hooks.class_eval do
  def self.test_remote_client_rb_extra_code(_hostname)
    %(
      # This comment gets added to client-taste-tester.rb
      # This one too.
      )
  end
end
```

Be sure to pass this plugin file with `-p` on the command line or set it as
`plugin_path` in your `taste-tester-config.rb` file.

## License

See the `LICENSE` file.
