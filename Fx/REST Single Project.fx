let
    Source = Json.Document(
        Web.Contents(
            "https://gitlab.com",
            [
                RelativePath = "api/v4/projects/<PROJECT ID>/issues",
                Query = [per_page = "20"],
                Headers = [
                    #"PRIVATE-TOKEN" = "<GAT>"
                ]
            ]
        )
    ),
    Issues = Table.FromRecords(Source)
in
    Issues
