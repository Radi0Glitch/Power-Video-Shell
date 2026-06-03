#================================================================
#Power Video Shell - ASCII вдеопроигрыватель для PowerShell 5.1
#Зависимости: FFMPEG C:\ffmpeg
#================================================================

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

#------------------настройки------------------
$ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"
$Script:AsciiChar = [char[]]"█▓▒░ "


Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public static class AsciiConv
{
    public static string Convert(string path, char[] chars, bool normalize)
    {
        using(Bitmap bmp = new Bitmap(path))
        {
            int w = bmp.Width, h = bmp.Height;
            Rectangle rect = new Rectangle(0, 0, w, h);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = data.Stride;
            byte[] bytes = new byte[stride * h];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            bmp.UnlockBits(data);

            int clenM1 = chars.Length - 1;
            int[] lum = new int[w * h];
            int minL = 255, maxL = 0;

            for(int y = 0; y < h; y++)
            {
                int row = y * stride;
                int rowOut = y * w;

                for(int x = 0; x < w; x++)
                {
                    int i = row + x * 3;
                    int L = (2126 * bytes[i+2] + 7152 * bytes[i+1] + 722 * bytes[i]) / 1000;
                    lum[rowOut + x] = L;
                    if(L < minL) {minL = L;}
                    if(L > maxL) {maxL = L;}
                }
            }

            int range;
            if(normalize && (maxL - minL) >= 1)
            {
                range = maxL-minL;
            }
            else
            {
                minL = 0; range = 255;
            }

            StringBuilder sb = new StringBuilder((w + 1) * h);
            for(int y = 0; y < h; y++)
            {
                int rowOut = y * w;
                for(int x = 0; x < w; x++)
                {
                    int norm = ((lum[rowOut + x] - minL) * clenM1) / range;
                    if(norm < 0){norm = 0;}
                    if(norm > clenM1) {norm = clenM1;}
                    sb.Append(chars[norm]);
                }
                sb.Append('\n');
            }
            return sb.ToString();
        }
    }
}
"@

#================================================================
#Выбор файла
#================================================================

function Select-VideoFile
{
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Выберите файл"
    $dialog.Filter = "Видео|*.mp4;*.avi;*.mov;*.webm;*.flv;*.wmv;|все файлы|*.*"
    
    if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    {
        return $dialog.FileName
    }

    return $null
}

function Select-AsciiVideoFile
{
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Выберите .asciivid файл"
    $dialog.Filter = "ASCII Видео|*.asciivid;|все файлы|*.*"
    
    if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    {
        return $dialog.FileName
    }

    return $null
}

#================================================================
#Извлечение кадров
#================================================================

function Extract-Frames
{
    param(
        [String]$VideoPath,
        [int]$Width = 200,
        [int]$Fps = 15
    )

    if(-not $VideoPath)
    {
        Write-Host "Файл не выбран" -ForegroundColor Yellow
        return $null
    }

    if(-not (Test-Path $VideoPath))
    {
        Write-Host "Файл не найден" -ForegroundColor Red
        return $null
    }

        if(-not (Test-Path $ffmpegPath))
    {
        Write-Host "ffmpeg не найден" -ForegroundColor Red
        return $null
    }

    $tempDir = Join-Path $env:TEMP "ascii_video_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    Write-Host "Видео: $VideoPath" -ForegroundColor DarkGreen
    Write-Host "извлекаю кадры в: $tempDir..." -ForegroundColor DarkGreen

    $vf = "fps=$Fps, scale=${Width}:-1, scale=iw:ih/2"
    $ffmegoutput = & $ffmpegPath -i $VideoPath -vf $vf -vsync 0 "$tempDir\frame_%05d.png" 2>&1

    if($LASTEXITCODE -ne 0)
    {
        Write-Host "Ошибка FFMPEG" -ForegroundColor Red
        $ffmegoutput | forEach-Object {Write-Host $_}
        return $null
    }

    $frames = Get-ChildItem $tempDir -Filter *.png | Sort-Object Name
    Write-Host "Готово: $($frames.Count) кадров" -ForegroundColor Green

    return [PSCustomObject]@{
        Dir = $tempDir
        Frames = $frames
        Fps = $fps
        Source = $VideoPath 
    }
}

#================================================================
#PNG -> ASCII
#================================================================

function Convert-FrameToAscii
{
    param(
        [Parameter(Mandatory)][String]$ImagePath,
        [switch]$Normalize
    )

    return [AsciiConv]::Convert($ImagePath, $Script:AsciiChar, [bool]$Normalize)
}

#================================================================
#Запись в .asciivid
#================================================================

