# Railway backend + Clerk publishable key defaults (override via env if needed).
param(
  [string]$ClerkKey = $(if ($env:CLERK_PUBLISHABLE_KEY) { $env:CLERK_PUBLISHABLE_KEY } else { 'pk_test_c2V0dGxpbmctaGFnZmlzaC05MC5jbGVyay5hY2NvdW50cy5kZXYk' }),
  [string]$ApiBase = $(if ($env:API_BASE_URL) { $env:API_BASE_URL } else { 'https://rjs-production.up.railway.app' })
)

Set-Location $PSScriptRoot
flutter run `
  --dart-define=API_BASE_URL=$ApiBase `
  --dart-define=CLERK_PUBLISHABLE_KEY=$ClerkKey
