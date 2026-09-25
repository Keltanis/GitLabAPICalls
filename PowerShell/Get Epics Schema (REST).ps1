$baseUrl = "https://gitlab.com"
$groupId = "<GROUP ID>"   
$token   = "<GAT>"

$uri = "$baseUrl/api/v4/groups/$groupId/epics?state=all&per_page=1"

$epics = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
    "PRIVATE-TOKEN" = $token
}

if ($epics.Count -eq 0) {
    Write-Host "No epics found in this group."
}
else {
    $epics[0].PSObject.Properties.Name | Sort-Object
}