function Convert-VideoToAscii
{
    param(
        [string]$VideoPath,
        [int]$Width = 200,
        [int]$Fps = 15,
        [switch]$Normalize,
        [string]$OutputPath
    )

    $extracted = Extract-Frames -VideoPath $VideoPath -Width $Width -Fps $Fps
    if(-not $extracted){ return $null }

    if(-not $OutputPath)
    {
        $name = if ($extracted.Source)
                {
                    [System.IO.Path]::GetFileNameWithoutExtension($extracted.Source)
                }
                else
                {
                    "Video"
                }

        $OutputPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) `
                                "${name}_$(Get-Date -Format 'yyyyMMdd_HHmmss').asciivid"
    }

    $total = $extracted.Frames.Count
    Write-Host "Конвертирую $total кадров -> $OutputPath" -ForegroundColor DarkGreen

    $stream = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::Unicode)
    try 
    {
        $stream.WriteLine("ASCIIVID|$Fps|$total")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $i = 0;
        foreach($f in $extracted.Frames)
        {
            $i++
            $ascii = if($Normalize)
                     {
                        Convert-FrameToAscii -ImagePath $f.FullName -Normalize
                     }
                     else
                     {
                        Convert-FrameToAscii -ImagePath $f.FullName
                     }
            
            $stream.WriteLine("---FRAME---")
            $stream.Write($ascii)

            if($i % 10 -eq 0)
            {
                $eta = [int](($sw.Elapsed.TotalSeconds / $i) * ($total - $i))
                Write-Progress -Activity "Конвертация в ASCII" `
                -Status "кадр $i из $total (осталось ~$eta сек)" `
                -PercentComplete (($i / $total) * 100)
            }
        }
        $sw.Stop()

        Write-Progress -Activity "Конвертация в ASCII" -Completed
        Write-Host ("Готово за {0:N1} сек" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    } 
    Finally
    {
        $stream.Close()
    }  

    Remove-Item $extracted.Dir -Recurse -Force -ErrorAction SilentlyContinue
    Return $OutputPath
}


# ============================================================
# Воспроизведение .asciivid
# ============================================================
function Play-AsciiVideo {
    param(
        [string]$Path
    )

    if (-not $Path) {
        $Path = Select-AsciiVideoFile
        if (-not $Path) { return }
    }
    if (-not (Test-Path $Path)) {
        Write-Host "Файл не найден: $Path" -ForegroundColor Red; return
    }

    Write-Host "Загружаю..." -ForegroundColor Cyan
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)

    $header = $lines[0].Split('|')
    if ($header[0] -ne 'ASCIIVID') {
        Write-Host "Неверный формат файла" -ForegroundColor Red; return
    }
    $fps = [int]$header[1]
    $delayMs = [int](1000 / $fps)

    # Собираем кадры
    $frames = New-Object 'System.Collections.Generic.List[string]'
    $sb = New-Object System.Text.StringBuilder
    for ($i = 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -eq '---FRAME---') {
            if ($sb.Length -gt 0) {
                [void]$frames.Add($sb.ToString()); [void]$sb.Clear()
            }
        } else {
            [void]$sb.AppendLine($lines[$i])
        }
    }
    if ($sb.Length -gt 0) { [void]$frames.Add($sb.ToString().TrimEnd("`r", "`n")) }

    Write-Host "Загружено $($frames.Count) кадров. FPS=$fps. Старт через 1 сек..." -ForegroundColor Green
    Start-Sleep -Seconds 1

    [Console]::Clear()
    [Console]::CursorVisible = $false

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt $frames.Count; $i++) {
            [Console]::SetCursorPosition(0, 0)
            [Console]::Out.Write($frames[$i])

            $targetMs = ($i + 1) * $delayMs
            $waitMs = $targetMs - $sw.ElapsedMilliseconds
            if ($waitMs -gt 0) { Start-Sleep -Milliseconds $waitMs }
        }
    }
    finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
        Write-Host "`nВоспроизведение завершено." -ForegroundColor Green
    }
}

# ============================================================
# Главное меню
# ============================================================
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host " POWER VIDEO SHELL" -ForegroundColor Cyan
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " 1. Конвертировать видео в .asciivid"
        Write-Host " 2. Воспроизвести .asciivid"
        Write-Host " 3. Конвертировать и сразу воспроизвести"
        Write-Host " 0. Выход"
        Write-Host ""
        $choice = Read-Host "Выбор"

        switch ($choice) {
            '1' {
                $video = Select-VideoFile
                $w = Read-Host "Ширина (по умолчанию 200)"
                if (-not $w) { $w = 200 } else { $w = [int]$w }
                $f = Read-Host "FPS (по умолчанию 15)"
                if (-not $f) { $f = 15 } else { $f = [int]$f }
                $n = Read-Host "Нормализация контраста? (y/n, по умолчанию y)"
                $norm = ($n -ne 'n')
                if ($norm) {
                    Convert-VideoToAscii -VideoPath $video -Width $w -Fps $f -Normalize | Out-Null
                } else {
                    Convert-VideoToAscii -VideoPath $video -Width $w -Fps $f | Out-Null
                }
                Read-Host "`nEnter для возврата в меню"
            }
            '2' {
                $asc = Select-AsciiVideoFile
                Play-AsciiVideo -Path $asc
                Read-Host "`nEnter для возврата в меню"
            }
            '3' {
                $video = Select-VideoFile 
                $w = Read-Host "Ширина (по умолчанию 200)"
                if (-not $w) { $w = 200 } else { $w = [int]$w }
                $f = Read-Host "FPS (по умолчанию 15)"
                if (-not $f) { $f = 15 } else { $f = [int]$f }
                $file = Convert-VideoToAscii -VideoPath $video -Width $w -Fps $f -Normalize
                if ($file) {
                    Read-Host "`nEnter для запуска воспроизведения"
                    Play-AsciiVideo -Path $file
                    Read-Host "`nEnter для возврата в меню"
                }
            }
            '0' { return }
            default { Write-Host "Неверный выбор" -ForegroundColor Yellow; Start-Sleep 1 }
        }
    }
}

# ============================================================
# Точка входа
# ============================================================

Show-Menu
