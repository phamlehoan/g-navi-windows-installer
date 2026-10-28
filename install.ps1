# G-Navi - Cài đặt xe bằng cáp USB (Windows)
# Làm đúng như mục "Cài đặt xe bằng cáp USB" của G-Navi Client, nhưng dùng máy tính làm chủ.
# Chạy bằng install.bat (nhấp đúp). Tham số dành cho kỹ thuật viên / chạy thử xem ở cuối file README.txt.
param(
    [ValidateSet('menu', 'kia', 'app', 'maps', 'grant')][string]$Mode = 'menu',
    [string]$Serial = '',
    [string]$Dir = '/storage/GNX/GNaviAlerts',
    [string]$Maps = '',              # không hỏi: tên vùng cách nhau dấu phẩy (vd viet_nam,bien_dong), 'none' hoặc 'all'
    [switch]$NoLaunch,               # không mở ứng dụng trên xe sau khi xong
    [switch]$AllowUninstall          # tự đồng ý gỡ bản cũ khi xung đột (mặc định phải hỏi)
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Adb = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
$script:Serial = $Serial
$Pkg = 'com.phamlehoan.gnavipro'
$Gnx = '/storage/GNX'
$DefaultDir = '/storage/GNX/GNaviAlerts'
$TmpApk = '/data/local/tmp/gnavi_install.apk'
$User = 'phamlehoan'
$MapRepo = 'g-navi-map-extract'
$MainRepo = 'g-navi-pro'
$Work = Join-Path $env:TEMP ('gnavi-install-' + $PID)

# Tên hiển thị từng gói (đúng thứ tự)
$Titles = [ordered]@{
    'viet_nam.zip'                = 'Toàn quốc (Việt Nam)'
    'mien_nui_phia_bac.zip'       = 'Trung du và miền núi phía Bắc'
    'dong_bang_song_hong.zip'     = 'Đồng bằng sông Hồng'
    'bac_trung_bo.zip'            = 'Bắc Trung Bộ'
    'nam_trung_bo_tay_nguyen.zip' = 'Duyên hải Nam Trung Bộ và Tây Nguyên'
    'dong_nam_bo.zip'             = 'Đông Nam Bộ'
    'dong_bang_song_cuu_long.zip' = 'Đồng bằng sông Cửu Long'
    'bien_dong.zip'               = 'Biển Đông (Hoàng Sa - Trường Sa)'
    'alert_data.zip'              = 'Dữ liệu cảnh báo giao thông'
    'sounds.zip'                  = 'Âm thanh'
}
$Extras = @('alert_data.zip', 'sounds.zip')

# ---------------------------------------------------------------- tiện ích
function Say([string]$s, [string]$color = 'Gray') { Write-Host $s -ForegroundColor $color }
function Ok([string]$s) { Write-Host ([string][char]0x2714 + ' ' + $s) -ForegroundColor Green }
function Warn([string]$s) { Write-Host ([string][char]0x26A0 + ' ' + $s) -ForegroundColor Yellow }
function Head([string]$s) { Write-Host ''; Write-Host ('== ' + $s + ' ==') -ForegroundColor Cyan }

function Format-Size([double]$b) {
    if ($b -le 0) { return '?' }
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    return ('{0:N1} MB' -f ($b / 1MB))
}

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]' -or $a.Length -eq 0) { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

# Chạy adb, trả về toàn bộ đầu ra (stdout + stderr)
function Run-Adb([string[]]$a, [int]$timeoutSec = 300) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Adb
    $full = @()
    if ($script:Serial) { $full += @('-s', $script:Serial) }
    $full += $a
    $psi.Arguments = (($full | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        throw 'adb quá thời gian chờ'
    }
    $p.WaitForExit()
    return (($o.Result + $e.Result) -replace "`r", '').Trim()
}

function Sh([string]$cmd, [int]$t = 120) { return (Run-Adb @('shell', $cmd) $t) }

function Confirm-Yes([string]$msg) {
    try {
        $r = Read-Host ($msg + ' [y = có, Enter = không]')
        return ($r -match '^(y|yes|c|co|có)$')
    } catch { return $false }
}

