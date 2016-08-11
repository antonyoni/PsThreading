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
    DataStructure = [pscustomobject]@{
        Dictionary = [System.Collections.Concurrent.ConcurrentDictionary`2[object,object]]
        Queue      = [System.Collections.Concurrent.ConcurrentQueue[object]]
        Stack      = [System.Collections.Concurrent.ConcurrentStack[object]]
        Bag        = [System.Collections.Concurrent.ConcurrentBag[object]]
    }
    Pattern = [pscustomobject]@{
        WorkerOnly           = $null
        ProducerConsumer     = $null
        ProducerWorkerWriter = $null
    }
    Thread  = [pscustomobject]@{
        Consumer = {
            Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
            $item = New-Object psobject
            while (!$Settings['IsDone'] -or $WorkQueue.Count -gt 0) {
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
            1..$Settings['Produce'] | % {
                $WorkQueue.Enqueue("item number $_")
            }
            $Settings['IsDone'] = $true
        }
        Worker = {
            Param($ThreadId, $WorkQueue)
            $item = ""
            while ($WorkQueue.TryDequeue([ref]$item)) {
                # process item here
                Write-Output "$ThreadId -> $item"
            }
        }
        Writer = {
            Param($ThreadId, $Settings, $ResultSet)
            $item = ""
            while (!$Settings['IsDone'] -or $ResultSet.Count -gt 0) {
                if ($ResultSet.TryTake([ref]$item)) {
                    Write-Host $item
                } else {
                    Start-Sleep -Milliseconds $Settings['SleepTime']
                }
            }
        }
    }
    Utility = [pscustomobject]@{}
}

$numCores = {
    return Get-WmiObject Win32_Processor |
        Measure-Object -Property NumberofCores -Sum |
        select -ExpandProperty Sum
}

$numCPUs = {
    return Get-WmiObject Win32_Processor |
        Measure-Object -Property NumberOfLogicalProcessors -Sum |
        select -ExpandProperty Sum
}

Add-Member -InputObject $PsThreading.Utility `
           -MemberType ScriptProperty `
           -Name CpuCores `
           -Value $numCores

Add-Member -InputObject $PsThreading.Utility `
           -MemberType ScriptProperty `
           -Name LogicalCpus `
           -Value $numCPUs

################################################################################

$PsThreading.Pattern.WorkerOnly = [pscustomobject]@{
    Thread = (New-Thread -ScriptBlock $PsThreading.Thread.Worker `
                         -Number $PsThreading.Utility.LogicalCpus)
    Parameters = @{
        WorkQueue = & {
             $q = New-Object $PsThreading.DataStructure.Queue
             1..1000 | % { $q.Enqueue("item $_") }
             return $q
        }
    }
    MaxThreads = $PsThreading.Utility.LogicalCpus
}

################################################################################

$PsThreading.Pattern.ProducerConsumer = [pscustomobject]@{
    Thread = @(
        New-Thread -ScriptBlock $PsThreading.Thread.Producer `
                   -Type "Producer" `
                   -Weight 100
        New-Thread -ScriptBlock $PsThreading.Thread.Consumer `
                   -Type "Consumer" `
                   -Number ($PsThreading.Utility.LogicalCpus - 1)
    )
    Parameters = @{
        Settings  = & {
            $s= New-Object $PsThreading.DataStructure.Dictionary
            $s['IsDone']    = $false
            $s['Produce']   = 10000
            $s['SleepTime'] = 10
            return $s
        }
        WorkQueue = New-Object $PsThreading.DataStructure.Queue
        ResultSet = New-Object $PsThreading.DataStructure.Bag
    }
    MaxThreads = $PsThreading.Utility.LogicalCpus
}

################################################################################

$PsThreading.Pattern.ProducerWorkerWriter = [pscustomobject]@{
    Thread = @(
        New-Thread -ScriptBlock $PsThreading.Thread.Producer `
                   -Type "Producer" `
                   -Weight 100
        New-Thread -ScriptBlock $PsThreading.Thread.Consumer `
                   -Type "Worker" `
                   -Number ($PsThreading.Utility.LogicalCpus - 1) `
                   -Weight 10
        New-Thread -ScriptBlock $PsThreading.Thread.Writer `
                   -Type "Writer"
    )
    Parameters = @{
        Settings  = & {
            $s= New-Object $PsThreading.DataStructure.Dictionary
            $s['IsDone']    = $false
            $s['Produce']   = 10000
            $s['SleepTime'] = 10
            return $s
        }
        WorkQueue = New-Object $PsThreading.DataStructure.Queue
        ResultSet = New-Object $PsThreading.DataStructure.Bag
    }
    MaxThreads = $PsThreading.Utility.LogicalCpus
}

################################################################################

Export-ModuleMember -Variable PsThreading
