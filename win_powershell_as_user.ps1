#!powershell
# This file is part of Ansible
#
# Copyright 2015, Corwin Brown <corwin@corwinbrown.com>
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.
#
# WANT_JSON
# POWERSHELL_COMMON

$params = Parse-Args $args

$scriptPath =  Get-AnsibleParam -obj $params -name 'ScriptPath' -failifempty $true
$arguments = Get-AnsibleParam -obj $params -name "Arguments"
$user = Get-AnsibleParam -obj $params -name "User"
$password = Get-AnsibleParam -obj $params -name "User" -no_log $true
[System.Collections.ArrayList]$stdout = @()
$result = New-Object psobject -Property @{
    changed = $false
    win_powershell_script_as_user = @{
        scriptpath = $scriptPath
        arguments = $arguments
        user = $user
	    stdout = "$stdout"
        stdout_lines = $stdout
        logfile = ""
    }
}

$taskName = "$((Get-Date).ticks)"
$logFile = "$PSScriptRoot\$taskName.log"
try{
    New-Item -ItemType file -Path $logFile -Force
    $result.changed = $true
}
catch{
    $result.changed = $true
    Fail-Json $result "Failed to create log file"
}
try{
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -NonInteractive -c $scriptPath $arguments >> $logFile"
    Register-ScheduledTask -Action $action -TaskName $taskName -RunLevel Highest -Force
    Start-ScheduledTask -TaskName $taskName
}
catch{
    Fail-Json $result $_.Exception.Message
}
try{
    while((Get-ScheduledTask -TaskName $taskName).state -ne 'Ready'){
        sleep 5
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
catch{
    Fail-Json $result $_.Exception.Message
}
try{
    get-content $logFile | Where-Object{$_ -ne ""} | %{$stdout.add($_)}
    $result.win_powershell_script_as_user.stdout_lines = $stdout
    $result.win_powershell_script_as_user.stdout = "$stdout"
    #copy $logfile c:\users\administrator\ansible_testing\test.log
    Remove-Item $logFile
    if($stdout.count -eq 0){
        $result.changed = $false
    }
}
catch{
    Fail-Json $result "$_.Exception.Message"
}
Exit-Json $result