# ---------------------------------------------------------------- kết nối
function Connect-Car {
    if (-not (Test-Path $script:Adb)) { throw "Không thấy adb.exe tại $script:Adb" }
    Say 'Tìm màn hình xe qua cáp USB...'
    $null = & $script:Adb start-server 2>&1
    $deadline = (Get-Date).AddSeconds(60)
    $told = $false
    while ($true) {
        $list = (& $script:Adb devices 2>&1 | Out-String) -split "`n" | Select-Object -Skip 1 |
            ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' -and $_ -notmatch '^\*' }
        $devs = @()
        foreach ($l in $list) {
            $p = $l -split '\s+'
            if ($p.Count -ge 2) { $devs += [pscustomobject]@{ Serial = $p[0]; State = $p[1] } }
        }
        if ($script:Serial) { $devs = @($devs | Where-Object { $_.Serial -eq $script:Serial }) }
        $ready = @($devs | Where-Object { $_.State -eq 'device' })
        if ($ready.Count -eq 1) { $script:Serial = $ready[0].Serial; break }
        if ($ready.Count -gt 1) {
            Say 'Có nhiều thiết bị đang nối:'
            for ($i = 0; $i -lt $ready.Count; $i++) { Say ('  {0}. {1}' -f ($i + 1), $ready[$i].Serial) }
            $n = Read-Host 'Chọn số thiết bị là màn hình xe'
            $script:Serial = $ready[[int]$n - 1].Serial
            break
        }
        $unauth = @($devs | Where-Object { $_.State -eq 'unauthorized' })
        if ($unauth.Count -gt 0 -and -not $told) {
            Say 'Hãy bấm "Luôn cho phép" trên màn hình xe (chờ tối đa 60 giây)...' 'Yellow'
            $told = $true
        }
        if ((Get-Date) -gt $deadline) {
            Warn 'Chưa thấy thiết bị. Kiểm tra: xe đã chuyển cổng USB sang Device chưa, cáp đã cắm chắc, "Gỡ lỗi USB" đã bật trên xe, và đã cài driver USB cho xe (nếu máy tính chưa nhận).'
            return $false
        }
        Start-Sleep -Seconds 2
    }
    Ok ('Đã kết nối ADB: ' + $script:Serial)
    return $true
}

# ---------------------------------------------------------------- GitHub
function Invoke-GitHub([string]$url) {
    return Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'GNavi-WindowsInstall'; 'Accept' = 'application/vnd.github+json' }
}

function Get-MapRelease {
    # /releases/latest bỏ qua Pre-release nên lấy bản mới nhất từ danh sách
    $list = Invoke-GitHub "https://api.github.com/repos/$User/$MapRepo/releases?per_page=1"
    if (-not $list -or @($list).Count -eq 0) { throw 'Repo bản đồ chưa có bản phát hành' }
    $rel = @($list)[0]
    $zips = @($rel.assets | Where-Object { $_.name -like '*.zip' } | ForEach-Object { [pscustomobject]@{ Name = $_.name; Size = [double]$_.size } })
    return [pscustomobject]@{ Tag = $rel.tag_name; Zips = $zips }
}

function Download-File([string]$url, [string]$out) {
    $dir = Split-Path $out
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path $out) { Remove-Item $out -Force }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail -o $out $url
        if ($LASTEXITCODE -ne 0) { throw "Tải thất bại ($url)" }
    } else {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -Headers @{ 'User-Agent' = 'GNavi-WindowsInstall' }
    }
}

# Xóa file/thư mục tạm; phần mềm diệt virus đôi khi còn giữ file vài giây nên thử lại, không báo lỗi nếu vẫn không xóa được
function Remove-Quiet([string]$path) {
    for ($i = 0; $i -lt 6; $i++) {
        if (-not (Test-Path $path)) { return }
        try { Remove-Item $path -Recurse -Force -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 700 }
    }
}

# ---------------------------------------------------------------- các bước
function Grant-Dir {
    Say '$ thông tin hiện tại'
    Say (Sh ('id; ls -ld ' + $Gnx + ' ' + $Dir + ' 2>&1') 30)
    Say '$ cho phép xe lưu dữ liệu'
    Say (Sh ('mkdir -p ' + $Dir + '; chmod -R 777 ' + $Dir + '; echo RC=$?') 60)
    $after = Sh ('ls -ld ' + $Dir + ' 2>&1') 30
    Say $after
    if ($after.StartsWith('drwxrwxrwx')) {
        Ok ('Xong: ứng dụng trên xe giờ ghi được vào ' + $Dir + '.')
    } else {
        Warn 'Chưa thấy quyền 777. Ổ GNX có thể không hỗ trợ chmod (định dạng FAT); khi đó ứng dụng sẽ dùng thư mục riêng của nó.'
    }
}

# Điện thoại có nhiều người dùng (Thư mục bảo mật...) thì "pm list" lỗi quyền: thử lại cho người dùng 0
function Test-Installed {
    $o = Sh ('pm list packages ' + $Pkg) 30
    if ($o -match 'Error|Exception') { $o = Sh ('pm list packages --user 0 ' + $Pkg) 30 }
    return ($o -match ('package:' + [regex]::Escape($Pkg)))
}

