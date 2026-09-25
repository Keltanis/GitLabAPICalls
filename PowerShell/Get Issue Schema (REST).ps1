$baseUrl   = "https://gitlab.com"
$projectId = "<PROJECT ID>"
$token     = "<GAT>"

$uri = "$baseUrl/api/v4/projects/$projectId/issues?state=all&per_page=1"

$issues = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
    "PRIVATE-TOKEN" = $token
}

if ($issues.Count -eq 0) {
    Write-Host "No issues found in this project."
}
else {
    $issues[0].PSObject.Properties.Name | Sort-Object | Out-GridView
}
