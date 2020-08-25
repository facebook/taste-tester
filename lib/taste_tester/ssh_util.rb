# Copyright 2020-present Facebook
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module TasteTester
  class SSH
    module Util
      def ssh_base_cmd
        jumps = TasteTester::Config.jumps ?
          "-J #{TasteTester::Config.jumps}" : ''
        "#{TasteTester::Config.ssh_command} #{jumps} -T -o BatchMode=yes " +
          '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ' +
          "-o ConnectTimeout=#{TasteTester::Config.ssh_connect_timeout} " +
          "#{TasteTester::Config.user}@#{@host} "
      end

      def error!
        error = <<~ERRORMESSAGE
  SSH returned error while connecting to #{TasteTester::Config.user}@#{@host}
  The host might be broken or your SSH access is not working properly
  Try doing

      #{ssh_base_cmd} -v

  to see if ssh connection is good.
  If ssh works, add '-v' key to taste-tester to see the list of commands it's
  trying to execute, and try to run them manually on destination host
        ERRORMESSAGE
        logger.error(error)
        fail TasteTester::Exceptions::SshError
      end

      def build_ssh_cmd(ssh, command_list)
        if TasteTester::Config.windows_target
          # Powershell has no `&&`. So originally we looked into joining the
          # various commands with `; if ($LASTEXITCODE -ne 0) { exit 42 }; `
          # except that it turns out lots of Powershell commands don't set
          # $LASTEXITCODE and so that crashes a lot.
          #
          # There is an `-and`, but it only works if you group things together
          # with `()`, but that loses any output.
          #
          # Technically in the latest preview of Powershell 7, `&&` exists, but
          # we cannot rely on this.
          #
          # So here we are. Thanks Windows Team.
          #
          # Anyway, what we *really* care about is that we exit if we_testing()
          # errors out, and on Windows, we can do that straight from the
          # powershell we generate there (we're not forking off awk), so the
          # `&&` isn't as critical. It's still a bummer that we continue on
          # if one of the commands fails, but... Well, it's Windows,
          # whatchyagonnado?

          cmds = command_list.join(' ; ')
        else
          cmds = command_list.join(' && ')
        end
        cmd = ssh
        cc = Base64.encode64(cmds).delete("\n")
        if TasteTester::Config.windows_target

          # This is pretty horrible, but because there's no way I can find to
          # take base64 as stdin and output text, we end up having to do use
          # these PS functions. But they're going to pass through *both* bash
          # *and* powershell, so in order to preserve the quotes, it gets
          # pretty ugly.
          #
          # The tldr here is that in shell you can't escape quotes you're
          # using to quote something. So if you use single quotes, there's no
          # way to escape a single quote inside, and same with double-quotes.
          # As such we switch between quote-styles as necessary. As long as the
          # strings are back-to-back, shell handles this well. To make this
          # clear, imagine you want to echo this:
          #    '"'"
          # Exactly like that. You would quote the first single quotes in double
          # quotes: "'"
          # Then the double quotes in single quotes: '"'
          # Now repeat twice and you get: echo "'"'"'"'"'"'
          # And that works reliably.
          #
          # We're doing the same thing here. What we want on the other side of
          # the ssh is:
          #  [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String('...'))
          #
          # But for this to work right the command we pass to SSH has to be in
          # single quotes too. For simplicity lets call those two functions
          # above GetString() and Base64(). So we'll start with:
          #    ssh host 'GetString(Base64('
          # We've closed that string, now we add the single quote we want there,
          # as well as the stuff inside of those double quotes, so we'll add:
          #    '#{cc}'))
          # but that must be in double quotes since we're using single quotes.
          # Put that together:
          #    ssh host 'GetString(Base64('"'#{cc}'))"
          #             ^-----------------^^---------^
          #              string 1           string2
          # No we're doing with needing single quotes inside of our string, go
          # back to using single-quotes so no variables get interpolated. We now
          # add: ' | powershell.exe -c -; exit $LASTEXITCODE'
          #   ssh host 'GetString(Base64('"'#{cc}'))"' | powershell.exe ...'
          #            ^-----------------^^---------^^---------------------^
          #
          # More than you ever wanted to know about shell. You're welcome.
          #
          # But now we have to put it inside of a ruby string, :)

          # just for readability, put these crazy function names inside of
          # variables
          fun1 = '[Text.Encoding]::Utf8.GetString'
          fun2 = '[Convert]::FromBase64String'
          cmd += "'#{fun1}(#{fun2}('\"'#{cc}'))\"' | "
          #       ^----------------^ ^----------^^---
          #        single-q           double-q    single-q
          #        string 1           string2     string3
          cmd += 'powershell.exe -c -; exit $LASTEXITCODE\''
          #       ----------------------------------------^
          #       continued string3
        else
          cmd += "\"echo '#{cc}' | base64 --decode"
          if TasteTester::Config.user != 'root'
            cmd += ' | sudo bash -x"'
          else
            cmd += ' | bash -x"'
          end
        end
        cmd
      end
    end
  end
end