function Test-Conflict([string]$out) {
    return ($out -match 'UPDATE_INCOMPATIBLE|INCONSISTENT_CERTIFICATES|VERSION_DOWNGRADE|signatures|DUPLICATE_PERMISSION|CONFLICTING_PROVIDER')
}

# Cài / cập nhật G-Navi Pro. Xung đột thì hỏi rồi gỡ bản cũ cài lại. Trả về $true nếu đã cài.
function Install-Apk {
    $apk = Join-Path $Work 'g-navi-pro.apk'
    Say 'Tải g-navi-pro.apk từ GitHub...'
    Download-File "https://github.com/$User/$MainRepo/releases/latest/download/g-navi-pro.apk" $apk
    $size = (Get-Item $apk).Length
    Say ('Đẩy lên xe (' + (Format-Size $size) + ')...')
    $push = Run-Adb @('push', $apk, $TmpApk) 600
    if ($push -notmatch 'pushed|1 file') { Say $push; throw 'Đẩy file lên xe thất bại' }
    try {
        Say 'Đang cài đặt trên xe...'
        $out = Sh ('pm install -r ' + $TmpApk + ' 2>&1; echo RC=$?') 300
        Say $out
        if ($out -match 'Success') { Ok 'Đã cài G-Navi Pro lên xe.'; return $true }
        if (-not (Test-Conflict $out)) { Warn 'Cài chưa thành công, xem thông báo ở trên.'; return $false }
        Warn 'Bản G-Navi Pro đang có trên xe không cài đè được (khác chữ ký hoặc mới hơn bản trên GitHub).'
        Say 'Gỡ bản cũ rồi cài lại thì cài đặt riêng của ứng dụng trên xe sẽ mất; bản đồ và dữ liệu trong ổ GNX vẫn còn.'
        if (-not ($AllowUninstall -or (Confirm-Yes 'Gỡ bản cũ và cài lại?'))) {
            Say 'Đã hủy, giữ nguyên bản đang có trên xe.'
            return $false
        }
        Say 'Gỡ bản cũ trên xe...'
        Say (Sh ('pm uninstall ' + $Pkg + ' 2>&1') 120)
        Say 'Đang cài lại trên xe...'
        $again = Sh ('pm install ' + $TmpApk + ' 2>&1; echo RC=$?') 300
        Say $again
        if ($again -match 'Success') { Ok 'Đã gỡ bản cũ và cài bản mới lên xe.'; return $true }
        Warn 'Cài lại chưa thành công, xem thông báo ở trên.'
        return $false
    } finally {
        $null = Sh ('rm -f ' + $TmpApk) 30
    }
}

function Start-App {
    Say 'Mở G-Navi Pro trên màn hình xe...'
    $out = Sh ('monkey -p ' + $Pkg + ' -c android.intent.category.LAUNCHER 1 2>&1') 60
    if ($out -match 'Events injected') { Ok 'Đã mở G-Navi Pro trên xe.' }
    else { Warn 'Chưa tự mở được ứng dụng, bạn mở G-Navi Pro trên màn hình xe nhé.' }
}

# Chọn gói. Trả về danh sách tên gói (.zip). Âm thanh + cảnh báo luôn có sẵn; hỏi thêm vùng bản đồ.
function Select-Packs($rel) {
    $byName = @{}
    foreach ($z in $rel.Zips) { $byName[$z.Name] = $z }
    $mapPacks = @()
    foreach ($n in $Titles.Keys) { if ($byName.ContainsKey($n) -and ($Extras -notcontains $n)) { $mapPacks += $byName[$n] } }
    foreach ($z in $rel.Zips) { if (-not $Titles.Contains($z.Name)) { $mapPacks += $z } }
    $extraPacks = @($Extras | Where-Object { $byName.ContainsKey($_) } | ForEach-Object { $byName[$_] })

    $chosenMaps = @()
    if ($Maps -ne '') {
        if ($Maps -eq 'all') { $chosenMaps = $mapPacks }
        elseif ($Maps -ne 'none') {
            $want = $Maps -split '[,\s]+' | Where-Object { $_ }
            foreach ($w in $want) {
                $hit = @($mapPacks | Where-Object { $_.Name -eq $w -or $_.Name -eq ($w + '.zip') })
                if ($hit.Count -eq 0) { Warn ("Không có gói '" + $w + "' trên GitHub") } else { $chosenMaps += $hit[0] }
            }
        }
    } else {
        Head 'Chọn bản đồ theo vùng'
        for ($i = 0; $i -lt $mapPacks.Count; $i++) {
            $t = if ($Titles.Contains($mapPacks[$i].Name)) { $Titles[$mapPacks[$i].Name] } else { $mapPacks[$i].Name }
            Say ('  {0,2}. {1}  ({2})' -f ($i + 1), $t, (Format-Size $mapPacks[$i].Size))
        }
        $extraNames = ($extraPacks | ForEach-Object { $Titles[$_.Name] }) -join ', '
        Say ''
        Say ('Luôn tải kèm: ' + $extraNames) 'Green'
        $in = ''
        try { $in = Read-Host 'Nhập số vùng cần tải, cách nhau dấu cách (Enter = không tải bản đồ)' } catch { }
        foreach ($tok in ($in -split '[,\s]+' | Where-Object { $_ })) {
            $n = 0
            if ([int]::TryParse($tok, [ref]$n) -and $n -ge 1 -and $n -le $mapPacks.Count) { $chosenMaps += $mapPacks[$n - 1] }
        }
    }
    $all = @()
    $all += $chosenMaps
    $all += $extraPacks
    return @($all | Sort-Object Name -Unique)
}

