################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

################################################################################
# Multiple consumers with a work queue that's created before spawning pool

$NumberOfThreads = Get-WmiObject Win32_Processor `
    | Measure-Object -Property NumberOfLogicalProcessors -Sum `
    | select -ExpandProperty Sum

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

$params = @{
    WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
    Settings  = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[object,Object]'
    ResultSet = New-Object System.Collections.Concurrent.ConcurrentBag[object]
}
$params.Settings['IsDone'] = $false

$prod = New-Thread -ScriptBlock {
    Param($ThreadId, $WorkQueue, $Settings)
    #Write-Host "$ThreadId - Starting"
    1..10000 | % {
        $WorkQueue.Enqueue("Producer says: $_")
    }
    $Settings['IsDone'] = $true
    #Write-Host "$ThreadId - Done"
} -Type Producer -Weight 100

$cons = New-Thread {
    Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
    #Write-Host "$ThreadId - Starting"
    $item = New-Object psobject
    while (!$Settings['IsDone'] -or $WorkQueue.Count -gt 0) {
        if ($WorkQueue.TryDequeue([ref]$item)) {
            #process item
            $ResultSet.Add("Thread $ThreadId has processed '$item'")
        } else {
            Start-Sleep -Milliseconds 100
        }
    }

    #Write-Host "$ThreadId - Done"
} -Type Consumer -Number 4

$results = Invoke-ThreadPool $prod, $cons $params -Verbose
$results.ResultSet | % { [regex]::Matches($_, "(c|p)-\d{2}").Groups[0].Value } | group

################################################################################