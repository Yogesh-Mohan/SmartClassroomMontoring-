---
name: classroom-geofence-fix
description: 'Fix Smart Classroom geofence polygon issues. Use when student UI shows classroom polygon not configured, outside classroom errors, or GeoJSON from map tools must be saved to Firestore.'
argument-hint: 'Paste your period name and geofence payload (GeoJSON or coordinate list).'
---

# Classroom Geofence Fix

## When to Use
- Student attendance shows `Classroom polygon is not configured correctly`.
- GeoJSON is available but student attendance rejects location.
- Admin attendance starts, but students always get `Outside classroom`.
- Firestore geofence docs may contain wrong key names or invalid polygon format.

## Inputs
- Period key (example: `Period 2`, `period 2`, `P2`)
- Geofence payload (GeoJSON `FeatureCollection`, `Feature`, `Polygon`, `MultiPolygon`, or coordinate list)
- Target Firestore doc path: `classroom_geofences/{period-or-default}`

## Procedure
1. Confirm runtime period mapping.
2. In Firestore, open `classroom_geofences` and verify document ID matches the period naming used by timetable.
3. Validate geofence field names in this priority order:
   - `polygon`
   - `geojson`
   - `geoJson`
   - `classroomPolygon`
   - `geometry`
   - `coordinates`
4. Save polygon payload as one of:
   - JSON string
   - Firestore Map/List object
5. Ensure coordinates have at least 3 points.
6. Start attendance from admin side and confirm session doc has `classroomPolygon` populated.
7. Submit student attendance at classroom location and verify geofence pass.

## Decision Points
- If payload is `FeatureCollection` or `Feature`: extract first polygon ring from `geometry.coordinates`.
- If payload is raw coordinate array: keep as-is.
- If student still fails geofence: test both `[lat,lng]` and `[lng,lat]` orientation.
- If period-specific doc missing: use `classroom_geofences/default` as fallback.

## Completion Checks
- `attendance_sessions/{date_period}` contains non-empty `classroomPolygon`.
- Student submit does not return `geofence-missing`.
- Student submit does not return `outside-classroom` when physically inside class.
- Firestore geofence document contains valid, parseable JSON or coordinate array.

## Quick Firestore Example
Use this structure for a period doc, such as `classroom_geofences/Period 2`:

```json
{
  "polygon": {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": {
          "type": "MultiPolygon",
          "coordinates": [
            [[[78.0479, 11.0554], [78.0483, 11.0552], [78.0480, 11.0555], [78.0479, 11.0554]]]
          ]
        }
      }
    ]
  }
}
```

## Notes
- Keep polygon small and accurate around the classroom boundary.
- Avoid duplicate consecutive points unless intentionally closing the ring.
- Prefer one primary ring for attendance validation simplicity.