# Tải từng gói, giải nén trên máy tính rồi đẩy lên xe
function Push-Packs($rel, $packs) {
    $total = 0.0
    foreach ($p in $packs) { $total += $p.Size }
    Say ('Đã chọn ' + $packs.Count + ' gói, tổng ' + (Format-Size $total) + ' (bản ' + $rel.Tag + ').')
    Say (Sh ('mkdir -p ' + $Dir + '; chmod 777 ' + $Dir + '; df ' + $Gnx + ' 2>&1') 60)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $i = 0
    foreach ($p in $packs) {
        $i++
        $label = if ($Titles.Contains($p.Name)) { $Titles[$p.Name] } else { $p.Name }
        Head ('[{0}/{1}] {2}' -f $i, $packs.Count, $label)
        $zip = Join-Path $Work $p.Name
        Download-File "https://github.com/$User/$MapRepo/releases/download/$($rel.Tag)/$($p.Name)" $zip
        $ex = Join-Path $Work ('x_' + [IO.Path]::GetFileNameWithoutExtension($p.Name))
        Remove-Quiet $ex
        Say 'Giải nén...'
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)
        $region = ($p.Name -ne 'sounds.zip' -and $p.Name -ne 'alert_data.zip')
        # gói vùng chứa "<vùng>/..." -> đích roads_map/<vùng>/...; âm thanh, cảnh báo đã kèm thư mục gốc
        $dest = if ($region -and -not (Test-Path (Join-Path $ex 'roads_map'))) { $Dir + '/roads_map' } else { $Dir }
        $null = Sh ("mkdir -p '" + $dest + "'; chmod 777 '" + $dest + "'") 60
        Say ('Đẩy lên xe: ' + $dest)
        $out = Run-Adb @('push', ($ex + '\.'), ($dest + '/')) 3600
        $last = ($out -split "`n" | Where-Object { $_ -match 'pushed|skipped' } | Select-Object -Last 1)
        if ($last) { Say ('   ' + $last) } else { Say $out }
        if ($out -match 'error|failed') { throw "Đẩy gói $($p.Name) thất bại" }
        Remove-Quiet $ex
        Remove-Quiet $zip
    }
    $null = Sh ('chmod -R 777 ' + $Dir) 600
}

# ---------------------------------------------------------------- các chế độ
function Do-Grant {
    if (-not (Connect-Car)) { return }
    Head 'Cho phép xe lưu dữ liệu'
    Grant-Dir
}

function Do-App {
    if (-not (Connect-Car)) { return }
    Head 'Cập nhật G-Navi Pro lên xe'
    if (Install-Apk) { if (-not $NoLaunch) { Start-App } }
}

function Do-Maps {
    Head 'Cập nhật bản đồ & cảnh báo'
    Say 'Lấy danh sách bản đồ từ GitHub...'
    $rel = Get-MapRelease
    $packs = Select-Packs $rel
    if ($packs.Count -eq 0) { Say 'Chưa chọn gói nào.'; return }
    if (-not (Connect-Car)) { return }
    Push-Packs $rel $packs
    Ok ('Đã tải xong ' + $packs.Count + ' gói lên xe. Mở G-Navi Pro trên xe để dùng dữ liệu mới.')
}

