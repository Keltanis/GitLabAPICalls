let
    BaseUrl = "https://gitlab.com",
    Token = "<GAT>",

    SchemaQuery =
        "query {
            __type(name: ""Issue"") {
                fields(includeDeprecated: false) {
                    name
                    args {
                        type { kind }
                    }
                    type {
                        kind
                        ofType {
                            kind
                            ofType {
                                kind
                                ofType { kind }
                            }
                        }
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
                Content = Json.FromValue([query = SchemaQuery])
            ]
        )
    ),

    BaseKind = (FieldType as nullable record) as nullable text =>
        if FieldType = null then null
        else if List.Contains({"NON_NULL", "LIST"}, FieldType[kind])
            then @BaseKind(FieldType[ofType])
        else FieldType[kind],

    IssueType = List.First(
    List.Select(
        Response[data][__schema][types],
        each _[name] = "Issue"
    )
),
Fields = IssueType[fields],

    SimpleFields = List.Select(
        Fields,
        each
            List.Contains({"SCALAR", "ENUM"}, BaseKind(_[type]))
            and not List.AnyTrue(
                List.Transform(_[args], each _[type][kind] = "NON_NULL")
            )
    ),

    SelectionText = Text.Combine(
        List.Transform(SimpleFields, each _[name]),
        "#(lf)"
    )
in
    SelectionText
