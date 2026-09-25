$ErrorActionPreference = 'Stop'

$here = Get-Location
$proj = Get-ChildItem -Path $here -Filter 'ZubiVPN.csproj' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proj) { throw "ZubiVPN.csproj not found under $here" }
$root = $proj.Directory.FullName
Set-Location $root

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root ".loginfix-backup-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null

$authPath = Join-Path $root 'Services\AuthService.cs'
$apiPath  = Join-Path $root 'Services\ZubiApiClient.cs'
Copy-Item $authPath (Join-Path $backup 'AuthService.cs')
Copy-Item $apiPath  (Join-Path $backup 'ZubiApiClient.cs')

$auth = Get-Content $authPath -Raw
$oldReq = 'public sealed record LoginRequest(string Username, string Password);'
$newReq = @'
public sealed record LoginRequest(
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string Password);
'@
if ($auth.Contains($oldReq)) {
    $auth = $auth.Replace($oldReq, $newReq.TrimEnd())
} elseif (-not ($auth -match 'JsonPropertyName\("username"\).*Username')) {
    throw 'LoginRequest patch anchor not found.'
}

$oldChange = 'public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);'
$newChange = @'
public sealed record ChangePasswordRequest(
    [property: JsonPropertyName("currentPassword")] string CurrentPassword,
    [property: JsonPropertyName("newPassword")] string NewPassword);
'@
if ($auth.Contains($oldChange)) { $auth = $auth.Replace($oldChange, $newChange.TrimEnd()) }

$loginAnchor = @'
        var result = await _api.PostAsync<LoginRequest, LoginResponse>(
            "/v1/auth/login", new LoginRequest(username, password), ct);
'@
if ($auth.Contains($loginAnchor) -and -not $auth.Contains('usernameLength=')) {
    $replacement = @'
        _logging.Info("AuthService", $"Sending login request (usernameLength={username.Length}, passwordLength={password.Length}).");
        var result = await _api.PostAsync<LoginRequest, LoginResponse>(
            "/v1/auth/login", new LoginRequest(username, password), ct);
'@
    $auth = $auth.Replace($loginAnchor, $replacement)
}
Set-Content -Path $authPath -Value $auth -Encoding utf8NoBOM

$api = Get-Content $apiPath -Raw
if (-not $api.StartsWith('using System.Text;')) {
    $api = 'using System.Text;' + [Environment]::NewLine + $api
}

$oldPost = @'
    public async Task<OperationResult<TResp>> PostAsync<TReq, TResp>(string path, TReq body, CancellationToken ct)
    {
        ApplyAuthHeader();
        try
        {
            using var resp = await _http.PostAsJsonAsync(Url(path), body, JsonOptions, ct);
            if (!resp.IsSuccessStatusCode)
                return OperationResult<TResp>.Fail($"HTTP {(int)resp.StatusCode}");
            var parsed = await resp.Content.ReadFromJsonAsync<TResp>(JsonOptions, ct);
            return parsed is null ? OperationResult<TResp>.Fail("Empty response") : OperationResult<TResp>.Ok(parsed);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception ex)
        {
            _logging.Warning("ZubiApiClient", $"POST {path} failed: {ex.GetType().Name}: {ex.Message}");
            return OperationResult<TResp>.Fail(Describe(ex, ct));
        }
    }
'@

$newPost = @'
    public async Task<OperationResult<TResp>> PostAsync<TReq, TResp>(string path, TReq body, CancellationToken ct)
    {
        ApplyAuthHeader();
        try
        {
            // Production Core reads request bodies using Content-Length.
            // JsonContent/PostAsJsonAsync can stream without Content-Length,
            // causing the Core to parse {} and reject an otherwise valid login.
            var json = JsonSerializer.Serialize(body, JsonOptions);
            using var content = new StringContent(json, Encoding.UTF8, "application/json");
            using var request = new HttpRequestMessage(HttpMethod.Post, Url(path)) { Content = content };
            if (!string.IsNullOrEmpty(SessionToken))
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", SessionToken);

            _logging.Info("ZubiApiClient", $"POST {path} sending {Encoding.UTF8.GetByteCount(json)} JSON bytes.");
            using var resp = await _http.SendAsync(request, HttpCompletionOption.ResponseContentRead, ct);
            if (!resp.IsSuccessStatusCode)
                return OperationResult<TResp>.Fail($"HTTP {(int)resp.StatusCode}");
            var parsed = await resp.Content.ReadFromJsonAsync<TResp>(JsonOptions, ct);
            return parsed is null ? OperationResult<TResp>.Fail("Empty response") : OperationResult<TResp>.Ok(parsed);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception ex)
        {
            _logging.Warning("ZubiApiClient", $"POST {path} failed: {ex.GetType().Name}: {ex.Message}");
            return OperationResult<TResp>.Fail(Describe(ex, ct));
        }
    }
'@

if ($api.Contains($oldPost)) {
    $api = $api.Replace($oldPost, $newPost)
} elseif (-not $api.Contains('new StringContent(json, Encoding.UTF8, "application/json")')) {
    throw 'PostAsync patch anchor not found; refusing to guess.'
}
Set-Content -Path $apiPath -Value $api -Encoding utf8NoBOM

@(
    'ZUBIVPN login transport fix applied.',
    "Project: $root",
    "Backup: $backup",
    'Explicit username/password JSON names: OK',
    'Buffered JSON POST with Content-Length: OK',
    'UI/XAML layout changed: NO'
) | Set-Content (Join-Path $root 'login-fix-report.txt') -Encoding utf8

Write-Host 'LOGIN FIX APPLIED'
Write-Host "Project: $root"
Write-Host "Backup: $backup"
