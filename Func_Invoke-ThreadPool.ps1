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
        Create a thread pool and run a number of concurrent threads.

        .DESCRIPTION
        To create threads to run use the New-Thread function. Patterns and samples are available
        in the PsThreading variable.

        .EXAMPLE
        Invoke-ThreadPool -Thread $Producer, $Consumer -Parameters @{ WorkQueue = $q l $ResultSet = $rs }

        .EXAMPLE
        New-Thread $ScriptBlock -Number $NumCPUs | Invoke-ThreadPool -Parameters @{ WorkQueue = $q }

        .NOTES
        The maximum number of concurrent threads is, if not explicitly, the number of logical CPUs.
        However, the number of threads spawned is controlled by the 'Number' property of each
        'PsThreading.Thread' object. By default that number is 1, so set it to num logical CPUs or
        greater to make full use of the threadpool.
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

        # Garbage collector cleanup interval in minutes. Default is 2.
        [Parameter(Mandatory=$false)]
        [int]$CleanupInterval = 2,

        # Polling interval to check for thread completion. For longer running tasks, set to higher number. Default is 500ms.
        [Parameter(Mandatory=$false)]
        [int]$PollingInterval = 500
    )

    Begin {

        if (!$MaxThreads) {
            $MaxThreads = Get-WmiObject Win32_Processor |
                Measure-Object -Property NumberOfLogicalProcessors -Sum |
                select -ExpandProperty Sum
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
                Write-Error ("The threads needs to be of type 'PsThreading.Thread'. " +
                    "Use the New-Thread function to create one.")
                continue
            }

            for ($i = 1; $i -le $type.Number; $i++) {
                
                $t = $type.PsObject.Copy()
            
                $t.Id = $type.Id -f $i

                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                $ps.AddScript($t.ScriptBlock) | Out-Null
                $Parameters['ThreadId'] = $t.Id
                $ps.AddParameters($Parameters) | Out-Null
                $Parameters.Remove('ThreadId')

                $t.Thread = $ps

                $threads += $t

            }

        }

    }

    End {

        $threads | Sort-Object -Property @{ Expression="Weight"; Descending=$true },
            @{ Expression="Id"; Descending=$false } | % {
            Write-Verbose "Starting $($_.Id)."
            $_.Handle = $_.Thread.BeginInvoke()
        }

        Write-Verbose "Waiting (polling every ${PollingInterval}ms) for the threads to complete..."

        while ($threads.Handle -ne $null) {
            
            # TODO: Switch to waiting for handles rather polling.
            #$tId = [System.Threading.WaitHandle]::WaitAny($threads.Handle.AsyncWaitHandle)

            for ($tId = 0; $tId -lt $threads.Count; $tId++) {

                $t = $threads[$tId]
                
                if ($t.Handle.IsCompleted) {

                    Write-Verbose "$($t.Type) $($t.Id) is done."

                    if ($t.Thread.HadErrors) {
                        Write-Error "Thread $($t.Id)`n$($t.Thread.Streams.Error.ReadAll())`n"
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

        $pool.Close()

    }

}

Export-ModuleMember -Function 'Invoke-ThreadPool'
