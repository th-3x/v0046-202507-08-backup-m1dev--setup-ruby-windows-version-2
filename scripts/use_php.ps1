# PowerShell script to add PHP to the current session's PATH
$phpPath = "C:\xampp\php"
$env:PATH = "$phpPath;$env:PATH"

Write-Host "Switching to PHP at: $phpPath"
# Verify PHP version
try {
    php -v
    Write-Host "`nPHP is now active in this terminal session."
    Write-Host "This change only affects the current terminal window."
} catch {
    Write-Host "`nError: Failed to execute PHP. Please verify the path: $phpPath" -ForegroundColor Red
}
