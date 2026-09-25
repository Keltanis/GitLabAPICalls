let
    BaseUrl = "https://gitlab.com",
    Token = "<GAT>",

    GraphQLQuery =
        "query {
            project(fullPath: ""<NAME OF GROUP>/<NAME OF PROJECT>"") {
                name
                issues(first: 100) {
                    nodes {
                        iid
                        title
                        description
                        state
                    }
                    pageInfo {
                        hasNextPage
                        endCursor
                    }
                }
            }
        }",

    Response = Json.Document(
        Web.Contents(
            BaseUrl,
            [
                RelativePath = "api/graphql",
                Headers = [
                    Authorization = "Bearer " & Token,
                    #"Content-Type" = "application/json"
                ],
                Content = Json.FromValue([query = GraphQLQuery])
            ]
        )
    ),

    Data =
        if Record.HasFields(Response, "errors")
        then error Error.Record(
            "GitLab GraphQL error",
            "GitLab returned GraphQL errors",
            Response[errors]
        )
        else Response[data],

    Project = Data[project],
    Issues = Table.FromRecords(Project[issues][nodes]),
    WithProjectName =
        Table.AddColumn(Issues, "project_name", each Project[name], type text)
in
    WithProjectName
