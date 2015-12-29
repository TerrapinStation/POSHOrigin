#Thank the FSM for the internets!
# http://rosettacode.org/wiki/Topological_sort#PowerShell
# http://stackoverflow.com/questions/8982782/does-anyone-have-a-dependency-graph-and-topological-sorting-code-snippet-for-pow

function _SortByDependency {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [psobject[]]$Objects
    )

    $edgeList = @{}
    $Objects | ForEach-Object {
        $edgeList.Add($_.FullName, $_)
    }

    #Write-Host ($edgeList | Format-Table * | Out-String)

    # Make sure we can use HashSet
    Add-Type -AssemblyName System.Core

    # Clone it so as to not alter original
    $currentEdgeList = [hashtable] (_CopyObject -DeepCopyObject $edgeList)

    $topologicallySortedElements = New-Object System.Collections.ArrayList
    $setOfAllNodesWithNoIncomingEdges = New-Object System.Collections.Queue

    $fasterEdgeList = @{}

    # Keep track of all nodes in case they put it in as an edge destination but not source
    $allNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentEdgeList.Keys)

    foreach($currentNode in $currentEdgeList.Keys) {
        $currentDestinationNodes = [array]$currentEdgeList[$currentNode].DependsOn
        if($currentDestinationNodes.Length -eq 0) {
            $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
        }

        foreach($currentDestinationNode in $currentDestinationNodes) {
            if(!$allNodes.Contains($currentDestinationNode)) {
                [void] $allNodes.Add($currentDestinationNode)
            }
        }

        # Take this time to convert them to a HashSet for faster operation
        if ($currentDestinationNodes) {
            $currentDestinationNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentDestinationNodes )
            [void] $fasterEdgeList.Add($currentNode, $currentDestinationNodes)
        }
    }

    #Now let's reconcile by adding empty dependencies for source nodes they didn't tell us about
    foreach($currentNode in $allNodes) {
        if(!$currentEdgeList.ContainsKey($currentNode)) {
            [void] $currentEdgeList.Add($currentNode, (New-Object -TypeName System.Collections.Generic.HashSet[object]))
            $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
        }
    }

    $currentEdgeList = $fasterEdgeList

    while($setOfAllNodesWithNoIncomingEdges.Count -gt 0) {
        $currentNode = $setOfAllNodesWithNoIncomingEdges.Dequeue()
        [void] $currentEdgeList.Remove($currentNode)
        [void] $topologicallySortedElements.Add($currentNode)

        foreach($currentEdgeSourceNode in $currentEdgeList.Keys) {
            $currentNodeDestinations = $currentEdgeList[$currentEdgeSourceNode]
            if($currentNodeDestinations.Contains($currentNode)) {
                [void] $currentNodeDestinations.Remove($currentNode)

                if($currentNodeDestinations.Count -eq 0) {
                    [void] $setOfAllNodesWithNoIncomingEdges.Enqueue($currentEdgeSourceNode)
                }
            }
        }
    }

    if($currentEdgeList.Count -gt 0) {
        throw "Cyclic dependency found! Adjust resource dependencies via the 'DependsOn' property"
    }

    $result = @()
    foreach ($item in $topologicallySortedElements) {
        $result += $edgeList[$item]
    }
    return $result
}