[Version = "0.3.0"]
section PBIServiceMetadata;

BaseURL = "https://api.powerbi.com/v1.0/myorg/";
ClientId = Extension.LoadString("PBIServiceApplication"); // load application id from resources.resx
TenantId = "common"; // Extension.LoadString("PBIServiceTenant"); // load tenant id from resources.resx
AuthorizeUri = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/authorize";
TokenUri = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/token";
LogoutUri = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/logout";
RedirectUri = "https://oauth.powerbi.com/views/oauthredirect.html";
DefaultScopes = "https://analysis.windows.net/powerbi/api/Workspace.Read.All https://analysis.windows.net/powerbi/api/Report.Read.All offline_access";

// OAuth2 flow helpers

PBIServiceMetadata.TokenRequest = (body as record) =>
    let
        // Merge client credentials into the body
        FullBody = Record.Combine({
            body,
            [
                client_id = ClientId
                // client_secret = ClientSecret // if client secret is needed
            ]
        }),
        Response = Web.Contents(
            TokenUri,
            [
                Content = Text.ToBinary(
                    Uri.BuildQueryString(FullBody),
                    TextEncoding.Ascii
                ),
                Headers = [
                    #"Content-Type" = "application/x-www-form-urlencoded",
                    Accept = "application/json"
                ],
                ManualCredentials = true,
                IsRetry = true
            ]
        ),
        JsonResponse = Json.Document(Response),

        // Validation
        Result = if Record.HasFields(JsonResponse, {"access_token"})
            then JsonResponse
            else error Error.Record("TokenError", "Token endpoint did not return an access_token", JsonResponse)
    in
        Result;

PBIServiceMetadata.GenerateCodeVerifier = () =>
    let
        RandomBytes = Binary.FromList(List.Transform({1..32}, each Number.Round(Number.RandomBetween(0, 255)))),
        Base64 = Binary.ToText(RandomBytes, BinaryEncoding.Base64),
        Base64Url = Text.Replace(
            Text.Replace(
                Text.Replace(
                    Base64,
                    "+", "-"
                ),
                "/", "_"
            ),
            "=", ""
        )
    in Base64Url;

PBIServiceMetadata.GenerateCodeChallenge = (verifier as text) =>
    let
        VerifierBytes = Text.ToBinary(verifier, TextEncoding.Ascii),
        HashBytes = Crypto.CreateHash(CryptoAlgorithm.SHA256, VerifierBytes),
        Base64 = Binary.ToText(HashBytes, BinaryEncoding.Base64),
        // Convert to Base64url
        Base64Url = Text.Replace(
            Text.Replace(
                Text.Replace(Base64, "+", "-"),
                "/", "_"
            ),
            "=", ""
        )
    in
        Base64Url;

PBIServiceMetadata.StartLogin = (resourceUrl as text, state as text, display as text) =>
    let
        // Generate PKCE code verifier and challenge
        CodeVerifier = PBIServiceMetadata.GenerateCodeVerifier(),
        CodeChallenge = PBIServiceMetadata.GenerateCodeChallenge(CodeVerifier),
        authorizeUrl = AuthorizeUri & "?" & Uri.BuildQueryString([
            client_id = ClientId,
            response_type = "code",
            redirect_uri = RedirectUri,
            scope = DefaultScopes,
            state = state,
            code_challenge = CodeChallenge,
            code_challenge_method = "S256"
        ])
    in
        [
            LoginUri = authorizeUrl,
            CallbackUri = RedirectUri,
            WindowHeight = 720,
            WindowWidth = 1024,
            Context = CodeVerifier
        ];

PBIServiceMetadata.FinishLogin = (context as text, callbackUri as text, state as text) =>
    let
        Parts = Uri.Parts(callbackUri),
        Query = Parts[Query],

        // Check for state match to protect against CSRF
        ReturnedState = Record.FieldOrDefault(Query, "state", ""),
        _ValidateState = if ReturnedState <> state
            then error Error.Record(
                "Security",
                "OAuth state mismatch, possible CSRF attack"
            )
            else null,
        Code = if Record.HasFields(Query, "code")
            then Record.Field(Query, "code")
            else if Record.HasFields(Query, "error")
            then error Error.Record(
                "OAuthError", 
                Record.Field(Query, "error") & ": " & Record.Field(Query, "error_description")
            )
            else error Error.Record("OAuthError", "No code found in response"),
        CodeVerifier = context,
        tokenResponse = PBIServiceMetadata.TokenRequest([
            grant_type = "authorization_code",
            code = Code,
            redirect_uri = RedirectUri,
            code_verifier = CodeVerifier
        ])
    in
        tokenResponse;

PBIServiceMetadata.Refresh = (resourceUrl as text, oldCredential as record) =>
    let
        RefreshToken= oldCredential[refresh_token],
        TokenResponse = PBIServiceMetadata.TokenRequest([
            grant_type = "refresh_token",
            refresh_token = RefreshToken,
            scope = DefaultScopes
        ])
    in
        TokenResponse;

PBIServiceMetadata.Logout = (accessToken as nullable text) =>
    let
        LogoutParameters = [
            token = accessToken,
            token_type_hint = "access_token",
            client_id = ClientId
        ]
    in LogoutUri & "?" & Uri.BuildQueryString([
        client_id = ClientId,
        post_logout_redirect_uri = RedirectUri
    ]);

