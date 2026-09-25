$baseUrl = "https://gitlab.com"
$token   = "MYTOKENHERE"

$uri = "$baseUrl/api/graphql"

$schemaQuery = @'
query {
    __type(name: "WorkItem") {
        fields(includeDeprecated: false) {
            name
            args {
                type {
                    kind
                }
            }
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
'@

$body = @{
    query = $schemaQuery
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod `
    -Method Post `
    -Uri $uri `
    -Headers @{
        Authorization = "Bearer $token"
    } `
    -ContentType "application/json" `
    -Body $body

if ($response.errors) {
    $response.errors | ConvertTo-Json -Depth 10
    throw "GitLab returned GraphQL errors."
}

function Get-BaseType {
    param (
        $FieldType
    )

    if ($null -eq $FieldType) {
        return $null
    }

    if ($FieldType.kind -in @("NON_NULL", "LIST")) {
        return Get-BaseType $FieldType.ofType
    }

    return $FieldType
}

$fields = $response.data.__type.fields

$simpleFields = $fields | Where-Object {

    $baseType = Get-BaseType $_.type

    $hasRequiredArgument = $false

    foreach ($arg in $_.args) {
        if ($arg.type.kind -eq "NON_NULL") {
            $hasRequiredArgument = $true
            break
        }
    }

    ($baseType.kind -in @("SCALAR", "ENUM")) -and
    (-not $hasRequiredArgument)
}

$simpleFields |
    Select-Object `
        name,
        @{
            Name = "Kind"
            Expression = {
                (Get-BaseType $_.type).kind
            }
        },
        @{
            Name = "GraphQLType"
            Expression = {
                (Get-BaseType $_.type).name
            }
        } | Sort-Object | Out-GridView
