$baseUrl = "https://gitlab.com"
$token   = "MYTOKENHERE"

$uri = "$baseUrl/api/graphql"

# GraphQL introspection query for the Issue type
$schemaQuery = @'
query {
    __type(name: "Issue") {
        fields(includeDeprecated: false) {
            name
            args {
                type {
                    kind
                }
            }
            type {
                kind
                ofType {
                    kind
                    ofType {
                        kind
                        ofType {
                            kind
                        }
                    }
                }
            }
        }
    }
}
'@

# Build the JSON request body
$body = @{
    query = $schemaQuery
} | ConvertTo-Json -Depth 10

# Send the GraphQL request to GitLab
$response = Invoke-RestMethod `
    -Method Post `
    -Uri $uri `
    -Headers @{
        Authorization = "Bearer $token"
    } `
    -ContentType "application/json" `
    -Body $body

# Stop if GitLab returned GraphQL errors
if ($response.errors) {
    $response.errors | ConvertTo-Json -Depth 10
    throw "GitLab returned GraphQL errors."
}

# Recursively unwrap NON_NULL and LIST wrappers to find
# the underlying GraphQL type (SCALAR, ENUM, OBJECT, etc.)
function Get-BaseKind {
    param (
        $FieldType
    )

    if ($null -eq $FieldType) {
        return $null
    }

    if ($FieldType.kind -in @("NON_NULL", "LIST")) {
        return Get-BaseKind $FieldType.ofType
    }

    return $FieldType.kind
}

# Get all fields defined on the GitLab Issue GraphQL type
$fields = $response.data.__type.fields

# Keep only fields that:
#   1. Resolve to a simple SCALAR or ENUM value
#   2. Do not require arguments
$simpleFields = $fields | Where-Object {

    $baseKind = Get-BaseKind $_.type

    $hasRequiredArgument = $false

    foreach ($arg in $_.args) {
        if ($arg.type.kind -eq "NON_NULL") {
            $hasRequiredArgument = $true
            break
        }
    }

    ($baseKind -in @("SCALAR", "ENUM")) -and
    (-not $hasRequiredArgument)
}

# Output just the field/property names
$simpleFields.name | Sort-Object | Out-GridView
