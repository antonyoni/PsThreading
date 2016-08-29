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

Describe "Patterns" {

    It "Worker only" {
        $produce = 10000
        $threads = $PsThreading.Utility.LogicalCpus
        $params  = $PsThreading.Parameter.WorkerOnly
        1..$produce | % { $params.WorkQueue.Enqueue("item number $_") }
        $thread = New-Thread -ScriptBlock $PsThreading.Thread.Worker `
                             -Number $threads
        $results = Invoke-ThreadPool -Thread $thread -Parameters $params
        $groups = $results | % { [regex]::Matches($_, "w-\d{2}").Value } | group
        $results.Count -eq $produce -and $groups.Count -eq $threads | Should Be $true
    }

    It "Producer - Consumer" {
        $produce = 9743
        $threads = $PsThreading.Utility.LogicalCpus
        $params  = $PsThreading.Parameter.ProducerConsumer
        $params.Settings['NumberToProduce'] = $produce
        $results = $params.ResultSet

        $producer = New-Thread -ScriptBlock $PsThreading.Thread.Producer `
                               -Type "Producer" `
                               -Weight 100

        $consumer = New-Thread -ScriptBlock $PsThreading.Thread.Consumer `
                               -Type "Consumer" `
                               -Number ($threads - 1)

        Invoke-ThreadPool -Thread $producer, $consumer -Parameters $params

        $groups = $results | % { [regex]::Matches($_, "\w-\d{2}").Value } | group

        $results.Count -eq $produce -and $groups.Count -eq ($threads - 1) | Should Be $true
    }

    It "Producer - Worker - Writer" {
        $produce = 12784
        $outPath = Join-Path $TestDrive writer-out-txt
        $threads = $PsThreading.Utility.LogicalCpus
        $params  = $PsThreading.Parameter.ProducerWorkerWriter
        $params.Settings['NumberToProduce'] = $produce
        $params.Settings['OutputPath'] = $outPath
        $params.Settings['WorkersRunning'] = $threads - 2

        $producer = New-Thread -ScriptBlock $PsThreading.Thread.Producer `
                               -Type "Producer" `
                               -Weight 100

        $workerWithFlag = "$($PsThreading.Thread.Consumer.ToString())" +
                          "do { 
                              `$val = `$Settings['WorkersRunning']
                          } while (!`$Settings.TryUpdate('WorkersRunning', `$val - 1, `$val))"

        $workerScript = [scriptblock]::Create($workerWithFlag)

        $worker = New-Thread -ScriptBlock $workerScript `
                             -Type "Worker" `
                             -Number $params.Settings['WorkersRunning'] `
                             -Weight 10

        $writer = New-Thread -ScriptBlock $PsThreading.Thread.Writer `
                             -Type "Writer"

        Invoke-ThreadPool -Thread $producer, $worker, $writer -Parameters $params

        $results = Get-Content $outPath
        $groups = $results | % { [regex]::Matches($_, "\w-\d{2}").Value } | group

        # writer adds two additional lines - so count is produce + 2
        $results.Count -eq ($produce + 2) -and $groups.Count -eq ($threads - 2) | Should Be $true
    }

}
