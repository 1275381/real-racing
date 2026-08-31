param(
    [int]$Port = 8017,
    [switch]$NoOpen
)

# 极速争锋 REAL RACING —— Windows 启动器
# 零依赖（不需要 Python / Node）：用系统自带 PowerShell 起一个禁缓存静态服务器，
# 行为与 macOS 的 启动游戏.command 保持一致。双击 启动游戏.bat 即可运行。

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$rootFull = [IO.Path]::GetFullPath($root)

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.mjs'  = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.map'  = 'application/json'
    '.glb'  = 'model/gltf-binary'
    '.gltf' = 'model/gltf+json'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.webp' = 'image/webp'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.mp3'  = 'audio/mpeg'
    '.wav'  = 'audio/wav'
    '.ogg'  = 'audio/ogg'
    '.txt'  = 'text/plain; charset=utf-8'
    '.md'   = 'text/plain; charset=utf-8'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}

Write-Host ''
Write-Host '  正在启动 极速争锋 REAL RACING ...' -ForegroundColor Cyan

$listener = $null
foreach ($p in $Port..($Port + 9)) {
    try {
        $candidate = New-Object System.Net.HttpListener
        $candidate.Prefixes.Add("http://localhost:$p/")
        $candidate.Start()
        $listener = $candidate
        $Port = $p
        break
    } catch {
        if ($candidate) { $candidate.Close() }
    }
}
if (-not $listener -or -not $listener.IsListening) {
    Write-Host "  [失败] 端口 $Port ~ $($Port + 9) 全部被占用，无法启动服务。" -ForegroundColor Red
    Write-Host '  如果之前已开过一个启动窗口，直接用它打开的浏览器页面游玩即可。'
    try { Read-Host '按回车键关闭窗口' | Out-Null } catch {}
    exit 1
}

$url = "http://localhost:$Port/index.html"
Write-Host "  本地服务地址: $url"
Write-Host '  浏览器即将自动打开，关闭本窗口即停止服务。'
Write-Host ''

if (-not $NoOpen) {
    try { Start-Process $url } catch {
        Write-Host "  无法自动打开浏览器，请手动访问: $url" -ForegroundColor Yellow
    }
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath)
            if ($rel -eq '/') { $rel = '/index.html' }
            $full = [IO.Path]::GetFullPath((Join-Path $rootFull $rel.TrimStart('/')))
            if ([IO.Directory]::Exists($full)) { $full = Join-Path $full 'index.html' }

            $resp = $ctx.Response
            $resp.Headers['Cache-Control'] = 'no-store, must-revalidate'
            $resp.Headers['Pragma'] = 'no-cache'
            $resp.Headers['Expires'] = '0'

            if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                $resp.StatusCode = 403
            } elseif ([IO.File]::Exists($full)) {
                $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
                if ($mime.ContainsKey($ext)) { $resp.ContentType = $mime[$ext] }
                $bytes = [IO.File]::ReadAllBytes($full)
                $resp.ContentLength64 = $bytes.Length
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $resp.StatusCode = 404
            }
        } catch {
            try { $ctx.Response.StatusCode = 500 } catch {}
        } finally {
            try { $ctx.Response.OutputStream.Close() } catch {}
        }
    }
} finally {
    try { $listener.Stop() } catch {}
}
