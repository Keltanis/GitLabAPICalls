let
    BaseUrl = "https://gitlab.com",
    Token = "<GAT>",
    ProjectIds = {"<PROJECT ID>", "<PROJECT ID>"},

    GetProjectIssues = (ProjectId as text) as table =>
        let
            Project = Json.Document(
                Web.Contents(
                    BaseUrl,
                    [
                        RelativePath = "api/v4/projects/" & ProjectId,
                        Headers = [#"PRIVATE-TOKEN" = Token]
                    ]
                )
            ),
            ProjectName = Project[name],

            GetPage = (PageNumber as number) as list =>
                Json.Document(
                    Web.Contents(
                        BaseUrl,
                        [
                            RelativePath = "api/v4/projects/" & ProjectId & "/issues",
                            Query = [
                                per_page = "100",
                                page = Text.From(PageNumber)
                            ],
                            Headers = [#"PRIVATE-TOKEN" = Token]
                        ]
                    )
                ),

            Pages = List.Generate(
                () => [Page = 1, Rows = GetPage(1)],
                each List.Count([Rows]) > 0,
                each [Page = [Page] + 1, Rows = GetPage([Page] + 1)],
                each [Rows]
            ),
            Issues = List.Combine(Pages),
            IssuesTable = Table.FromRecords(Issues),
            WithProjectName = Table.AddColumn(
                IssuesTable,
                "project_name",
                each ProjectName,
                type text
            )
        in
            WithProjectName,

    CombinedIssues = Table.Combine(
        List.Transform(ProjectIds, each GetProjectIssues(_))
    )
in
    CombinedIssues
