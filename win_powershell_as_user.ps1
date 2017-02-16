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

#######################################################################
#                                                                     #
# Fail-Json seems to output changed = $false regardless of if we have #
# set this explicitly or not. Adding bool third parameter to          #
# specify changed state. The original function is located at          #
# ansible/lib/ansible/module_utils/powershell.ps1. I may send a PR    #
# at some point                                                       #
#                                                                     #
#######################################################################

# Helper function to add the "msg" property, "failed" property and "changed" property, convert the
# powershell object to JSON and echo it, exiting the script
# Example: Fail-Json $result "This is the failure message" $false
Function Fail-Json{
    param(
        $obj,
        [string]$message = "",
        [bool]$changed = $false
    )
    # If the only arg was a string, create a new
    # psobject and use the arg as the failure message
    If ($message -eq "" -and $changed -eq $false -and $obj.GetType().Name -eq "String")
    {
        $message = $obj
        $obj = New-Object psobject
    }
    # If the only arg was a boolean, create a new
    # psobject and use the arg as the changed state
    ElseIf ($message -eq "" -and $changed -eq $false -and $obj.GetType().Name -eq "Boolean")
    {
        $changed = $obj
        $obj = New-Object psobject
    }
    # If the first arg is undefined or not an object, make it an object
    ElseIf (-not $obj -or -not $obj.GetType -or $obj.GetType().Name -ne "PSCustomObject")
    {
        $obj = New-Object psobject
    }
    Set-Attr $obj "changed" $changed
    Set-Attr $obj "msg" $message
    Set-Attr $obj "failed" $true
    echo $obj | ConvertTo-Json -Compress -Depth 99
    Exit 1
}

$params = Parse-Args $args

$scriptPath =  Get-AnsibleParam -obj $params -name 'ScriptPath' -failifempty $true
$arguments = Get-AnsibleParam -obj $params -name "Arguments"
$user = Get-AnsibleParam -obj $params -name "User"
$password = Get-AnsibleParam -obj $params -name "User" -no_log $true
[System.Collections.ArrayList]$stdout = @()
[PSCustomObject]$result = @{
    changed = $false
    win_powershell_script_as_user = @{
        scriptpath = $scriptPath
        arguments = $arguments
        user = $user
	    stdout = "$stdout"
        stdout_lines = $stdout
        logfile = ""
    }
};

$taskName = "$((Get-Date).ticks)"
$logFile = "$PSScriptRoot\$taskName.log"
try{
    New-Item -ItemType file -Path $logFile -Force
    $result.changed = $true
}
catch{
    Fail-Json $result "Failed to create log file" $true
}
try{
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -NonInteractive -c $scriptPath $arguments >> $logFile"
    Register-ScheduledTask -Action $action -TaskName $taskName -RunLevel Highest -Force
    Start-ScheduledTask -TaskName $taskName
}
catch{
    Fail-Json $result $_.Exception.Message $true
}
try{
    while((Get-ScheduledTask -TaskName $taskName).state -ne 'Ready'){
        sleep 5
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
catch{
    Fail-Json $result $_.Exception.Message $true
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
    Fail-Json $result "$_.Exception.Message" $true
}
Exit-Json $result
