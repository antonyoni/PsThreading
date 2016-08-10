################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

Function Invoke-ProducerConsumerPool {
    <#
        .SYNOPSIS
        

        .EXAMPLE
        

        .NOTES
        The consumers are the first ones to start. The producers are 
        Basic script block should look like this:

    #>

    [CmdletBinding()]
    Param(
        # Script block to execute in each producer thread. These will usually be adding to the work queue.
        [Parameter(Mandatory=$True,
                   Position=1)]
        [scriptblock]$Producer,

        # Script block to execute in each consumer thread. These will usually be removing from the work queue, and adding to the result set.
        [Parameter(Mandatory=$True,
                   Position=2)]
        [scriptblock]$Consumer,

        # Set of arguments to pass to both thread types. These will be available in the $Settings array.
        [Parameter(Mandatory=$False)]
        [hashtable]$AdditionalParameters,

        # Number of producer threads. Default is one.
        [Parameter(Mandatory=$False)]
        [int]$NumProducers = 1,

        # Number of consumer threads. Default is (Logical CPUs - $NumProducers).
        [Parameter(Mandatory=$False)]
        [int]$NumConsumers,

        # Garbage collector cleanup interval.
        [Parameter(Mandatory=$False)]
        [int]$CleanupInterval = 2,

        # Powershell modules to import into the RunspacePool.
        [Parameter(Mandatory=$False)]
        [String[]]$ImportModules,

        # Paths to modules to be imported into the RunspacePool.
        [Parameter(Mandatory=$False)]
        [String[]]$ImportModulesPath
    )

    Begin {
        if (!$NumConsumers) {
            $workers = Get-WmiObject Win32_Processor `
                | Measure-Object -Property NumberOfLogicalProcessors -Sum `
                | select -ExpandProperty Sum
            $NumConsumers = $workers - $NumProducers
        } else {
            $workers = $NumProducers + $NumConsumers
        }

        $params = @{
            ThreadId  = "n/a"
            WorkQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
            Settings  = New-Object 'System.Collections.Concurrent.ConcurrentDictionary`2[object,Object]'
            ResultSet = New-Object System.Collections.Concurrent.ConcurrentBag[object]
        }

        $params.Settings['IsDone'] = $false

        if ($AdditionalParameters) {
            $AdditionalParameters.GetEnumerator() | % {
                $params.Settings[$_.Key] = $_.Value
            }
        }

    }

    End {

        # Create the runspace pool
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

        if ($ImportModules) {
            $ImportModules | % { $sessionState.ImportPSModule($_) }
        }

        if ($ImportModulesPath) {
            $ImportModulesPath | % { $sessionState.ImportPSModulesFromPath($_) }
        }

        $pool = [RunspaceFactory]::CreateRunspacePool(1, $workers, $sessionState, $Host)

        $pool.ApartmentState  = "STA" # Single-threaded runspaces created
        $pool.CleanupInterval = $CleanupInterval * [timespan]::TicksPerMinute

        $pool.Open()

        $threads = @()

        # Spawn the producers
        1..$NumProducers | % {

            $tId = "p-{0:D2}" -f $_

            $thread = [powershell]::Create()
            $thread.RunspacePool = $pool
            $thread.AddScript($Producer) | Out-Null
            $params.ThreadId = $tId
            $thread.AddParameters($params) | Out-Null

            $handle = $thread.BeginInvoke()

            $threads += [pscustomobject]@{
                Id     = $tId
                Type   = 'Producer'
                Thread = $thread
                Handle = $handle
            }

        }

        # Spawn the consumers
        1..$NumConsumers | % {

            $thread = [powershell]::Create()
            $thread.RunspacePool = $pool
            $thread.AddScript($Consumer) | Out-Null
            $params.ThreadId = "c-{0:D2}" -f $_
            $thread.AddParameters($params) | Out-Null

            $handle = $thread.BeginInvoke()

            $threads += [pscustomobject]@{
                Id     = "c-{0:D2}" -f $_
                Type   = 'Consumer'
                Thread = $thread
                Handle = $handle
            }

        }

        Write-Verbose "Wait for the threads to complete."

        while (($threads.Handle -ne $null).Count -gt 0) {

            #$tId = [System.Threading.WaitHandle]::WaitAny($threads.Handle.AsyncWaitHandle)

            for ($tId = 0; $tId -lt $threads.Count; $tId++) {

                $t = $threads[$tId]
                
                if ($t.Handle.IsCompleted) {

                    Write-Verbose "$($t.Type) $($t.Id) is done."
                    if ($PSBoundParameters['Verbose'].IsPresent `
                        -and $t.Thread.Streams.Verbose) {
                        Write-Verbose "$($t.Thread.Streams.Verbose.ReadAll())"
                    }

                    if ($t.Thread.HadErrors) {
                        Write-Error "Thread $($t.Id)`n$($t.Thread.Streams.Error.ReadAll())`n"
                    }

                    if ($t.Thread.Streams) {

                    }

                    # get the results
                    $t.Thread.EndInvoke($t.Handle) | Write-Output

                    $t.Thread.Dispose()
                    $t.Thread = $null
                    $t.Handle = $null

                }
            }

            Start-Sleep -Milliseconds 100

        }

        # Clean up
        $pool.Close()

        return $params.ResultSet

    }

}

#Export-ModuleMember -Function 'Invoke-ProducerConsumerPool'

################################################################################

$prod = {
    Param($ThreadId, $WorkQueue, $Settings)
    #Write-Host "$ThreadId - Starting"
    1..100000 | % {
        $WorkQueue.Enqueue("Producer says: $_")
    }
    $Settings['IsDone'] = $true
    #Write-Host "$ThreadId - Done"
}

$cons = {
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
}

$results = Invoke-ProducerConsumerPool $prod $cons -Verbose
$results | % { [regex]::Matches($_, "(c|p)-\d{2}").Groups[0].Value } | group

################################################################################