// Helper Functions

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

// Workspaces Wrapper

[DataSource.Kind="PBIServiceMetadata", Publish="PBIServiceMetadata.PublishWorkspaces"]
shared PBIServiceMetadata.Workspaces = () =>
    let
        Url = BaseURL & "groups",
        Response = Web.Contents(
            Url,
            [
                Headers = [
                    Authorization = "Bearer " & Extension.CurrentCredential()[access_token],
                    Accept = "application/json"
                ]
            ]
        ),
        ResponseRecord = Json.Document(Response),
        TableSchema = type table[id = text, isReadOnly = logical, isOnDedicatedCapacity = logical, name = text],
        RecordTable = if Record.FieldOrDefault(ResponseRecord, "@odata.count", 0) = 0
            then Table.FromRecords({}, TableSchema)
            else Table.FromRecords(ResponseRecord[value], TableSchema)
    in RecordTable;

// Reports Wrapper

// Type table (prompts)
PBIServiceMetadata.ReportsType = type function () as table meta [
    Documentation.Name = "List Reports",
    Documentation.LongDescription = "Lists reports from the specified workspace or My Workspace if none specified"
];

// Navigation table (UI)
PBIServiceMetadata.ReportNavigation = () as table =>
    let
        Workspaces = PBIServiceMetadata.Workspaces(),
        WorkspaceRows = Table.FromRecords(
            List.Transform(
                Table.ToRecords(Workspaces),
                each [
                    Name = [name],
                    Key = [id],
                    Data = PBIServiceMetadata.ReportsByWorkspaceId([id]),
                    ItemKind = "Table",
                    ItemName = "Table",
                    IsLeaf = true
                ]
            )
        ),
        MyWorkspaceRow = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            {{
                "My Workspace",
                null,
                PBIServiceMetadata.ReportsByWorkspaceId(null),
                "Table",
                "Table",
                true
            }}
        ),
        NavTable = Table.ToNavigationTable(
            Table.Combine({WorkspaceRows, MyWorkspaceRow}),
            {"Key"},
            "Name",
            "Data",
            "ItemKind",
            "ItemName",
            "IsLeaf"
        )
    in
        NavTable;

[DataSource.Kind="PBIServiceMetadata"]
shared PBIServiceMetadata.ReportsByWorkspaceId = (optional workspace as nullable text) =>
    let
        Endpoint = if workspace = null
            then "reports"
            else "groups/" & workspace & "/reports",
        Response = Web.Contents(
            BaseURL,
            [
                RelativePath = Endpoint,
                Headers = [
                    Authorization = "Bearer " & Extension.CurrentCredential()[access_token],
                    Accept = "application/json"
                ]
            ]
        ),
        ResponseRecord = Json.Document(Response),
        TableSchema = type table[
            id = text,
            reportType = text,
            format = text,
            name = text,
            webUrl = text,
            embedUrl = text,
            isOwnedByMe = logical,
            datasetId = text,
            datasetWorkspaceId = text
        ],
        RecordTable = Table.FromRecords(ResponseRecord[value], TableSchema)
    in
        RecordTable
    ;

[DataSource.Kind="PBIServiceMetadata", Publish="PBIServiceMetadata.PublishReports"]
shared PBIServiceMetadata.Reports = Value.ReplaceType(
    PBIServiceMetadata.ReportNavigation,
    PBIServiceMetadata.ReportsType
);

// Data Source Kind description
PBIServiceMetadata = [
    Authentication = [
        OAuth = [
            StartLogin = PBIServiceMetadata.StartLogin,
            FinishLogin = PBIServiceMetadata.FinishLogin,
            Refresh = PBIServiceMetadata.Refresh,
            Logout = PBIServiceMetadata.Logout
        ]
    ],
    Label = Extension.LoadString("PBIServiceMetadata_Label"),
    SupportsEncryption = true
];

// Data Source UI publishing description
PBIServiceMetadata.PublishWorkspaces = [
    Beta = true,
    Category = "Online Services",
    ButtonText = {"PBI Service Workspaces", "Power BI Service Metadata: Workspaces"},
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = PBIServiceMetadata.Icons,
    SourceTypeImage = PBIServiceMetadata.Icons
];

PBIServiceMetadata.PublishReports = [
    Beta = true,
    Category = "Online Services",
    ButtonText = {"PBI Service Reports", "Power BI Service Metadata: Reports"},
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = PBIServiceMetadata.Icons,
    SourceTypeImage = PBIServiceMetadata.Icons
];

PBIServiceMetadata.Icons = [
    Icon16 = {
        Extension.Contents("PBI Service Metadata16.png"),
        Extension.Contents("PBI Service Metadata20.png"),
        Extension.Contents("PBI Service Metadata24.png"),
        Extension.Contents("PBI Service Metadata32.png")
    },
    Icon32 = {
        Extension.Contents("PBI Service Metadata32.png"),
        Extension.Contents("PBI Service Metadata40.png"),
        Extension.Contents("PBI Service Metadata48.png"),
        Extension.Contents("PBI Service Metadata64.png")
    }
];