function Do-Kia {
    if (-not (Connect-Car)) { return }
    Head 'Kiểm tra xe'
    $installed = Test-Installed
    $ver = ''
    if ($installed) {
        $d = Sh ('dumpsys package ' + $Pkg + ' | grep versionName') 60
        if ($d -match 'versionName=(\S+)') { $ver = $Matches[1] }
    }
    $testDir = ($Dir -ne $DefaultDir)
    $gnxOk = (Sh ('ls -ld ' + $Gnx + ' 2>&1; echo RC=$?') 30) -match 'RC=0'
    $dirOk = (Sh ('ls -ld ' + $Dir + ' 2>&1; echo RC=$?') 30) -match 'RC=0'
    $verText = if ($ver) { ' (bản ' + $ver + ')' } else { '' }
    Say ('G-Navi Pro: ' + $(if ($installed) { 'đã cài' + $verText } else { 'chưa cài (cài lần đầu)' }))
    Say ('Ổ GNX: ' + $(if ($gnxOk) { 'có' } elseif ($testDir) { 'không thấy (đang chạy thử với thư mục khác)' } else { 'KHÔNG THẤY' }))
    Say ('Thư mục dữ liệu: ' + $(if ($dirOk) { 'đã có' } else { 'chưa có (sẽ tạo)' }))
    if (-not $gnxOk -and -not $testDir) {
        Warn 'Không thấy ổ GNX trên xe. Hãy cắm đúng ổ USB/thẻ có tên GNX rồi chạy lại.'
        return
    }
    Head ($(if ($installed) { 'Cập nhật' } else { 'Cài' }) + ' G-Navi Pro')
    if (-not (Install-Apk)) { return }
    Head 'Cấp quyền thư mục'
    Grant-Dir
    Head 'Tải dữ liệu'
    Say 'Lấy danh sách bản đồ từ GitHub...'
    $rel = Get-MapRelease
    $packs = Select-Packs $rel
    if ($packs.Count -eq 0) { Say 'Chưa chọn gói nào, bỏ qua bước tải dữ liệu.' }
    else { Push-Packs $rel $packs; Ok ('Đã tải xong ' + $packs.Count + ' gói lên xe.') }
    if (-not $NoLaunch) { Head 'Mở ứng dụng'; Start-App }
    Ok 'Hoàn tất cài đặt cho xe.'
}

# ---------------------------------------------------------------- menu
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Host '  G-NAVI - CÀI ĐẶT XE BẰNG CÁP USB' -ForegroundColor Red
        Write-Host '  ---------------------------------'
        Write-Host ''
        Write-Host '  Cách nối:  [Xe] ==== cáp USB ==== [Máy tính này]' -ForegroundColor White
        Write-Host '    1. Trên màn hình xe, chuyển cổng USB sang chế độ Device.'
        Write-Host '    2. Nối cáp USB từ cổng USB của xe vào máy tính.'
        Write-Host '    3. Lần đầu, màn hình xe hỏi "Cho phép gỡ lỗi USB?" - chọn Luôn cho phép.'
        Write-Host ''
        Write-Host '  [1] Cài đặt tự động cho xe KIA   (kiểm tra - cài - cấp quyền - tải dữ liệu - mở ứng dụng)' -ForegroundColor Green
        Write-Host '  [2] Cập nhật G-Navi Pro lên xe'
        Write-Host '  [3] Cập nhật bản đồ & cảnh báo'
        Write-Host '  [4] Cho phép xe lưu dữ liệu'
        Write-Host '  [Q] Thoát'
        Write-Host ''
        $c = Read-Host '  Chọn'
        switch -Regex ($c.Trim()) {
            '^1$' { Run-Safe { Do-Kia } }
            '^2$' { Run-Safe { Do-App } }
            '^3$' { Run-Safe { Do-Maps } }
            '^4$' { Run-Safe { Do-Grant } }
            '^[qQ]$' { return }
        }
    }
}

function Run-Safe([scriptblock]$b) {
    try { & $b } catch { Warn ('Lỗi: ' + $_.Exception.Message) }
    Write-Host ''
    try { Read-Host 'Nhấn Enter để quay lại menu' | Out-Null } catch { }
}

if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force -Path $Work | Out-Null }
try {
switch ($Mode) {
    'menu' { Show-Menu }
    'kia' { try { Do-Kia } catch { Warn ('Lỗi: ' + $_.Exception.Message); $script:Failed = $true } }
    'app' { try { Do-App } catch { Warn ('Lỗi: ' + $_.Exception.Message); $script:Failed = $true } }
    'maps' { try { Do-Maps } catch { Warn ('Lỗi: ' + $_.Exception.Message); $script:Failed = $true } }
    'grant' { try { Do-Grant } catch { Warn ('Lỗi: ' + $_.Exception.Message); $script:Failed = $true } }
}
} finally {
    Remove-Quiet $Work
}
if ($script:Failed) { exit 1 }
