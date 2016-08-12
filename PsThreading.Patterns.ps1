################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

$PsThreading = [pscustomobject]@{
    Parameter = [pscustomobject]@{}
    Thread = [pscustomobject]@{
        Consumer = {
            Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
            $item = ""
            while (!$Settings['ProducerIsDone'] -or $WorkQueue.Count -gt 0) {
                if ($WorkQueue.TryDequeue([ref]$item)) {
                    #process item
                    $ResultSet.Add("Thread $ThreadId has processed '$item'")
                } else {
                    Start-Sleep -Milliseconds 10
                }
            }
        }
        Producer = {
            Param($ThreadId, $WorkQueue, $Settings)
            1..$Settings['NumberToProduce'] | % {
                $WorkQueue.Enqueue("item number $_")
            }
            $Settings['ProducerIsDone'] = $true
        }
        Worker = {
            Param($ThreadId, $WorkQueue)
            $item = ""
            while ($WorkQueue.TryDequeue([ref]$item)) {
                # process item
                Write-Output "$ThreadId -> $item"
            }
        }
        Writer = {
            Param($ThreadId, $Settings, $ResultSet)
            $item = ""
            $sleepTime = $Settings['SleepTime']
            $stream = [System.IO.File]::OpenWrite($Settings['OutputPath'])
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.WriteLine("$(Get-Date -Format "yyyyMMddHHmmss") -> Writer starting")
            while ($Settings['WorkersRunning'] -gt 0 -or $ResultSet.Count -gt 0) {
                if ($ResultSet.TryTake([ref]$item)) {
                    $writer.WriteLine($item)
                } else {
                    Start-Sleep -Milliseconds $sleepTime
                }
            }
            $writer.WriteLine("$(Get-Date -Format "yyyyMMddHHmmss") -> Writer id done.")
            $writer.Flush()
            $stream.Close()
        }
    }
    Utility = [pscustomobject]@{}
}

################################################################################

$workerOnly = {
    return @{
        WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    }
}

Add-Member -InputObject $PsThreading.Parameter `
           -MemberType ScriptProperty `
           -Name WorkerOnly `
           -Value $workerOnly

$producerConsumer = {
    $sets = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[string,object]'
    $sets['NumberToProduce'] = 10000
    $sets['ProducerIsDone']  = $false
    return @{
        ResultSet = New-Object System.Collections.Concurrent.ConcurrentBag[object]
        Settings  = $sets
        WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    }
}

Add-Member -InputObject $PsThreading.Parameter `
           -MemberType ScriptProperty `
           -Name ProducerConsumer `
           -Value $producerConsumer

$producerWorkerWriter = {
    $sets = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[string,object]'
    $sets['OutputPath']      = (Join-Path (Get-Location) out.txt)
    $sets['NumberToProduce'] = 10000
    $sets['SleepTime']       = 10
    $sets['ProducerIsDone']  = $false
    $sets['WorkersRunning']  = 0
    return @{
        ResultSet = New-Object System.Collections.Concurrent.ConcurrentBag[object]
        Settings  = $sets
        WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    }
}

Add-Member -InputObject $PsThreading.Parameter `
           -MemberType ScriptProperty `
           -Name ProducerWorkerWriter `
           -Value $producerWorkerWriter

################################################################################

$numCores = {
    return Get-WmiObject Win32_Processor |
        Measure-Object -Property NumberofCores -Sum |
        select -ExpandProperty Sum
}

Add-Member -InputObject $PsThreading.Utility `
           -MemberType ScriptProperty `
           -Name CpuCores `
           -Value $numCores

$numCPUs = {
    return Get-WmiObject Win32_Processor |
        Measure-Object -Property NumberOfLogicalProcessors -Sum |
        select -ExpandProperty Sum
}

Add-Member -InputObject $PsThreading.Utility `
           -MemberType ScriptProperty `
           -Name LogicalCpus `
           -Value $numCPUs

################################################################################

Export-ModuleMember -Variable PsThreading
