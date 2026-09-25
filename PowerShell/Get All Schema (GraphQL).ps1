$baseUrl = "https://gitlab.com"
$token   = "<GAT>"
$fullPath = "<GROUP>/<PROJECT>"

$uri = "$baseUrl/api/graphql"

$headers = @{
    Authorization = "Bearer $token"
}

function Invoke-GitLabGraphQL {

    param (
        [string]$Query,
        [hashtable]$Variables = @{}
    )

    $body = @{
        query     = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 50

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    if ($response.errors) {
        $response.errors |
            ConvertTo-Json -Depth 20 |
            Write-Host

        throw "GitLab returned GraphQL errors."
    }

    return $response
}


# ------------------------------------------------------------
# GET ISSUE + EPIC WORK ITEM DEFINITIONS
# ------------------------------------------------------------

$typeQuery = @'
query GetWorkItemTypes($fullPath: ID!) {
    namespace(fullPath: $fullPath) {
        workItemTypes {
            nodes {
                name
                widgetDefinitions {
                    type
                }
            }
        }
    }
}
'@

$typeResponse = Invoke-GitLabGraphQL `
    -Query $typeQuery `
    -Variables @{
        fullPath = $fullPath
    }

$workItemTypes =
    $typeResponse.data.namespace.workItemTypes.nodes

$issueType =
    $workItemTypes |
    Where-Object { $_.name -eq "Issue" } |
    Select-Object -First 1

$epicType =
    $workItemTypes |
    Where-Object { $_.name -eq "Epic" } |
    Select-Object -First 1


# ------------------------------------------------------------
# GET COMPLETE GRAPHQL SCHEMA
# ------------------------------------------------------------

$schemaQuery = @'
query {
    __schema {
        types {
            kind
            name

            fields(includeDeprecated: false) {
                name

                type {
                    kind
                    name

                    ofType {
                        kind
                        name

                        ofType {
                            kind
                            name

                            ofType {
                                kind
                                name
                            }
                        }
                    }
                }
            }
        }
    }
}
'@

$schemaResponse =
    Invoke-GitLabGraphQL -Query $schemaQuery

$schemaTypes =
    $schemaResponse.data.__schema.types


# ------------------------------------------------------------
# FIND COMMON WORK ITEM OBJECT
# ------------------------------------------------------------

$workItemObject =
    $schemaTypes |
    Where-Object {

        $_.kind -eq "OBJECT" -and
        $_.fields -and

        ($_.fields.name -contains "iid") -and
        ($_.fields.name -contains "title") -and
        ($_.fields.name -contains "state") -and
        ($_.fields.name -contains "widgets")
    } |
    Select-Object -First 1

if (-not $workItemObject) {
    throw "Could not identify the Work Item GraphQL object."
}


# ------------------------------------------------------------
# GET ACTUAL QUERYABLE WIDGET OBJECTS
#
# Excludes WorkItemWidgetDefinition*
# ------------------------------------------------------------

$widgetObjects =
    $schemaTypes |
    Where-Object {

        $_.kind -eq "OBJECT" -and
        $_.name -like "WorkItemWidget*" -and
        $_.name -notlike "WorkItemWidgetDefinition*" -and
        $_.fields
    }


# ------------------------------------------------------------
# HELPER: CONVERT WIDGET ENUM TO GRAPHQL OBJECT NAME
#
# ASSIGNEES
#     -> WorkItemWidgetAssignees
#
# START_AND_DUE_DATE
#     -> WorkItemWidgetStartAndDueDate
# ------------------------------------------------------------

function Get-WidgetObject {

    param (
        [string]$WidgetType
    )

    $parts =
        $WidgetType.ToLower().Split("_")

    $pascal =
        ($parts |
            ForEach-Object {

                if ($_.Length -gt 0) {

                    $_.Substring(0,1).ToUpper() +
                    $_.Substring(1)
                }

            }) -join ""

    $expectedName =
        "WorkItemWidget$pascal"

    $match =
        $widgetObjects |
        Where-Object {
            $_.name -eq $expectedName
        } |
        Select-Object -First 1

    if (-not $match) {

        $match =
            $widgetObjects |
            Where-Object {
                $_.name -like "*$pascal*"
            } |
            Select-Object -First 1
    }

    return $match
}


# ------------------------------------------------------------
# BUILD PROPERTY MATRIX
# ------------------------------------------------------------

$matrix = @{}


# ------------------------------------------------------------
# COMMON WORK ITEM FIELDS
#
# These are directly on the Work Item object rather than
# supplied through a widget.
# ------------------------------------------------------------

foreach ($field in $workItemObject.fields) {

    if ($field.name -eq "widgets") {
        continue
    }

    $key =
        "BASE::$($field.name)"

    $matrix[$key] =
        [PSCustomObject]@{

            Property =
                $field.name

            Issue =
                if ($issueType) { "Yes" } else { "N/A" }

            Epic =
                if ($epicType) { "Yes" } else { "N/A" }

            Location =
                "Work Item"

            GraphQLObject =
                $workItemObject.name
        }
}


# ------------------------------------------------------------
# PROCESS ISSUE WIDGETS
# ------------------------------------------------------------

if ($issueType) {

    foreach ($definition in $issueType.widgetDefinitions) {

        $widget =
            Get-WidgetObject `
                -WidgetType $definition.type

        if (-not $widget) {
            continue
        }

        $location =
            $definition.type `
                -replace "_", " "

        $location =
            (Get-Culture).TextInfo.ToTitleCase(
                $location.ToLower()
            ) + " Widget"


        foreach ($field in $widget.fields) {

            if ($field.name -in @("type", "__typename")) {
                continue
            }

            $key =
                "$($widget.name)::$($field.name)"


            if (-not $matrix.ContainsKey($key)) {

                $matrix[$key] =
                    [PSCustomObject]@{

                        Property =
                            $field.name

                        Issue =
                            "No"

                        Epic =
                            "No"

                        Location =
                            $location

                        GraphQLObject =
                            $widget.name
                    }
            }

            $matrix[$key].Issue =
                "Yes"
        }
    }
}


# ------------------------------------------------------------
# PROCESS EPIC WIDGETS
# ------------------------------------------------------------

if ($epicType) {

    foreach ($definition in $epicType.widgetDefinitions) {

        $widget =
            Get-WidgetObject `
                -WidgetType $definition.type

        if (-not $widget) {
            continue
        }

        $location =
            $definition.type `
                -replace "_", " "

        $location =
            (Get-Culture).TextInfo.ToTitleCase(
                $location.ToLower()
            ) + " Widget"


        foreach ($field in $widget.fields) {

            if ($field.name -in @("type", "__typename")) {
                continue
            }

            $key =
                "$($widget.name)::$($field.name)"


            if (-not $matrix.ContainsKey($key)) {

                $matrix[$key] =
                    [PSCustomObject]@{

                        Property =
                            $field.name

                        Issue =
                            if ($issueType) {
                                "No"
                            }
                            else {
                                "N/A"
                            }

                        Epic =
                            "No"

                        Location =
                            $location

                        GraphQLObject =
                            $widget.name
                    }
            }

            $matrix[$key].Epic =
                "Yes"
        }
    }
}


# ------------------------------------------------------------
# NORMALIZE N/A VALUES
# ------------------------------------------------------------

foreach ($item in $matrix.Values) {

    if (-not $issueType) {
        $item.Issue = "N/A"
    }

    if (-not $epicType) {
        $item.Epic = "N/A"
    }
}


# ------------------------------------------------------------
# FINAL OUTPUT
# ------------------------------------------------------------

$results =
    $matrix.Values |
    Select-Object `
        @{Name="Property / Node"; Expression={$_.Property}},
        Issue,
        Epic,
        @{Name="GraphQL Location"; Expression={$_.Location}},
        @{Name="GraphQL Object"; Expression={$_.GraphQLObject}} |
    Sort-Object `
        "GraphQL Location",
        "Property / Node"


$results |
    Out-GridView `
        -Title "GitLab GraphQL - Issue vs Epic Available Nodes"
