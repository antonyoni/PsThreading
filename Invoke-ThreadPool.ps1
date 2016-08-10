################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

Function Invoke-ThreadPool {
    <#
        .SYNOPSIS
        

        .EXAMPLE
        

        .NOTES
        The consumers are the first ones to start. The producers are 
        Basic script block should look like this:

    #>

    [CmdletBinding()]
    Param(
        # Thread object(s) to invoke.
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   Position=1)]
        [PsObject[]]$Thread,

        # Parameters to pass to the threads. By default, this will have the parameter 'ThreadId'.
        [Parameter(Mandatory=$false,
                   Position=2)]
        [Alias('Params')]
        [hashtable]$Parameters,

        # Maximum number of Thread Pool threads. Default is the number of Logical CPUs.
        [Parameter(Mandatory=$false)]
        [int]$MaxThreads,

        # Modules to import into the Thread Pool.
        [Parameter(Mandatory=$false)]
        [String[]]$ModulesToImport,

        # Paths to modules to import into the Thread Pool.
        [Parameter(Mandatory=$false)]
        [String[]]$PathsToImport,

        # Garbage collector cleanup interval in minutes.
        [Parameter(Mandatory=$false)]
        [int]$CleanupInterval = 2,

        # Polling interval to check for thread completion. For longer running tasks, set to higher number. Default is 200ms.
        [Parameter(Mandatory=$false)]
        [int]$PollingInterval = 200
    )

    Begin {
        if (!$MaxThreads) {
            $MaxThreads = Get-WmiObject Win32_Processor `
                | Measure-Object -Property NumberOfLogicalProcessors -Sum `
                | select -ExpandProperty Sum
        }

        if ($Parameters.ContainsKey('ThreadId')) {
            Write-Warning "The Paramter 'ThreadId' is system reserved. It will be overwritten."
        }

        # Create the runspace pool
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

        if ($ModulesToImport) {
            $ModulesToImport | % { $sessionState.ImportPSModule($_) }
        }

        if ($PathsToImport) {
            $PathsToImport | % { $sessionState.ImportPSModulesFromPath($_) }
        }

        $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)

        $pool.ApartmentState  = "STA" # Single-threaded runspaces created
        $pool.CleanupInterval = $CleanupInterval * [timespan]::TicksPerMinute

        $pool.Open()

        $threads = @()
    }

    Process {

        # Add the threads but do not start them yet.
        foreach ($type in $Thread) {

            if (($type | Get-Member).TypeName -ne 'PsThreading.Thread') {
                Write-Error "The threads needs to be of type 'PsThreading.Thread'. Use the New-Thread function to create one."
                continue
            }

            for ($i = 1; $i -le $type.Number; $i++) {
                
                $t = $type.PsObject.Copy()
            
                $t.Id = $type.Id -f $i

                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                $ps.AddScript($t.ScriptBlock) | Out-Null
                $Parameters.ThreadId = $t.Id
                $ps.AddParameters($Parameters) | Out-Null

                $t.Thread = $ps

                $threads += $t

            }

        }

    }

    End {
        
        Write-Verbose "Start your engines..."

        $threads | Sort-Object -Property @{ Expression="Weight"; Descending=$true },
            @{ Expression="Id"; Descending=$false } | % {
            Write-Verbose "Starting $($_.Id)."
            $_.Handle = $_.Thread.BeginInvoke()
        }

        Write-Verbose "Waiting for the threads to complete..."

        while ($threads.Handle -ne $null) {

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

            Start-Sleep -Milliseconds $PollingInterval

        }

        # Clean up
        $pool.Close()

        #Write-Output $Parameters

    }

}

#Export-ModuleMember -Function 'Invoke-ThreadPool'

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
