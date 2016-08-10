################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

# Multiple consumers with a work queue that's created before spawning pool

$NumberOfThreads = Get-WmiObject Win32_Processor |
    Measure-Object -Property NumberOfLogicalProcessors -Sum |
    select -ExpandProperty Sum

$WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]

1..10000 | % { $WorkQueue.Enqueue("Item number $_") }

$Parameters = @{
    WorkQueue = $WorkQueue
}

$ThreadScriptBlock = {
    Param($ThreadId, $WorkQueue)
    $item = ""
    while ($WorkQueue.TryDequeue([ref]$item)) {
        Write-Output "$ThreadId -> $item"
    }
}

$Thread= New-Thread -ScriptBlock $ThreadScriptBlock -Number $NumberOfThreads

$result = Invoke-ThreadPool -Thread $Thread -Parameters $Parameters -Verbose
$result | % { [regex]::Matches($_, ".-\d{2}").Groups[0].Value } | group

################################################################################

# Producer - Consumer pattern with a work queue and result bag

$NumCPUs = Get-WmiObject Win32_Processor |
    Measure-Object -Property NumberOfLogicalProcessors -Sum |
    select -ExpandProperty Sum

$Results = New-Object System.Collections.Concurrent.ConcurrentBag[object]

$Parameters = @{
    WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Settings  = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[object,Object]'
    ResultSet = $Results
}
$Parameters.Settings['IsDone'] = $false
$Parameters.Settings['Produce'] = 10000
$Parameters.Settings['SleepTime'] = 10

$ProducerThread = New-Thread -ScriptBlock {
    Param($ThreadId, $WorkQueue, $Settings)
    1..$Settings['Produce'] | % {
        $WorkQueue.Enqueue("item number $_")
    }
    $Settings['IsDone'] = $true
} -Type Producer -Weight 100

$ConsumerThread = New-Thread {
    Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
    $item = New-Object psobject
    while (!$Settings['IsDone'] -or $WorkQueue.Count -gt 0) {
        if ($WorkQueue.TryDequeue([ref]$item)) {
            #process item
            $ResultSet.Add("Thread $ThreadId has processed '$item'")
        } else {
            Start-Sleep -Milliseconds $Settings['SleepTime']
        }
    }
} -Type Consumer -Number ($NumCPUs - 1)

Invoke-ThreadPool -Thread $ProducerThread, $ConsumerThread -Parameters $Parameters -Verbose
$Results | % { [regex]::Matches($_, "(c|p)-\d{2}").Groups[0].Value } | group

################################################################################

# Producer - Worker - Writer

$NumCPUs = Get-WmiObject Win32_Processor |
    Measure-Object -Property NumberOfLogicalProcessors -Sum |
    select -ExpandProperty Sum

$Results = New-Object System.Collections.Concurrent.ConcurrentBag[object]

$Parameters = @{
    WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Settings  = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[object,Object]'
    ResultSet = $Results
}
$Parameters.Settings['IsDone'] = $false
$Parameters.Settings['Produce'] = 10000
$Parameters.Settings['SleepTime'] = 10

$ProducerThread = New-Thread -ScriptBlock {
    Param($ThreadId, $WorkQueue, $Settings)
    1..$Settings['Produce'] | % {
        $WorkQueue.Enqueue("item number $_")
    }
    $Settings['IsDone'] = $true
} -Type Producer -Weight 100

$WorkerThread = New-Thread {
    Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
    $item = ""
    while (!$Settings['IsDone'] -or $WorkQueue.Count -gt 0) {
        if ($WorkQueue.TryDequeue([ref]$item)) {
            #process item
            $ResultSet.Add("Thread $ThreadId has processed '$item'")
        } else {
            Start-Sleep -Milliseconds $Settings['SleepTime']
        }
    }
} -Type Worker -Number ($NumCPUs - 2) -Weight 10

$ProgressThread = New-Thread {
    Param($ThreadId, $Settings, $ResultSet)
    $item = ""
    while (!$Settings['IsDone'] -or $ResultSet.Count -gt 0) {
        if ($ResultSet.TryTake([ref]$item)) {
            Write-Host $item
        } else {
            Start-Sleep -Milliseconds $Settings['SleepTime']
        }
    }
} -Type Writer

Invoke-ThreadPool -Thread $ProducerThread, $ConsumerThread, $ProgressThread `
                  -Parameters $Parameters -Verbose

################################################################################
