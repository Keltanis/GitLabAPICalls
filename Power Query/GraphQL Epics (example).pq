let
    BaseUrl = "https://gitlab.com",
    Token = "<GAT>",

    GraphQLQuery =
        "query {
            group(fullPath: ""<NAME OF GROUP>"") {
                name
                epics(first: 100) {
                    nodes {
                        id
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

    Group = Data[group],
    Epics = Table.FromRecords(Group[epics][nodes]),
    WithGroupName =
        Table.AddColumn(Epics, "group_name", each Group[name], type text)
in
    WithGroupName
