################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

. .\setup-test.ps1

Describe "`$PsThreading" {

    It "WorkerOnly pattern works" {
        $produce = 10000
        $threads = $PsThreading.Utility.LogicalCpus
        $params  = $PsThreading.Parameter.WorkerOnly
        1..$produce | % { $params.WorkQueue.Enqueue("item number $_") }
        $thread = New-Thread -ScriptBlock $PsThreading.Thread.Worker `
                             -Number $threads
        $results = Invoke-ThreadPool -Thread $thread -Parameters $params
        $groups = $results | % { [regex]::Matches($_,"w-\d{2}").Value } | group
        $results.Count -eq $produce -and $groups.Count -eq $threads | Should Be $true
    }

}
