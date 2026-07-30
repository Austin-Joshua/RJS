$base = "http://127.0.0.1:8000/api/v1"

Write-Host "M-03: Landowner cannot create parcel (expect 403)"
try {
  Invoke-WebRequest -Uri "$base/parcels" -Method Post -Headers @{
    Authorization = "Bearer demo-owner"
    "Content-Type" = "application/json"
  } -Body '{"name":"Denied","owner_user_id":"owner-1","boundary_geojson_path":"../data/Boundary.geojson"}' | Out-Null
  Write-Host "Unexpected: landowner create parcel succeeded"
} catch {
  if ($_.Exception.Response) {
    $statusCode = [int]$_.Exception.Response.StatusCode
    Write-Host "Landowner create status code:" $statusCode
  } else {
    Write-Host "Landowner create request failed without HTTP response"
  }
}

Write-Host "Create parcel as consultant"
$create = Invoke-RestMethod -Uri "$base/parcels" -Method Post -Headers @{
  Authorization = "Bearer demo-consultant"
  "Content-Type" = "application/json"
} -Body '{"name":"Validation Parcel","owner_user_id":"owner-1","boundary_geojson_path":"../data/Boundary.geojson"}'
$parcelId = $create.id
Write-Host "Parcel ID: $parcelId"

Write-Host "M-02: AI modules confidence"
$health = Invoke-RestMethod -Uri "$base/ai/$parcelId/land-health" -Headers @{ Authorization = "Bearer demo-owner" }
$zones = Invoke-RestMethod -Uri "$base/ai/$parcelId/plant-zones" -Headers @{ Authorization = "Bearer demo-owner" }
Write-Host "Land Health confidence:" $health.land_health.confidence
Write-Host "Plant Zones confidence:" $zones.plant_zones.confidence

Write-Host "D-03: Valuation response"
$valuation = Invoke-RestMethod -Uri "$base/ai/$parcelId/valuation" -Headers @{ Authorization = "Bearer demo-owner" }
$valuation.valuation | ConvertTo-Json -Depth 5
