let
    // ============================================================
    // GITLAB CONNECTION SETTINGS
    // ============================================================

    // Base URL for GitLab.
    // For GitLab.com this remains "https://gitlab.com".
    // A self-hosted GitLab instance would use its own server URL.
    BaseUrl = "https://gitlab.com",

    // Numeric GitLab Group ID containing the projects we want to query.
    // Replace <GROUP ID> with the actual Group ID.
    GroupId = "<GROUP ID>",

    // GitLab Access Token (GAT) used to authenticate API requests.
    // The token must have permission to read the group, projects,
    // and issues being requested.
    Token = "<GAT>",


    // ============================================================
    // FUNCTION: GetPagedList
    // ============================================================
    // GitLab limits how many records an API request can return at once.
    // This reusable function handles that limitation by requesting
    // multiple pages until GitLab returns an empty page.
    //
    // Parameters:
    //   Path    - GitLab API endpoint to call.
    //             Example: "api/v4/projects/123/issues"
    //
    //   Options - Additional query-string parameters for the API.
    //             Example: [state = "opened"]
    //
    // Returns:
    //   A single Power Query list containing records from ALL pages.
    GetPagedList = (Path as text, Options as record) as list =>
        let

            // ----------------------------------------------------
            // FUNCTION: GetPage
            // ----------------------------------------------------
            // Retrieves one specific page from the GitLab API.
            //
            // PageNumber determines which API page is requested.
            GetPage = (PageNumber as number) as list =>
                Json.Document(

                    // Web.Contents sends the HTTP request to GitLab.
                    Web.Contents(
                        BaseUrl,
                        [
                            // RelativePath is appended to BaseUrl.
                            //
                            // Example:
                            // BaseUrl      = https://gitlab.com
                            // RelativePath = api/v4/projects/123/issues
                            //
                            // Result:
                            // https://gitlab.com/api/v4/projects/123/issues
                            RelativePath = Path,

                            // Query contains the URL query-string parameters.
                            Query = Record.Combine({

                                // Preserve any endpoint-specific options
                                // supplied when GetPagedList was called.
                                Options,

                                [
                                    // GitLab allows up to 100 records per page
                                    // for these endpoints. Using 100 reduces
                                    // the total number of API calls required.
                                    per_page = "100",

                                    // Tell GitLab which page to retrieve.
                                    // Query-string values are passed as text.
                                    page = Text.From(PageNumber)
                                ]
                            }),

                            // Send the GitLab Access Token in the HTTP header
                            // so GitLab can authenticate the request.
                            Headers = [
                                #"PRIVATE-TOKEN" = Token
                            ]
                        ]
                    )
                ),


            // ----------------------------------------------------
            // RETRIEVE ALL API PAGES
            // ----------------------------------------------------
            // List.Generate acts like a loop.
            //
            // It:
            //   1. Requests page 1.
            //   2. Checks whether that page contains records.
            //   3. Requests the next page.
            //   4. Continues until GitLab returns an empty page.
            Pages = List.Generate(

                // INITIAL STATE
                // Start with page 1 and immediately retrieve it.
                () => [
                    Page = 1,
                    Rows = GetPage(1)
                ],

                // CONTINUE CONDITION
                // Keep looping while the current page contains records.
                //
                // When GitLab returns an empty list, there are no more
                // records and pagination stops.
                each List.Count([Rows]) > 0,

                // NEXT ITERATION
                // Increase the page number by 1 and retrieve that page.
                each [
                    Page = [Page] + 1,
                    Rows = GetPage([Page] + 1)
                ],

                // OUTPUT
                // Store only the rows returned by each API request.
                each [Rows]
            )

        in
            // Pages is currently a list containing one list per API page.
            //
            // Example:
            // {
            //     {Page 1 records},
            //     {Page 2 records},
            //     {Page 3 records}
            // }
            //
            // List.Combine flattens those page lists into one list:
            //
            // {
            //     all records from all pages
            // }
            List.Combine(Pages),


    // ============================================================
    // DISCOVER PROJECTS IN THE GITLAB GROUP
    // ============================================================
    // Retrieve the projects every time Power Query refreshes.
    //
    // This means project IDs do NOT have to be manually maintained.
    // If a project is later added to the group, it can automatically
    // become part of the next refresh.
    Projects = GetPagedList(
        "api/v4/groups/" & GroupId & "/projects",
        [
            // Include projects belonging to nested/subgroups as well
            // as projects directly under the specified group.
            include_subgroups = "true",

            // Do not include projects merely shared with this group.
            // Only projects belonging to the group hierarchy are wanted.
            with_shared = "false"
        ]
    ),


    // ============================================================
    // FUNCTION: GetProjectIssues
    // ============================================================
    // Retrieves all issues belonging to ONE project.
    //
    // The Project parameter is a project record returned by the
    // GitLab Groups/Projects API above.
    //
    // Returns:
    //   A Power Query table containing the project's issues.
    GetProjectIssues = (Project as record) as table =>
        let

            // Extract the project's numeric GitLab ID.
            //
            // Convert it to text because it will become part of
            // the API endpoint URL.
            ProjectId = Text.From(Project[id]),


            // Retrieve ALL issues for this project.
            //
            // GetPagedList handles pagination automatically, so this
            // works even when a project contains more than 100 issues.
            //
            // [] means that no additional query-string options are
            // currently required for this endpoint.
            Issues = GetPagedList(
                "api/v4/projects/" & ProjectId & "/issues",
                []
            ),


            // GitLab returned a list of issue records.
            // Convert those records into a Power Query table so that
            // each issue becomes a row and its properties become columns.
            IssuesTable = Table.FromRecords(Issues),


            // Add the project's name to every issue row.
            //
            // This is important because all project issue tables will
            // eventually be combined into one master table.
            //
            // Without this column, identifying which project an issue
            // originated from would be less convenient.
            WithProjectName = Table.AddColumn(
                IssuesTable,
                "project_name",
                each Project[name],
                type text
            )

        in
            // Return the completed issue table for this project.
            WithProjectName,


    // ============================================================
    // COMBINE ISSUES FROM ALL PROJECTS
    // ============================================================

    // List.Transform works through every project discovered earlier.
    //
    // For each project:
    //     GetProjectIssues(Project)
    //
    // is executed.
    //
    // Conceptually, this produces:
    //
    // {
    //     Project A Issue Table,
    //     Project B Issue Table,
    //     Project C Issue Table,
    //     ...
    // }
    //
    // Table.Combine then merges those individual tables vertically
    // into one master issue table.
    CombinedIssues = Table.Combine(
        List.Transform(
            Projects,
            each GetProjectIssues(_)
        )
    )

in
    // ============================================================
    // FINAL QUERY OUTPUT
    // ============================================================
    // Return the combined table to Power Query / Power BI.
    //
    // The final result contains issues from every discovered project
    // in the specified GitLab group and its subgroups.
    CombinedIssues
