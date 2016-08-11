################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

Function New-Thread {
    <#
        .SYNOPSIS
        Function to scaffold a new thread to be used by Invoke-ThreadPool.

        .EXAMPLE
        New-Thread -ScriptBlock $ThreadScriptBlock -Number $NumberOfThreads

        .NOTES
        For usage examples see the PsThreading variable.
    #>

    [CmdletBinding()]
    [OutputType([PsObject])]
    Param(
        # Script block the thread will execute.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$ScriptBlock,

        # Thread type. Default is 'Worker'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [ValidateNotNullOrEmpty()]
        [string]$Type = 'Worker',

        # Number of threads to spawn.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=3)]
        [ValidateRange(1,10000)]
        [int]$Number = 1,

        # Threads with higher weight will start first. Default is 1.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=4)]
        [int]$Weight = 1,

        # Prefix for the thread id to aid debugging. Default is first letter of the thread type.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=5)]
        [string]$IdPrefix
    )

    End {

        if (!$IdPrefix) {
            $IdPrefix = $Type.Substring(0,1).ToLower()
        }

        $t = [pscustomobject]@{
            Id          = "$IdPrefix-{0:D2}"
            Type        = $Type
            Weight      = $Weight
            Number      = $Number
            ScriptBlock = $ScriptBlock
            Thread      = $null
            Handle      = $null
        }

        $t.PsObject.TypeNames.Insert(0, "PsThreading.Thread")

        Write-Output $t
    }

}

Export-ModuleMember -Function 'New-Thread'
