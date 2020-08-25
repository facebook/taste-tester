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

[CmdletBinding()]
param(
  [switch]$dryrun
)

# keep these as *forward* slashes
$CONFLINK = 'C:/chef/client.rb'
$PRODCONF = 'C:/chef/client-prod.rb'
$CERTLINK = 'C:/chef/client.pem'
$PRODCERT = 'C:/chef/client-prod.pem'
$STAMPFILE = 'C:/chef/test_timestamp'
$MYSELF = $0

function log($msg) {
  Write-EventLog -LogName "Application" -Source "taste-tester" `
    -EventID 2 -EntryType Warning -Message $msg
}

function set_server_to_prod {
  if (Test-Path $STAMPFILE) {
    $content = Get-Content $STAMPFILE
    if ($content -ne $null) {
      kill $content -Force 2>$null
    }
  }
  rm -Force $CONFLINK
  New-Item -ItemType symboliclink -Force -Value $PRODCONF $CONFLINK
  if (Test-Path $STAMPFILE) {
    rm -Force $STAMPFILE
  }
  log "Reverted to production Chef."
}

function check_server {
  # this is the only way to check if something is a symlink, apparently
  if (-Not ((get-item $CONFLINK).Attributes.ToString() -match "ReparsePoint")) {
    Write-Verbose "$CONFLINK is not a link..."
    return
  }
  $current_config = (Get-Item $CONFLINK).target
  if ($current_config -eq $PRODCONF) {
    if (Test-Path $STAMPFILE) {
      rm -Force $STAMPFILE
    }
    return
  }

  $revert = $false
  if (-Not (Test-Path $STAMPFILE)) {
    $revert = $true
  } else {
    $now = [int][double]::Parse(
      $(Get-Date -date (Get-Date).ToUniversalTime()-uformat %s)
    )
    $stamp_time = Get-Date -Date `
      (Get-Item $STAMPFILE).LastWriteTime.ToUniversalTime() -UFormat %s
    Write-Verbose "$now vs $stamp_time"
    if ($now -gt $stamp_time) {
      $revert = $true
    }
  }
  if ($revert) {
    if ($dryrun) {
      echo "DRYRUN: Would return server to prod"
    } else {
      set_server_to_prod
    }
  }
}

check_server
