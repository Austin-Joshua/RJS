# Railway backend + Clerk publishable key defaults (override via env if needed).
param(
  [string]$ClerkKey = $(if ($env:CLERK_PUBLISHABLE_KEY) { $env:CLERK_PUBLISHABLE_KEY } else { 'pk_test_c2V0dGxpbmctaGFnZmlzaC05MC5jbGVyay5hY2NvdW50cy5kZXYk' }),
  [string]$ApiBase = $(if ($env:API_BASE_URL) { $env:API_BASE_URL } else { 'https://rjs-production.up.railway.app' }),
  [string]$DevToken = $(if ($env:DEV_LOGIN_TOKEN) { $env:DEV_LOGIN_TOKEN } else { 't8DldZzFcIWlNyBluc0aOdyLaXFMel0J' }),
  [string]$DevUser = $(if ($env:DEV_LOGIN_USER) { $env:DEV_LOGIN_USER } else { 'demo-farmer' })
)

Set-Location $PSScriptRoot
flutter run `
  --dart-define=API_BASE_URL=$ApiBase `
  --dart-define=CLERK_PUBLISHABLE_KEY=$ClerkKey `
  --dart-define=DEV_LOGIN_TOKEN=$DevToken `
  --dart-define=DEV_LOGIN_USER=$DevUser
