# PowerShell Threading Module

This module is designed to simplify multi-threading in PowerShell. PowerShell jobs are a great way to work with background tasks, but lack the necessary throttling and resource-sharing mechanisms. There is also a performance advantage to using a RunspacePool over jobs, as detailed in [this blog post](https://learn-powershell.net/2012/05/13/using-background-runspaces-instead-of-psjobs-for-better-performance/).

### Threading with this module

Use the `New-Thread` function to create a thread template:

```powershell
$ScriptBlock = {
    Param($ThreadId, $WorkQueue)
    $item = ""
    while ($WorkQueue.TryDequeue([ref]$item)) {
        # do work here
        Write-Output "$ThreadId -> $item"
    }
}

$worker = New-Thread -ScriptBlock $ScriptBlock -Number $PsThreading.Utility.LogicalCpus
```

Then use the `Invoke-ThreadPool` function to create and execute the threads, and wait (poll) for them to complete:

```powershell
$workQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
1..10000 | % { $workQueue.Enqueue("item number $_") }

$params = @{
    WorkQueue = $workQueue
}

Invoke-ThreadPool -Thread $worker `
                  -Parameters $params
```

### Helper functions

There is a helper function Split-FileToStream which splits a file based on a delimiter, and creates n memory streams from it. By default, it will split the file into the number of logical CPUs.

```powershell
$Path = '\path\to\large-file.csv'

$workQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]
Split-FileToStream -Path $Path | % { $workQueue.Enqueue($_) }
```

### The PsThreading module variable

The `$PsThreading` variable contains two helper properties:

```powershell
$PsThreading.Utility.CpuCores     # Number of physical cores
$PsThreading.Utility.LogicalCpus  # Number of logical CPUs
```

and some sample parameter sets and thread templates for various threading patterns:

```powershell
$PsThreading.Parameter.WorkerOnly
$PsThreading.Parameter.ProducerConsumer
$PsThreading.Parameter.ProducerWorkerWriter

$PsThreading.Thread.Consumer
$PsThreading.Thread.Producer
$PsThreading.Thread.Worker
$PsThreading.Thread.Writer
```

Have a look at the PsThreading.Patterns.ps1 and PsThreading.Patterns.Tests.ps1 files for some example implementation patterns.

### Examples

Producer - Consumer example where the producer uses the Split-FileToStream function to create file chunks for the consumer threads to then process.

```powershell
$FileToProcess   = '\path\to\large-file.csv'
$PsThreadingPath = '\path\to\PsThreading'

$threads = $PsThreading.Utility.LogicalCpus
$params  = $PsThreading.Parameter.ProducerConsumer

$params.Settings['FileToProcess'] = $FileToProcess
$params.Settings['NumberToProduce'] = $threads * 2

$producer = New-Thread -Type "Producer" -Weight 100 -ScriptBlock {
    Param($ThreadId, $Settings, $WorkQueue)
    $path  = $Settings['FileToProcess']
    $split = $Settings['NumberToProduce']
    Split-FileToStream -Path $path -SplitNumber $split | % {
        $WorkQueue.Enqueue($_)
    }
    $Settings['ProducerIsDone'] = $true
}

$consumer = New-Thread -Type "Consumer" -Number $threads -ScriptBlock {
    Param($ThreadId, $WorkQueue, $Settings, $ResultSet)
    $item = ""
    while (!$Settings['ProducerIsDone'] -or $WorkQueue.Count -gt 0) {
        if ($WorkQueue.TryDequeue([ref]$item)) {
            $reader = New-Object System.IO.StreamReader($item.Stream)
            $count  = 0
            while (($line = $reader.ReadLine()) -ne $null) {
                $count++
            }
            $ResultSet.Add("Thread $ThreadId has processed $count lines.")
        } else {
            Start-Sleep -Milliseconds 10
        }
    }
}

Invoke-ThreadPool -Thread $producer, $consumer -Parameters $params -PathsToImport $PsThreadingPath

$params.ResultSet
```

### License

<a rel="license" href="http://creativecommons.org/licenses/by-sa/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/4.0/88x31.png" /></a>
This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by-sa/4.0/">Creative Commons Attribution-ShareAlike 4.0 International License</a>.
