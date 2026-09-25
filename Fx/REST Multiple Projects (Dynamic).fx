let
    BaseUrl = "https://gitlab.com",
    GroupId = "<GROUP ID>",
    Token = "<GAT>",

    // Fetch every page from a GitLab list endpoint.
    GetPagedList = (Path as text, Options as record) as list =>
        let
            GetPage = (PageNumber as number) as list =>
                Json.Document(
                    Web.Contents(
                        BaseUrl,
                        [
                            RelativePath = Path,
                            Query = Record.Combine({
                                Options,
                                [
                                    per_page = "100",
                                    page = Text.From(PageNumber)
                                ]
                            }),
                            Headers = [#"PRIVATE-TOKEN" = Token]
                        ]
                    )
                ),

            Pages = List.Generate(
                () => [Page = 1, Rows = GetPage(1)],
                each List.Count([Rows]) > 0,
                each [Page = [Page] + 1, Rows = GetPage([Page] + 1)],
                each [Rows]
            )
        in
            List.Combine(Pages),

    // Discover projects each time the query refreshes.
    Projects = GetPagedList(
        "api/v4/groups/" & GroupId & "/projects",
        [
            include_subgroups = "true",
            with_shared = "false"
        ]
    ),

    GetProjectIssues = (Project as record) as table =>
        let
            ProjectId = Text.From(Project[id]),
            Issues = GetPagedList(
                "api/v4/projects/" & ProjectId & "/issues",
                []
            ),
            IssuesTable = Table.FromRecords(Issues),
            WithProjectName = Table.AddColumn(
                IssuesTable,
                "project_name",
                each Project[name],
                type text
            )
        in
            WithProjectName,

    CombinedIssues = Table.Combine(
        List.Transform(Projects, each GetProjectIssues(_))
    )
in
    CombinedIssues
